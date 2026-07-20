# frozen_string_literal: true

require "nokogiri"

require_relative "../../timeline"
require_relative "../../normalize"

module Nabu
  module Store
    module TimelineBuilder
      # I.Sicily dating + findspot → the timeline (P29-4) — the
      # RiigDates shape (per-record EpiDoc, DOM over tiny files) with the
      # corpus's own attribute dialect: origDate carries
      # notBefore-custom/notAfter-custom (datingMethod="#julian", signed
      # historical years, zero-padded, 2,117 BCE records at the pinned
      # census; 3 records use the plain attributes — the fallback). Reads
      # canonical/isicily/inscriptions/*.xml and joins filename →
      # urn:nabu:isicily:<id> → document_id, one document-grain row per
      # dated OR placed document — metadata-only records included (their
      # header is most of their machine-readable value: Sicel 212/299).
      #
      # - Bounds via the ENVELOPE policy across every origin origDate
      #   (6 multi-date records; alternatives widen, never a midpoint).
      #   precision: "exact" for a point, else "range". date_raw = the
      #   first date's own display text ("between later 1st and 3rd
      #   century CE"). Year 0 ("-0000", 1 record) is the Timeline
      #   tripwire: skipped, counted invalid, never stored; ISO-shaped
      #   values ("0160-12-10") contribute their leading signed year.
      # - place_name = the ancient placeName (the corpus's own
      #   identification, "Selinus"), modern as fallback; place_ref = the
      #   ancient @ref (Pleiades) else the modern @ref (GeoNames) — http
      #   URLs only ("..." placeholders on 60 records are dropped),
      #   verbatim strings, no gazetteer resolution (the §1.4 stance).
      #   WGS84 <geo> stays canonical + document metadata (the EDH
      #   no-coordinate-columns decision).
      module IsicilyDates
        ISICILY_SLUG = "isicily"
        URN_PREFIX = "urn:nabu:isicily:"
        RECORDS_GLOB = File.join("isicily", "inscriptions", "ISic*.xml")

        module_function

        # Walk the canonical records, insert one timeline row per dated/placed
        # document. Returns { documents:, undated:, invalid: } — +undated+
        # counts joined records with a place-only row or no row, +invalid+
        # the year-0 tripwire skips.
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

          TimelineBuilder.insert_timeline(catalog, document_id, timeline, ISICILY_SLUG)
          counts[:documents] += 1
        end

        # One record's timeline fields; nil when it carries neither date nor
        # place, :invalid on the year-0 tripwire.
        def extract(xml)
          doc = Nokogiri::XML(xml)
          doc.remove_namespaces!
          begin
            bounds = envelope(doc.xpath("//origin/origDate"))
          rescue Timeline::InvalidYear
            return :invalid
          end
          place_name, place_ref = extract_place(doc)
          return nil if bounds[:not_before].nil? && bounds[:not_after].nil? && place_name.nil?

          {
            not_before: bounds[:not_before], not_after: bounds[:not_after],
            precision: bounds[:not_before] || bounds[:not_after] ? bounds[:precision] : nil,
            date_raw: bounds[:date_raw],
            place_name: place_name, place_ref: place_ref
          }
        end

        # TimelineBuilder.envelope's policy over the -custom dialect: min of
        # all lowers, max of all uppers; the plain attributes only answer
        # where the -custom ones are absent.
        def envelope(dates)
          lowers = []
          uppers = []
          raw = nil
          ranged = false
          dates.each do |node|
            not_before = Timeline.parse_year(node["notBefore-custom"] || node["notBefore"])
            not_after = Timeline.parse_year(node["notAfter-custom"] || node["notAfter"])
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

        def extract_place(doc)
          origin = doc.at_xpath("//origin/origPlace")
          return [nil, nil] if origin.nil?

          ancient = origin.at_xpath("./placeName[@type='ancient']")
          modern = origin.at_xpath("./placeName[@type='modern']")
          name = TimelineBuilder.normalize(ancient&.text)
          name ||= TimelineBuilder.normalize(modern&.text)
          [name, name ? place_ref(ancient, modern) : nil]
        end

        # Pleiades (the ancient identification) wins over GeoNames (the
        # modern commune); http URLs only — "..." placeholders drop.
        def place_ref(ancient, modern)
          [ancient&.attr("ref"), modern&.attr("ref")]
            .map { |value| value.to_s.strip }
            .find { |value| value.start_with?("http") }
        end
      end
    end
  end
end
