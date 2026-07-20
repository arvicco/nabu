# frozen_string_literal: true

require "nokogiri"

require_relative "../../timeline"
require_relative "../../normalize"

module Nabu
  module Store
    module TimelineBuilder
      # IIP dating + findspot → the timeline (P30-6) — the
      # IsicilyDates shape (per-record EpiDoc, DOM over tiny files) with
      # the corpus's own attribute dialect: origin/date carries PLAIN
      # notBefore/notAfter (zero-padded, signed-negative BCE — 2,218
      # files at the pinned census, zero year-0; bounds on 5,261 of
      # 5,535 records). Reads canonical/iip/epidoc-files/*.xml and joins
      # filename → urn:nabu:iip:<id> → document_id, one document-grain
      # row per dated OR placed document — metadata-only records
      # included (their header is the whole of their machine-readable
      # value).
      #
      # - Bounds via the ENVELOPE policy across every origin date (zero
      #   multi-date records today; alternatives would widen, never a
      #   midpoint). precision: "exact" for a point, else "range".
      #   date_raw = the first date's display text ("300 CE - 700 CE").
      #   A year-0 bound is the Timeline tripwire: skipped, counted
      #   invalid, never stored. The Periodo @period URIs stay in
      #   document metadata (no timeline column for them).
      # - place_name = the settlement's OWN text (upstream nests <geo>
      #   coordinates INSIDE <settlement> — they must not leak into the
      #   name), region as fallback; place_ref = nil always — the corpus
      #   carries no gazetteer refs (no Pleiades, no GeoNames), an
      #   honest absence. WGS84 <geo> stays canonical + document
      #   metadata (the EDH no-coordinate-columns decision).
      module IipDates
        IIP_SLUG = "iip"
        URN_PREFIX = "urn:nabu:iip:"
        RECORDS_GLOB = File.join("iip", "epidoc-files", "*.xml")

        module_function

        # Walk the canonical records, insert one timeline row per dated/
        # placed document. Returns { documents:, undated:, invalid: } —
        # +undated+ counts joined records with a place-only row or no
        # row, +invalid+ the year-0 tripwire skips.
        def build(catalog:, canonical_dir:)
          paths = Dir.glob(File.join(canonical_dir, RECORDS_GLOB))
          counts = { documents: 0, undated: 0, invalid: 0 }
          return counts if paths.empty?

          urn_ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}%")).select_hash(:urn, :id)
          paths.each do |path|
            document_id = urn_ids["#{URN_PREFIX}#{File.basename(path, '.xml').downcase}"] or next

            insert_row(catalog, document_id, path, counts)
          end
          counts
        end

        def insert_row(catalog, document_id, path, counts)
          timeline = extract(File.read(path))
          if timeline == :invalid
            counts[:invalid] += 1
            return
          end
          counts[:undated] += 1 if timeline.nil? || timeline[:not_before].nil?
          return if timeline.nil?

          TimelineBuilder.insert_timeline(catalog, document_id, timeline, IIP_SLUG)
          counts[:documents] += 1
        end

        # One record's timeline fields; nil when it carries neither date nor
        # place, :invalid on the year-0 tripwire.
        def extract(xml)
          doc = Nokogiri::XML(xml)
          doc.remove_namespaces!
          begin
            bounds = envelope(doc.xpath("//history/origin/date"))
          rescue Timeline::InvalidYear
            return :invalid
          end
          place_name = extract_place(doc)
          return nil if bounds[:not_before].nil? && bounds[:not_after].nil? && place_name.nil?

          {
            not_before: bounds[:not_before], not_after: bounds[:not_after],
            precision: bounds[:not_before] || bounds[:not_after] ? bounds[:precision] : nil,
            date_raw: bounds[:date_raw],
            place_name: place_name, place_ref: nil
          }
        end

        # TimelineBuilder's envelope policy over the plain attributes: min of
        # all lowers, max of all uppers (zero multi-date records at the
        # pinned census — defensive, like the multi-date sources).
        def envelope(dates)
          lowers = []
          uppers = []
          raw = nil
          ranged = false
          dates.each do |node|
            not_before = Timeline.parse_year(node["notBefore"])
            not_after = Timeline.parse_year(node["notAfter"])
            next if not_before.nil? && not_after.nil?

            lowers << not_before if not_before
            uppers << not_after if not_after
            ranged ||= not_before != not_after
            raw ||= TimelineBuilder.normalize(node.text)
          end
          {
            not_before: lowers.min, not_after: uppers.max,
            precision: ranged ? "range" : "exact", date_raw: raw
          }
        end

        # The settlement's own text (its <geo> child excluded), region as
        # fallback; nil when the record names no findspot.
        def extract_place(doc)
          origin = doc.at_xpath("//history/origin/placeName")
          return nil if origin.nil?

          settlement = origin.at_xpath("./settlement")
          own = settlement && settlement.xpath("./text()").map(&:text).join
          TimelineBuilder.normalize(own) || TimelineBuilder.normalize(origin.at_xpath("./region")&.text)
        end
      end
    end
  end
end
