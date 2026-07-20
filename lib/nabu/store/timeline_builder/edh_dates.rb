# frozen_string_literal: true

require "csv"

require_relative "../../timeline"
require_relative "../../normalize"

module Nabu
  module Store
    module TimelineBuilder
      # EDH dating + findspot → the timeline (P17-2, edh-survey §4.1/
      # §4.2) — the largest single timeline feed since HGV: 60,474 dated records
      # (73.3%) whose CSV year columns are ALREADY signed historical years
      # with no year 0 (survey-verified byte-level against HD080029's
      # "-0020…-0001" = "20 BC - 1 BC" — conventions §11, ingested verbatim).
      #
      # Reads canonical/edh/text/edh_data_text.csv (the corpus-wide sidecar
      # the adapter fetches; the EpiDoc origDate duplicates it) and joins
      # hd_nr → urn:nabu:edh:hd<nr> → document_id, one document-grain row per
      # dated OR placed document:
      #
      # - dat_jahr_a / dat_jahr_e → not_before / not_after. Open-ended rows
      #   (one bound empty — 3,529 notBefore-only) keep the other bound NULL.
      #   precision: "year" for a point, else "range" — width is visible in
      #   the honest bounds themselves. date_raw joins the verbatim column
      #   values ("71–130", "212–"). A literal year 0 is the Timeline
      #   tripwire: skipped, counted invalid, never stored. The 330 records
      #   dated past 640 CE (post-antique copies/forgeries EDH records as
      #   such, up to 1998) ingest verbatim — the timeline does not editorialize.
      # - place_name = the ancient findspot (fo_antik), modern (fo_modern) as
      #   fallback; place_ref = the Pleiades URL (pl_ancient_loc1) where
      #   present, else the GeoNames URL (geo_id1) — the same gazetteers the
      #   HGV/ORACC refs point at, verbatim strings, no gazetteer resolution
      #   (the §1.4 stance). Coordinates stay canonical-only (survey v2).
      #
      # Undated-and-unplaced rows contribute nothing (an absence, never a
      # row); rows whose document is not in the catalog (text-less stubs
      # discover skipped) are not counted at all.
      module EdhDates
        EDH_SLUG = "edh"
        URN_PREFIX = "urn:nabu:edh:"
        TEXT_CSV = File.join("text", "edh_data_text.csv")
        PLEIADES = "https://pleiades.stoa.org/places/"
        GEONAMES = "https://www.geonames.org/"

        module_function

        # Walk the text CSV, join hd_nr→urn→document_id, insert one
        # document-grain timeline row per dated/placed document. Returns
        # { documents:, undated:, invalid: } — +undated+ counts joined
        # documents with a place-only row or no row, +invalid+ the year-0
        # tripwire skips.
        def build(catalog:, canonical_dir:)
          path = File.join(canonical_dir, EDH_SLUG, TEXT_CSV)
          return { documents: 0, undated: 0, invalid: 0 } unless File.file?(path)

          urn_ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}%")).select_hash(:urn, :id)
          counts = { documents: 0, undated: 0, invalid: 0 }
          CSV.foreach(path, headers: true) do |row|
            document_id = urn_ids["#{URN_PREFIX}#{row['hd_nr'].to_s.strip.downcase}"] or next

            insert_row(catalog, document_id, row, counts)
          end
          counts
        end

        def insert_row(catalog, document_id, row, counts)
          timeline = extract(row)
          if timeline == :invalid
            counts[:invalid] += 1
            return
          end
          counts[:undated] += 1 if timeline.nil? || timeline[:not_before].nil?
          return if timeline.nil?

          TimelineBuilder.insert_timeline(catalog, document_id, timeline, EDH_SLUG)
          counts[:documents] += 1
        end

        # One row's timeline fields; nil when it carries neither date nor place,
        # :invalid on the year-0 tripwire.
        def extract(row)
          begin
            not_before = Timeline.parse_year(row["dat_jahr_a"])
            not_after = Timeline.parse_year(row["dat_jahr_e"])
          rescue Timeline::InvalidYear
            return :invalid
          end
          place_name, place_ref = extract_place(row)
          return nil if not_before.nil? && not_after.nil? && place_name.nil?

          {
            not_before: not_before, not_after: not_after,
            precision: precision(not_before, not_after),
            date_raw: date_raw(row, not_before, not_after),
            place_name: place_name, place_ref: place_ref
          }
        end

        def precision(not_before, not_after)
          return nil if not_before.nil? && not_after.nil?

          not_before == not_after ? "year" : "range"
        end

        # The verbatim column values, joined for display: "71–130", "212–"
        # (open-ended). nil for a place-only row.
        def date_raw(row, not_before, not_after)
          return nil if not_before.nil? && not_after.nil?

          "#{row['dat_jahr_a'].to_s.strip}–#{row['dat_jahr_e'].to_s.strip}"
        end

        def extract_place(row)
          name = TimelineBuilder.normalize(row["fo_antik"].to_s)
          name ||= TimelineBuilder.normalize(row["fo_modern"].to_s)
          [name, name ? place_ref(row) : nil]
        end

        # Pleiades (the ancient-place id) wins over GeoNames (the modern one).
        def place_ref(row)
          pleiades = row["pl_ancient_loc1"].to_s.strip
          return "#{PLEIADES}#{pleiades}" if pleiades.match?(/\A\d+\z/)

          geonames = row["geo_id1"].to_s.strip
          geonames.match?(/\A\d+\z/) ? "#{GEONAMES}#{geonames}" : nil
        end
      end
    end
  end
end
