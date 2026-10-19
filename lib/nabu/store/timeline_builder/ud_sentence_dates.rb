# frozen_string_literal: true

require "json"

require_relative "../../period_bands"

module Nabu
  module Store
    module TimelineBuilder
      # The UD treebanks' sentence-comment dates and places → the timeline.
      # A UD document is one split FILE (train/dev/test) holding many
      # upstream texts, so the dating claims ride the passages: the
      # ConlluParser's METADATA_COMMENTS whitelist carries each sentence's
      # date (newdoc-scoped, so every sentence of a dated letter carries
      # its letter's date) into passage annotations, and this lane projects
      # them FROM THE CATALOG (the NikhEntryDates stance — annotations are
      # load-verified f(canonical); no re-parse, no revision bump).
      #
      # The claims (census of canonical/ud, 2026-10-19):
      #   date_created  birchbark — 1,203 letters in 25 bands ("1180-1200",
      #                 "1025-1050", "after 1400", "before 1300")
      #   created       rnc 56 / ruthenian 4 ("1652", "1698-05-02",
      #                 "1630—1635", "1391.08.25;1500-1600" — alternatives)
      #   date          ruthenian 79 ("1653", "1652-1653"); egyptian-pc
      #                 3,089 ("5th Dynasty" 1,258 / "6th Dynasty" 1,831 —
      #                 banded through config/period_bands.yml)
      #   place         egyptian-pc — "Saqqara" on all 3,089
      # Every claim dates the text itself (the letter, the charter, the
      # pyramid inscription) — the artifact class (date_class NULL).
      #
      # Rows (axis_source "ud-sentences"):
      #   * a passage-grain run per stretch of consecutive sentences sharing
      #     one claim (upstream document id + date + place) — a sentence
      #     without a claim BREAKS the run, never silently covered;
      #   * one document-grain ENVELOPE row (min..max of the runs; the
      #     distinct places joined "; ", the multi-place convention). A
      #     document whose single run covers every sentence keeps only the
      #     envelope — the run would restate it.
      # A claim the grammar cannot read (prose, an unruled period label)
      # mints no bounds; with a place it still rows (place-only).
      module UdSentenceDates
        SLUG = "ud"
        AXIS_SOURCE = "ud-sentences"

        # First present wins (no sentence carries two of them).
        DATE_KEYS = %w[date_created created date].freeze
        PLACE_KEY = "place"
        DOCUMENT_KEY = "newdoc_id"

        PROBE_FIELDS = (DATE_KEYS + [PLACE_KEY]).freeze

        YEAR = /\A(\d{3,4})\z/
        # "1698-05-02" / "1391.08.25" — a dated day: its year is the grain
        # (the day rides date_raw).
        DAY = /\A(\d{3,4})[-.]\d{2}[-.]\d{2}\z/
        RANGE = /\A(\d{3,4})\s*[-–—]\s*(\d{3,4})\z/
        AFTER = /\Aafter\s+(\d{3,4})\z/i
        BEFORE = /\Abefore\s+(\d{3,4})\z/i

        BATCH = 2_000

        module_function

        # Returns {documents:, runs:, undated:} — documents gaining an
        # envelope row, passage-grain runs, sentences carrying a claim the
        # grammar could not read (the honest residue).
        def build(catalog:, canonical_dir: nil) # rubocop:disable Lint/UnusedMethodArgument
          counts = { documents: 0, runs: 0, undated: 0 }
          source_id = catalog[:sources].where(slug: SLUG).get(:id)
          return counts if source_id.nil?

          buffer = []
          claimed_documents(catalog, source_id).each do |document_id|
            buffer.concat(document_rows(catalog, document_id, counts))
            if buffer.size >= BATCH
              catalog[:document_axes].multi_insert(buffer)
              buffer = []
            end
          end
          catalog[:document_axes].multi_insert(buffer) unless buffer.empty?
          counts
        end

        # The per-source seam (the MetadataDates contract): drop this lane's
        # rows, re-project. Returns rows inserted; 0 for any other slug.
        def refresh_source!(catalog:, slug:)
          return 0 unless slug == SLUG

          catalog[:document_axes].where(axis_source: AXIS_SOURCE).delete
          outcome = build(catalog: catalog)
          outcome[:documents] + outcome[:runs]
        end

        # Live documents with at least one passage whose annotations name a
        # claim key (a LIKE superset probe — the JSON parse decides).
        def claimed_documents(catalog, source_id)
          probe = Sequel.|(*PROBE_FIELDS.map { |field| Sequel.like(:annotations_json, %(%"#{field}"%)) })
          documents = catalog[:documents].where(source_id: source_id, withdrawn: false).select(:id)
          catalog[:passages].where(document_id: documents, withdrawn: false).where(probe)
                            .distinct.order(:document_id).select_map(:document_id)
        end

        def document_rows(catalog, document_id, counts)
          runs, total = scan_runs(catalog, document_id, counts)
          return [] if runs.empty?

          counts[:documents] += 1
          rows = [envelope_row(document_id, runs)]
          return rows if runs.size == 1 && runs.first[:from_seq].zero? && runs.first[:span] == total

          counts[:runs] += runs.size
          rows + runs.map { |run| run_row(document_id, run) }
        end

        # Walk the document's live passages in order, folding consecutive
        # identical claims into runs. Returns [runs, passage count].
        def scan_runs(catalog, document_id, counts)
          runs = []
          current = nil
          total = 0
          catalog[:passages].where(document_id: document_id, withdrawn: false)
                            .order(:sequence).select_map(%i[sequence annotations_json])
                            .each do |sequence, json|
                              total += 1
                              claim = passage_claim(json, counts)
                              if claim.nil?
                                runs << current if current
                                current = nil
                              elsif current && current[:key] == claim[:key] && current[:to_seq] == sequence - 1
                                current[:to_seq] = sequence
                                current[:span] += 1
                              else
                                runs << current if current
                                current = claim.merge(from_seq: sequence, to_seq: sequence, span: 1)
                              end
                            end
          runs << current if current
          [runs, total]
        end

        # The sentence's claim — {key:, raw:, bounds:, place:} — or nil when
        # it names neither a readable date nor a place.
        def passage_claim(json, counts)
          annotations = JSON.parse(json.to_s)
          raw = DATE_KEYS.lazy.map { |key| annotations[key] }.find { |value| value.is_a?(String) && !value.empty? }
          place = annotations[PLACE_KEY]
          place = nil unless place.is_a?(String) && !place.strip.empty?
          bounds = raw && claim_bounds(raw)
          counts[:undated] += 1 if raw && bounds.nil?
          return nil if bounds.nil? && place.nil?

          { key: [annotations[DOCUMENT_KEY], raw, place], raw: bounds && raw, bounds: bounds, place: place }
        rescue JSON::ParserError
          nil
        end

        # A date claim → [not_before, not_after, precision], or nil. ";"
        # separates alternatives (rnc's "1391.08.25;1500-1600" — the
        # original's day and its copy's century): every alternative must
        # read, and the envelope spans them all.
        def claim_bounds(raw)
          alternatives = raw.split(";").map(&:strip)
          spans = alternatives.map { |alternative| alternative_bounds(alternative) }
          return nil if spans.empty? || spans.include?(nil)
          return spans.first if spans.size == 1

          lowers = spans.map(&:first)
          uppers = spans.map { |span| span[1] }
          [lowers.include?(nil) ? nil : lowers.min, uppers.include?(nil) ? nil : uppers.max, "range"]
        end

        def alternative_bounds(text)
          case text
          when YEAR, DAY
            year = Integer(::Regexp.last_match(1), 10)
            [year, year, "year"]
          when RANGE then ordered(Integer(::Regexp.last_match(1), 10), Integer(::Regexp.last_match(2), 10))
          when AFTER then [Integer(::Regexp.last_match(1), 10), nil, "range"]
          when BEFORE then [nil, Integer(::Regexp.last_match(1), 10), "range"]
          else period_bounds(text)
          end
        end

        def ordered(from, to)
          from <= to ? [from, to, "range"] : nil
        end

        # A period label through the ruled table; a dynasty label wears
        # precision "dynasty" (the AED header lane's grain name).
        def period_bounds(text)
          band = Nabu::PeriodBands.default&.lookup(text)
          return nil if band.nil?

          [band[0], band[1], text.match?(/Dynasty/i) ? "dynasty" : "period"]
        end

        # NB: every row carries the SAME column set (multi_insert takes its
        # columns from the first row).
        def envelope_row(document_id, runs)
          dated = runs.select { |run| run[:bounds] }
          places = runs.filter_map { |run| run[:place] }.uniq
          row(document_id, envelope_bounds(dated), envelope_raw(dated), places.empty? ? nil : places.join("; "),
              nil, nil)
        end

        def run_row(document_id, run)
          row(document_id, run[:bounds], run[:raw], run[:place], run[:from_seq], run[:to_seq])
        end

        def row(document_id, bounds, raw, place, from_seq, to_seq)
          { document_id: document_id,
            not_before: bounds&.at(0), not_after: bounds&.at(1), precision: bounds&.at(2),
            date_raw: raw, place_name: place,
            passage_seq_from: from_seq, passage_seq_to: to_seq,
            axis_source: AXIS_SOURCE }
        end

        def envelope_bounds(dated)
          return nil if dated.empty?
          return dated.first[:bounds] if dated.map { |run| run[:bounds] }.uniq.size == 1

          lowers = dated.map { |run| run[:bounds][0] }
          uppers = dated.map { |run| run[:bounds][1] }
          [lowers.include?(nil) ? nil : lowers.min, uppers.include?(nil) ? nil : uppers.max, "range"]
        end

        # One claim → its raw; several → the earliest and latest claims'
        # raws ("1160-1180 … 1420-1430").
        def envelope_raw(dated)
          raws = dated.map { |run| run[:raw] }.uniq
          return raws.first if raws.size <= 1

          first = dated.min_by { |run| run[:bounds][0] || -Float::INFINITY }[:raw]
          last = dated.max_by { |run| run[:bounds][1] || Float::INFINITY }[:raw]
          first == last ? first : "#{first} … #{last}"
        end
      end
    end
  end
end
