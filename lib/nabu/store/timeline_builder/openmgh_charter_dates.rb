# frozen_string_literal: true

require "json"

module Nabu
  module Store
    module TimelineBuilder
      # The openMGH Diplomata charters at passage grain. Each charter
      # passage carries its edition's German dating line verbatim ("date")
      # and, where the line reads cleanly, the structured claims the
      # adapter's OpenmghCharterDate reader minted beside it at parse —
      # "not_before"/"not_after" (integer years; one may be open) and the
      # issuing "place". This lane projects them from the CATALOG
      # (annotations are load-verified f(canonical); the NikhEntryDates
      # stance — no re-parse here):
      #
      #   * every bounded charter → one passage-grain row (passage_seq_from
      #     = passage_seq_to = its sequence), the dating line as date_raw,
      #     the issuing place as place_name — the places lane's verbatim
      #     claim, gazetteer resolution left to that lane. date_class stays
      #     NULL: the charter's own issue date is the artifact's date, unlike
      #     the volume's print year (MetadataDates, date_class "edition").
      #   * every volume with ≥1 bounded charter → one document-grain
      #     ENVELOPE row first (the ChronicleAnnals mold): min..max over the
      #     charters' known bounds (an open "vor 1162" bound contributes its
      #     closed side only), no place — so document-grain readers see the
      #     volume's medieval span once, beside its edition row.
      #
      # Census 2026-10-19 (a full parse of canonical/openmgh): 2,808 charter
      # passages in 13 Diplomata volumes; 2,037 carry a dating line — 1,915
      # bounded (1,633 placed), 122 verbatim-only (hedged or unreadable,
      # counted as +unbounded+) — and 771 carry none (the three DD F. II.
      # volumes' bare <date/>, counted as +undated+).
      #
      # axis_source is "openmgh-charters", NOT the bare slug — MetadataDates
      # refresh deletes by its own axis_source ("openmgh", the edition row),
      # and the two lanes must never orphan each other's rows.
      module OpenmghCharterDates
        SLUG = "openmgh"
        AXIS_SOURCE = "openmgh-charters"

        # Only charter passages carry the addressing marker this probes for.
        CHARTER_PROBE = '%"charter-number"%'

        BATCH = 2_000

        module_function

        # {documents:, charters:, unbounded:, undated:} — envelopes minted,
        # passage rows minted, dating lines left verbatim-only, charters with
        # no dating line at all.
        def build(catalog:, canonical_dir: nil) # rubocop:disable Lint/UnusedMethodArgument
          counts = { documents: 0, charters: 0, unbounded: 0, undated: 0 }
          source_id = catalog[:sources].where(slug: SLUG).get(:id)
          return counts if source_id.nil?

          buffer = []
          catalog[:documents].where(source_id: source_id, withdrawn: false).order(:id).select_map(:id).each do |id|
            buffer.concat(document_rows(catalog, id, counts))
            next if buffer.size < BATCH

            catalog[:document_axes].multi_insert(buffer)
            buffer = []
          end
          catalog[:document_axes].multi_insert(buffer) unless buffer.empty?
          counts
        end

        # The per-source seam (the MetadataDates contract): drop this lane's
        # rows, re-project. Returns rows inserted; 0 for any other slug.
        def refresh_source!(catalog:, slug:)
          return 0 unless slug == SLUG

          catalog[:document_axes].where(axis_source: AXIS_SOURCE).delete
          counts = build(catalog: catalog)
          counts[:documents] + counts[:charters]
        end

        def document_rows(catalog, document_id, counts)
          charters = charter_rows(catalog, document_id, counts)
          return [] if charters.empty?

          counts[:documents] += 1
          counts[:charters] += charters.size
          [envelope_row(document_id, charters), *charters]
        end

        def charter_rows(catalog, document_id, counts)
          catalog[:passages]
            .where(document_id: document_id, withdrawn: false)
            .where(Sequel.like(:annotations_json, CHARTER_PROBE))
            .order(:sequence).select_map(%i[sequence annotations_json])
            .filter_map do |sequence, json|
              annotations = JSON.parse(json.to_s)
              row = charter_row(document_id, sequence, annotations)
              tally(counts, annotations) if row.nil?
              row
            end
        end

        def tally(counts, annotations)
          annotations["date"] ? counts[:unbounded] += 1 : counts[:undated] += 1
        end

        # NB: every row carries the SAME column set (multi_insert takes its
        # columns from the first row).
        def charter_row(document_id, sequence, annotations)
          not_before = annotations["not_before"]
          not_after = annotations["not_after"]
          return nil if not_before.nil? && not_after.nil?

          { document_id: document_id, not_before: not_before, not_after: not_after,
            precision: not_before == not_after ? "year" : "range",
            date_raw: annotations["date"], place_name: annotations["place"],
            passage_seq_from: sequence, passage_seq_to: sequence, axis_source: AXIS_SOURCE }
        end

        def envelope_row(document_id, charters)
          { document_id: document_id,
            not_before: charters.filter_map { |row| row[:not_before] }.min,
            not_after: charters.filter_map { |row| row[:not_after] }.max,
            precision: "range", date_raw: "#{charters.first[:date_raw]} – #{charters.last[:date_raw]}",
            place_name: nil, passage_seq_from: nil, passage_seq_to: nil, axis_source: AXIS_SOURCE }
        end
      end
    end
  end
end
