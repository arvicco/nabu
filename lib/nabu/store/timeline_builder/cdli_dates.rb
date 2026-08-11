# frozen_string_literal: true

require "csv"

require_relative "../../normalize"
require_relative "../../regnal_years"

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
      # dates_referenced regnal values ("Šulgi.32.09.03") resolve through
      # the RULED reign table (config/regnal_years.yml — №R-28, 2026-08-11,
      # the P73-6 scout ratified; NOT invented: middle chronology / Parker
      # & Dubberstein, stated per entry). FINER WINS: a ruled ruler's
      # numbered year replaces the period band with its one conventional
      # year (precision "regnal-year"; YY=00 gives the whole-reign span,
      # "regnal-reign"; "(us2 year)" shifts +1); unruled rulers (ED III,
      # OAkk, floating dynasts — the table header names them) and
      # out-of-range years fall back to the period band, censused.
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

        # A regnal dating's leading "Ruler.YY." — the ruler segment must
        # carry a letter (placeholder shapes like "00." and "--." never
        # reach the table).
        REGNAL = /\A([^.]*\p{L}[^.]*)\.(\d{1,2})\./
        US2_SUFFIX = /\(us2 year\)/

        module_function

        # Stream the canonical catalog CSV, join id_text → urn → document,
        # insert one document-grain row per dated OR placed artifact.
        # Returns { documents:, undated:, invalid: } — +undated+ counts
        # joined documents without a resolvable date (place-only rows
        # still insert), +invalid+ the malformed-range tripwire (ascending
        # BC, zero years).
        def build(catalog:, canonical_dir:)
          counts = { documents: 0, undated: 0, invalid: 0,
                     regnal: 0, regnal_unruled: 0, regnal_out_of_range: 0 }
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
          date = extract_regnal(row["dates_referenced"].to_s.strip, counts) ||
                 extract_period(row["period"].to_s.strip, counts)
          counts[:undated] += 1 if date.nil?
          place = extract_place(row["provenience"].to_s)
          return if date.nil? && place.nil?

          counts[:documents] += 1
          timeline = date || { not_before: nil, not_after: nil, precision: nil, date_raw: nil }
          TimelineBuilder.insert_timeline(
            catalog, document_id, timeline.merge(place_name: place, place_ref: nil), CDLI_SLUG
          )
        end

        # The RULED regnal conversion (№R-28), or nil for anything the
        # table does not answer — the period band is always the fallback.
        def extract_regnal(value, counts)
          return nil if value.empty?
          return nil if (m = REGNAL.match(value)).nil?
          return nil if (table = Nabu::RegnalYears.default).nil?

          year_number = m[2].to_i
          span = table.span(m[1], year_number, us2: value.match?(US2_SUFFIX))
          case span
          when :unruled then counts[:regnal_unruled] += 1
          when :out_of_range then counts[:regnal_out_of_range] += 1
          else
            counts[:regnal] += 1
            return { not_before: span[0], not_after: span[1],
                     precision: year_number.zero? ? "regnal-reign" : "regnal-year",
                     date_raw: value }
          end
          nil
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
