# frozen_string_literal: true

require_relative "../../adapters/damaskini"

module Nabu
  module Store
    module AxisBuilder
      # Damaskini witness dates and places (P23-1): every one of the 23 TSV
      # headers carries a date (point year, decade, decade range, century,
      # or "19th (post 1817)" — all censused at fixture time) and most a
      # place, honest question marks included ("Pleven?"). These are
      # WITNESS (copying/printing) dates — the right axis for a corpus of
      # 15th–19th-c. copies of older works. The coptic-scriptorium shape:
      # a header read from canonical, joined to the catalog by urn.
      #
      # The urn mint mirrors Adapters::Damaskini#discover (FROZEN): TSV
      # filename = newdoc id verbatim, downcased into the urn; the test
      # pins the two against each other via the shared fixture set. -en
      # siblings never join (their urns carry the -en suffix, no TSV file
      # does). Honest absences: a header with neither a parseable date nor
      # a place gets no row (none upstream today); bounds are envelopes,
      # never midpoints.
      module DamaskiniDates
        SLUG = "damaskini"
        URN_PREFIX = "urn:nabu:damaskini:"

        module_function

        # Walk canonical/damaskini's TSV headers and insert one row per
        # dated-or-placed document we hold. Returns { documents: }.
        def build(catalog:, canonical_dir:)
          dir = File.join(canonical_dir, SLUG)
          return { documents: 0 } unless Dir.exist?(dir)

          ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}%")).select_hash(:urn, :id)
          rows = 0
          Dir.glob(File.join(dir, "tsv", "**", "*.txt")).each do |path|
            document_id = ids[document_urn(path)] or next
            axis = extract(path) or next

            insert(catalog, document_id, axis)
            rows += 1
          end
          { documents: rows }
        end

        def document_urn(path)
          "#{URN_PREFIX}#{File.basename(path, '.txt').downcase}"
        end

        # The axis fields, or nil when the header carries neither a date
        # nor a place. Precision "year" for a point date, else "range"
        # (honest envelope).
        def extract(path)
          header = Adapters::Damaskini::TsvHeader.read(path)
          return nil if header.not_before.nil? && header.not_after.nil? && header.place.nil?

          {
            not_before: header.not_before, not_after: header.not_after,
            precision: precision_of(header), date_raw: header.date_raw,
            place_name: header.place
          }
        end

        def precision_of(header)
          return nil if header.not_before.nil? && header.not_after.nil?

          header.not_before == header.not_after ? "year" : "range"
        end

        def insert(catalog, document_id, axis)
          catalog[:document_axes].insert(
            document_id: document_id,
            not_before: axis[:not_before], not_after: axis[:not_after],
            precision: axis[:precision], date_raw: axis[:date_raw],
            place_name: axis[:place_name], axis_source: SLUG
          )
        end
      end
    end
  end
end
