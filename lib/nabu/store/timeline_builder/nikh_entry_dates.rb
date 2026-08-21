# frozen_string_literal: true

require "json"

module Nabu
  module Store
    module TimelineBuilder
      # The NIKH chronicle family's leaf grain (P81-1, the dating harvest).
      # The five Korean-historiography sources (sillok, sjw, bibyeonsa and
      # the two goryeosa compilations) carry per-entry machine dates in
      # their dateOccured @date attrs — "1617-01-00L0" (lunar-calendar
      # year-month-day + leap-month flag; "00"/"99" mark unknown parts,
      # "9999" is upstream's no-date filler) — which the adapters ride in
      # passage annotations RAW. This extractor projects them from the
      # CATALOG (annotations are load-verified f(canonical); no re-parse,
      # no revision bump — the MetadataDates stance at the leaf grain):
      #
      #   * consecutive same-YEAR entries become one passage-grain run row
      #     (the ChronicleAnnals mold; year is the schema's honest grain —
      #     bounds are integer years, the day rides date_raw). Interleaved
      #     years (bb_001, censused 2026-08-18) never merge; an undated
      #     entry BREAKS the run rather than being silently covered.
      #   * a document with NO metadata date claim (bibyeonsa books, the
      #     goryeosa family, sillok's undated prefaces/indexes) gains one
      #     document-grain ENVELOPE row (min..max entry year), inserted
      #     before its runs. Documents already dated by MetadataDates
      #     (:structured 서기 envelopes) keep that as their document grain.
      #
      # axis_source is "<slug>-entries", NOT the bare slug — MetadataDates
      # refresh deletes by its own axis_source, and the two lanes must
      # never orphan each other's rows.
      #
      # Cost at live scale (measured 2026-08-21 census): ~2.45M annotated
      # passages across the five sources — one streamed pass per source at
      # rebuild (the "timeline" stage) or per synced source post-load;
      # ~5-6k rows minted, JSON parse dominated.
      module NikhEntryDates
        SLUGS = %w[sillok sjw bibyeonsa goryeosa goryeosa-jeoryo].freeze

        AXIS_SUFFIX = "-entries"

        # Entry years live 877 (goryeosa's Taejo prehistory) .. 1928
        # (sillok's colonial-era supplements); the bracket generously
        # covers the family while excluding the 9999 filler and any
        # degenerate 0000.
        YEAR_PLAUSIBLE = (800..2000)

        YEAR_PREFIX = /\A(\d{4})/

        BATCH = 2_000

        module_function

        # {slug => {documents:, runs:, undated_entries:}} for the family.
        # +documents+ counts envelope rows minted (newly document-grain-
        # dated documents); +undated_entries+ the honest residue.
        def build(catalog:, canonical_dir: nil) # rubocop:disable Lint/UnusedMethodArgument
          SLUGS.to_h { |slug| [slug, build_source(catalog, slug)] }
        end

        # The per-source seam (the MetadataDates contract): drop this
        # source's entry rows, re-project. Returns rows inserted; 0 for a
        # slug outside the family.
        def refresh_source!(catalog:, slug:)
          return 0 unless SLUGS.include?(slug)

          catalog[:document_axes].where(axis_source: slug + AXIS_SUFFIX).delete
          outcome = build_source(catalog, slug)
          outcome[:documents] + outcome[:runs]
        end

        def build_source(catalog, slug)
          counts = { documents: 0, runs: 0, undated_entries: 0 }
          source_id = catalog[:sources].where(slug: slug).get(:id)
          return counts if source_id.nil?

          buffer = []
          catalog[:documents]
            .where(source_id: source_id, withdrawn: false)
            .select(:id, :metadata_json).order(:id)
            .paged_each do |doc|
              buffer.concat(document_rows(catalog, doc, slug, counts))
              if buffer.size >= BATCH
                catalog[:document_axes].multi_insert(buffer)
                buffer = []
              end
            end
          catalog[:document_axes].multi_insert(buffer) unless buffer.empty?
          counts
        end

        # One document's rows — envelope (when the metadata lane makes no
        # claim) first, then the year runs.
        def document_rows(catalog, doc, slug, counts)
          runs, undated = scan_runs(catalog, doc[:id])
          counts[:undated_entries] += undated
          return [] if runs.empty?

          axis_source = slug + AXIS_SUFFIX
          rows = []
          unless metadata_dated?(doc[:metadata_json])
            rows << envelope_row(doc[:id], runs, axis_source)
            counts[:documents] += 1
          end
          counts[:runs] += runs.size
          rows + runs.map { |run| run_row(doc[:id], run, axis_source) }
        end

        # Walk the document's live passages in reading order, folding
        # consecutive same-year entries into runs. Returns [runs, undated].
        def scan_runs(catalog, document_id)
          runs = []
          undated = 0
          current = nil
          catalog[:passages]
            .where(document_id: document_id, withdrawn: false)
            .order(:sequence).select_map(%i[sequence annotations_json])
            .each do |sequence, annotations_json|
              year, date = entry_date(annotations_json)
              if year.nil?
                undated += 1
                # an undated entry breaks the run — a year claim never
                # silently covers a passage that carries none
                runs << current if current
                current = nil
              elsif current && current[:year] == year
                current[:to_seq] = sequence
                current[:last] = date
              else
                runs << current if current
                current = { year: year, from_seq: sequence, to_seq: sequence, first: date, last: date }
              end
            end
          runs << current if current
          [runs, undated]
        end

        # [year, raw date string] when the annotation carries a plausible
        # machine date, else [nil, nil] — filler ("9999-…"), dateless
        # entries and unparseable JSON all land in the undated count.
        def entry_date(annotations_json)
          date = JSON.parse(annotations_json.to_s)["date"].to_s
          match = YEAR_PREFIX.match(date) or return [nil, nil]

          year = Integer(match[1], 10)
          YEAR_PLAUSIBLE.cover?(year) ? [year, date] : [nil, nil]
        rescue JSON::ParserError
          [nil, nil]
        end

        # Does documents.metadata_json already claim date bounds (the
        # MetadataDates :structured shape)? Then the document grain is
        # that lane's, not ours.
        def metadata_dated?(metadata_json)
          date = JSON.parse(metadata_json.to_s)["date"]
          date.is_a?(Hash) && (date["not_before"] || date["not_after"])
        rescue JSON::ParserError
          false
        end

        # NB: every row carries the SAME column set (multi_insert takes its
        # columns from the first row — a key missing there would be dropped
        # for the whole batch).
        def envelope_row(document_id, runs, axis_source)
          dates = runs.flat_map { |run| [run[:first], run[:last]] }
          { document_id: document_id,
            not_before: runs.map { |run| run[:year] }.min,
            not_after: runs.map { |run| run[:year] }.max,
            precision: "year", date_raw: span_raw(dates.min, dates.max),
            passage_seq_from: nil, passage_seq_to: nil,
            axis_source: axis_source }
        end

        def run_row(document_id, run, axis_source)
          { document_id: document_id,
            not_before: run[:year], not_after: run[:year],
            precision: "year", date_raw: span_raw(run[:first], run[:last]),
            passage_seq_from: run[:from_seq], passage_seq_to: run[:to_seq],
            axis_source: axis_source }
        end

        def span_raw(first, last)
          first == last ? first : "#{first} – #{last}"
        end
      end
    end
  end
end
