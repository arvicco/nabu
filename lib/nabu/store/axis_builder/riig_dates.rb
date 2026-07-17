# frozen_string_literal: true

require "nokogiri"

require_relative "../../date_axis"
require_relative "../../normalize"

module Nabu
  module Store
    module AxisBuilder
      # RIIG dating + findspot → the date/place axis (P25-1) — the EDH
      # extractor's shape over per-record EpiDoc instead of a corpus CSV:
      # reads canonical/riig/documents/*.xml (428 tiny files; DOM, the HGV
      # precedent), joins filename → urn:nabu:riig:<id> → document_id, one
      # document-grain row per dated OR placed ORIGINAL document (-fr
      # siblings never join — their urns aren't minted from filenames).
      #
      # - origDate @notBefore/@notAfter (signed historical years, no year 0
      #   — "-0100"/"-0001"; @when covers a missing bound) → not_before/
      #   not_after via the ENVELOPE policy shared with HGV
      #   (AxisBuilder.envelope — alternatives widen, never a midpoint).
      #   precision: HGV's explicit @precision never appears here, so a
      #   point reads "exact" and a bounded interval "range"; date_raw = the
      #   record's own display text ("-Ier siècle"). Year 0 is the DateAxis
      #   tripwire: skipped, counted invalid, never stored.
      # - place_name = the untyped origPlace placeName (the findspot,
      #   "Chastelard de Lardiers"), settlement modern name as fallback;
      #   place_ref = the settlement's Trismegistos @corresp, else its RIIG
      #   places @ref — verbatim strings, no gazetteer resolution (the §1.4
      #   stance). WGS84 <geo> stays canonical + document metadata (the EDH
      #   coordinates decision — the axis has no coordinate columns).
      module RiigDates
        RIIG_SLUG = "riig"
        URN_PREFIX = "urn:nabu:riig:"
        DOCUMENTS_GLOB = File.join("riig", "documents", "*.xml")

        module_function

        # Walk the canonical records, insert one axis row per dated/placed
        # document. Returns { documents:, undated:, invalid: } — +undated+
        # counts joined records with a place-only row or no row, +invalid+
        # the year-0 tripwire skips.
        def build(catalog:, canonical_dir:)
          paths = Dir.glob(File.join(canonical_dir, DOCUMENTS_GLOB))
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
          axis = extract(File.read(path))
          if axis == :invalid
            counts[:invalid] += 1
            return
          end
          counts[:undated] += 1 if axis.nil? || axis[:not_before].nil?
          return if axis.nil?

          AxisBuilder.insert_axis(catalog, document_id, axis, RIIG_SLUG)
          counts[:documents] += 1
        end

        # One record's axis fields; nil when it carries neither date nor
        # place, :invalid on the year-0 tripwire.
        def extract(xml)
          doc = Nokogiri::XML(xml)
          doc.remove_namespaces!
          begin
            bounds = AxisBuilder.envelope(doc.xpath("//origin/origDate"))
          rescue DateAxis::InvalidYear
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

        def extract_place(doc)
          origin = doc.at_xpath("//origin/origPlace")
          return [nil, nil] if origin.nil?

          findspot = origin.at_xpath("./placeName[not(@type)]")
          settlement = origin.at_xpath("./settlement")
          name = AxisBuilder.normalize(findspot&.text)
          name ||= AxisBuilder.normalize(settlement&.at_xpath("./placeName")&.text)
          [name, name ? place_ref(settlement, findspot) : nil]
        end

        # Trismegistos (the settlement @corresp) wins; the RIIG places @ref
        # and the findspot's own @ref follow.
        def place_ref(settlement, findspot)
          candidates = [settlement&.attr("corresp"), settlement&.attr("ref"), findspot&.attr("ref")]
          candidates.map { |value| value.to_s.strip }.find { |value| !value.empty? }
        end
      end
    end
  end
end
