# frozen_string_literal: true

require "csv"

require_relative "../../normalize"

module Nabu
  module Store
    module TimelineBuilder
      # CDLI catalog dates + proveniences → the timeline (P31-2).
      #
      # THE HONESTY RULE: year envelopes come ONLY from the catalog's own
      # period strings — CDLI writes its conventional years INTO the value
      # ("Ur III (ca. 2100-2000 BC)", "Achaemenid (547-331 BC)"), so no
      # hand-built chronology table exists here (contrast OraccDates,
      # whose catalogues carry bare period names). Census over the full
      # snapshot (2026-07-19): 353,283 rows — 329,948 parse from the
      # parenthetical, 22,110 have no period, ~1,225 stay honestly
      # undated ("uncertain", "fake (modern)", bare "Old Babylonian" ×6,
      # "Achaemenid?" ×4) less the variant shapes handled below:
      # en-dash ranges (×50), "N BC-N AD" cross-era (Parthian, ×21),
      # ascending "N-N AD" (Sassanian, ×61), single "(ca. 2200 BC)"
      # (Linear Elamite, ×41), "c." for "ca." (×1), and one paren-less
      # "1200-700 BC". A "?"-suffixed period stays parseable — the doubt
      # rides date_raw verbatim.
      #
      # dates_referenced regnal values ("Šulgi.32.09.03") resolve to NO
      # years — that would take an invented reign table; they stay
      # document metadata + the ruler facet.
      #
      # Place: provenience verbatim (NFC), except the no-place shapes
      # ("uncertain (mod. uncertain)", "unknown", …). No gazetteer here —
      # the catalog carries none in this column.
      module CdliDates
        CDLI_SLUG = "cdli"
        URN_PREFIX = "urn:nabu:cdli:"
        CATALOG_RELPATH = File.join("cdli", "cdli_cat.csv")

        # BCE range "2100-2000 BC" (hyphen or en dash, optional ca./c.).
        BC_RANGE = /(?:c(?:a)?\.\s*)?(\d{1,5})\s*[-–]\s*(?:ca\.\s*)?(\d{1,5})\s*BC\b/
        # Cross-era "247 BC-224 AD" — checked before BC_RANGE would misread.
        CROSS_ERA = /(\d{1,5})\s*BC\s*[-–]\s*(?:ca\.\s*)?(\d{1,5})\s*AD\b/
        # CE range "224-641 AD" (ascending).
        AD_RANGE = /(?:ca\.\s*)?(\d{1,5})\s*[-–]\s*(?:ca\.\s*)?(\d{1,5})\s*AD\b/
        # A single "ca. 2200 BC" point.
        BC_POINT = /(?:c(?:a)?\.\s*)?(\d{1,5})\s*BC\b/

        # Proveniences that are explicit don't-knows, not places.
        NO_PLACE = /\A(?:uncertain|unknown|unclear)\b/i

        module_function

        # Stream the canonical catalog CSV, join id_text → urn → document,
        # insert one document-grain row per dated OR placed artifact.
        # Returns { documents:, undated:, invalid: } — +undated+ counts
        # joined documents without a resolvable date (place-only rows
        # still insert), +invalid+ the malformed-range tripwire (ascending
        # BC, zero years).
        def build(catalog:, canonical_dir:)
          counts = { documents: 0, undated: 0, invalid: 0 }
          path = File.join(canonical_dir, CATALOG_RELPATH)
          return counts unless File.file?(path) && !LfsFetch.pointer?(path)

          urn_ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}p%"))
                                       .select_hash(:urn, :id)
          each_catalog_row(path) do |row|
            document_id = urn_ids[Nabu::Adapters::Cdli.urn_for(row["id_text"].to_s.strip)]
            next if document_id.nil?

            insert_row(catalog, document_id, row, counts)
          end
          counts
        end

        def each_catalog_row(path, &)
          CSV.foreach(path, headers: true, encoding: Encoding::UTF_8, &)
        rescue CSV::MalformedCSVError
          nil # a torn catalog costs the timeline, never the rebuild
        end

        def insert_row(catalog, document_id, row, counts)
          date = extract_period(row["period"].to_s.strip, counts)
          counts[:undated] += 1 if date.nil?
          place = extract_place(row["provenience"].to_s)
          return if date.nil? && place.nil?

          counts[:documents] += 1
          timeline = date || { not_before: nil, not_after: nil, precision: nil, date_raw: nil }
          TimelineBuilder.insert_timeline(
            catalog, document_id, timeline.merge(place_name: place, place_ref: nil), CDLI_SLUG
          )
        end

        # The period string's own year envelope (module note), or nil.
        # Every parsed date keeps precision "period" — the periodisation is
        # convention — with the full verbatim value (incl. "?") as raw.
        def extract_period(period, counts)
          return nil if period.empty?

          bounds = period_bounds(period, counts)
          return nil if bounds.nil?

          { not_before: bounds[0], not_after: bounds[1], precision: "period", date_raw: period }
        end

        def period_bounds(period, counts)
          if (m = CROSS_ERA.match(period))
            checked(-m[1].to_i, m[2].to_i, counts)
          elsif (m = AD_RANGE.match(period)) && !period.match?(/BC/)
            checked(m[1].to_i, m[2].to_i, counts)
          elsif (m = BC_RANGE.match(period))
            checked(-m[1].to_i, -m[2].to_i, counts)
          elsif (m = BC_POINT.match(period))
            checked(-m[1].to_i, -m[1].to_i, counts)
          end
        end

        # Bounds must be chronological and year-0-free (the Timeline
        # invariant) — anything else is counted invalid, never stored.
        def checked(not_before, not_after, counts)
          if not_before.zero? || not_after.zero? || not_before > not_after
            counts[:invalid] += 1
            return nil
          end

          [not_before, not_after]
        end

        def extract_place(provenience)
          name = TimelineBuilder.normalize(provenience)
          return nil if name.nil? || name.match?(NO_PLACE)

          name
        end
      end
    end
  end
end
