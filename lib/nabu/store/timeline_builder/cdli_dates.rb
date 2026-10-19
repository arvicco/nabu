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
      # the RULED reign table (config/regnal_years.yml — owner-ruled 2026-08-11,
      # the P73-6 scout ratified; NOT invented: middle chronology / Parker
      # & Dubberstein, stated per entry). FINER WINS: a ruled ruler's
      # numbered year replaces the period band with its one conventional
      # year (precision "regnal-year"; YY=00 gives the whole-reign span,
      # "regnal-reign"; the "(us2 year)" / "(us2-us2 year)" marks read as
      # written — #regnal_span); unruled rulers (ED III,
      # OAkk, floating dynasts — the table header names them) and
      # out-of-range years fall back to the period band, censused.
      # Above both sits the accounting_period span (#extract_accounting):
      # where an account's regnal span resolves at both ends it is the
      # document's envelope, precision "accounting-period". Below the
      # explicit datings and above the period band sits date_of_origin
      # (#extract_origin), the tablet's own date, read through the same
      # table. Precedence: accounting_period > dates_referenced (first
      # entry) > date_of_origin > period band.
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
        # reach the table). The year is a number (a "?" on it is doubt,
        # riding date_raw) or a BROKEN year: CDLI's date scheme gives
        # "components which are broken ... with double hyphen ('--')"
        # (S. Tinney, "Date Specifications for CDLI/Oracc", Oracc 2019);
        # the catalog also writes "xx". A broken year under a ruled ruler is
        # still that reign — the YY=00 whole-reign span.
        REGNAL = /\A([^.]*\p{L}[^.]*)\.(\d{1,2}|--|xx)\??\./
        BROKEN_YEAR = /\A(?:--|xx)\z/
        # The Achaemenid-lane "Ruler.DD/MONTH/YY" shape (day / roman month /
        # regnal year: "Darius1.18/XI/6", "Artaxerxes1.17/VII/41" — the
        # 41-year reign fixes the order). Only a numeric year converts; the
        # accession year ("Darius2.29/X/acc") and doubted/compound forms
        # ("Darius1.24/27(?)") stay unresolved.
        SLASH_REGNAL = %r{\A([^./]*\p{L}[^./]*)\.\d{1,2}/[IVX]+/(\d{1,2})(?=\s|\?|\z)}

        module_function

        # Stream the canonical catalog CSV, join id_text → urn → document,
        # insert one document-grain row per dated OR placed artifact.
        # Returns { documents:, undated:, invalid: } — +undated+ counts
        # joined documents without a resolvable date (place-only rows
        # still insert), +invalid+ the malformed-range tripwire (ascending
        # BC, zero years).
        def build(catalog:, canonical_dir:)
          counts = { documents: 0, undated: 0, invalid: 0,
                     regnal: 0, regnal_unruled: 0, regnal_out_of_range: 0,
                     regnal_broken_year: 0, regnal_slash: 0,
                     accounting: 0, accounting_unresolved: 0, origin: 0, origin_unresolved: 0 }
          path = File.join(canonical_dir, CATALOG_RELPATH)
          return counts unless File.file?(path) && !LfsFetch.pointer?(path)

          urn_ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}p%"))
                                       .select_hash(:urn, :id)
          TimelineBuilder.writing_axes(catalog) do |axes|
            each_catalog_row(path) do |row|
              document_id = urn_ids[Nabu::Adapters::Cdli.urn_for(row["id_text"].to_s.strip)]
              next if document_id.nil?

              insert_row(axes, document_id, row, counts)
            end
          end
          counts
        end

        def each_catalog_row(path, &)
          CSV.foreach(path, headers: true, encoding: Encoding::UTF_8, &)
        rescue CSV::MalformedCSVError
          nil # a torn catalog costs the timeline, never the rebuild
        end

        def insert_row(axes, document_id, row, counts)
          dates_referenced = row["dates_referenced"].to_s.strip
          date = extract_accounting(row["accounting_period"].to_s.strip, counts) ||
                 extract_regnal(dates_referenced, counts) ||
                 extract_origin(row["date_of_origin"].to_s.strip, dates_referenced, counts) ||
                 extract_period(row["period"].to_s.strip, counts)
          counts[:undated] += 1 if date.nil?
          place = extract_place(row["provenience"].to_s)
          return if date.nil? && place.nil?

          counts[:documents] += 1
          timeline = date || { not_before: nil, not_after: nil, precision: nil, date_raw: nil }
          TimelineBuilder.insert_timeline(
            axes, document_id, timeline.merge(place_name: place, place_ref: nil), CDLI_SLUG
          )
        end

        # The RULED regnal conversion (owner ruling 2026-08-11), or nil for anything the
        # table does not answer — the period band is always the fallback.
        # dates_referenced is a LIST ("Šulgi.39.00.00, Šulgi.40.00.00 (us2
        # year)"); only its FIRST entry is read.
        def extract_regnal(value, counts)
          return nil if value.empty?

          first = value.split(",").first.to_s.strip
          return nil if (parsed = parse_regnal(first)).nil?

          span = regnal_span(first)
          case span
          when :unruled then counts[:regnal_unruled] += 1
          when :out_of_range then counts[:regnal_out_of_range] += 1
          when Array
            counts[:regnal] += 1
            counts[:regnal_broken_year] += 1 if parsed[:shape] == :broken
            counts[:regnal_slash] += 1 if parsed[:shape] == :slash
            return { not_before: span[0], not_after: span[1],
                     precision: parsed[:year].zero? ? "regnal-reign" : "regnal-year",
                     date_raw: value }
          end
          nil
        end

        # date_of_origin (catalog census 2026-10-19: 147,383 rows) is the
        # tablet's own date. On 142,921 rows it restates dates_referenced
        # verbatim; on the other 4,462 — every one an account carrying an
        # accounting_period — it is the LAST entry of the dates_referenced
        # list (the date the account closed). Its shapes are therefore the
        # dates_referenced shapes (regnal strings, "00.00.00.00" /
        # "--.--.--.--" filler, Mari/Isin letter-years, Seleucid
        # "HE.SE.080.09.07", Old Assyrian eponyms "085: Szarru-ken1.…"), read
        # through the same ruled table. It ranks BELOW the explicit datings
        # (accounting_period, the first dates_referenced entry) and above
        # the period band; a value that merely restates dates_referenced is
        # never re-read (it would only double the regnal census). Hits count
        # +origin+, distinct values that resolve nothing +origin_unresolved+.
        def extract_origin(value, dates_referenced, counts)
          return nil if value.empty? || value == dates_referenced

          date = extract_regnal(value, Hash.new(0))
          counts[date ? :origin : :origin_unresolved] += 1
          date
        end

        # The accounting_period column (catalog census 2026-10-19: 4,468
        # rows, 3,457 values — "Amar-Suen.07.00.00 to Amar-Suen.08.00.00",
        # "Šulgi.48.00.00 to Amar-Suen.01.00.00", "--.--.01.00 to
        # --.--.12.00"): the span an account covers. Both ends must resolve
        # through the ruled table; the envelope is min..max of the two end
        # spans (month/day refine the raw, never the bounds; a trailing
        # "?" or "(Reichskalender)" rides raw). Its own labeled precision,
        # "accounting-period" — and it outranks dates_referenced, whose
        # first entry is only one date inside the span. Anything else
        # (unruled rulers such as Lugalanda, ruler-less filler, eponym
        # prose, out-of-range years) is counted
        # unresolved and the column stays metadata.
        ACCOUNTING_SPLIT = /\s+to\s+/

        def extract_accounting(value, counts)
          return nil if value.empty?

          sides = value.split(ACCOUNTING_SPLIT)
          spans = sides.size == 2 ? sides.map { |side| regnal_span(side.strip) } : []
          unless spans.size == 2 && spans.all?(Array)
            counts[:accounting_unresolved] += 1
            return nil
          end

          counts[:accounting] += 1
          { not_before: spans.map(&:first).min, not_after: spans.map(&:last).max,
            precision: "accounting-period", date_raw: value }
        end

        # One "Ruler.YY.MM.DD" (or slash-shaped) dating → the ruled table's
        # span, or a reason symbol (:unparsed, :unruled, :out_of_range).
        #
        # THE us2 MARKS READ AS WRITTEN (owner-ruled 2026-10-20): the year
        # number IS the year, for "(us2 year)" and "(us2-us2 year)" alike.
        # The marks record which year-NAME formula the scribe used (mu
        # us2-sa "year after the year: …", mu us2-sa … mu us2-sa-a-bi
        # "second year after the year: …"), not an offset from the number.
        # CDLI's own year-name tables (cdli.ox.ac.uk/wiki, year_names_shulgi
        # / year_names_shu-suen / year_names_ibbi-suen, read 2026-10-19)
        # list those formulae UNDER their canonical year numbers: the
        # single-mark names (Šulgi 47 = "mu us2-sa ki-maš ba-hul") and the
        # double-mark names (Šulgi 41 and 48, Šū-Suen 6, Ibbi-Suen 8) alike —
        # and the catalog's marks concentrate on exactly those numbers
        # (first entries, census 2026-10-20: "(us2 year)" Šulgi.47 ×1,750;
        # "(us2-us2 year)" Šulgi.48 ×486, Šulgi.41 ×409, Šū-Suen.06 ×294,
        # Ibbi-Suen.08 ×75). The mark annotates an already-numbered year.
        def regnal_span(dating)
          return :unparsed if (parsed = parse_regnal(dating)).nil?
          return :unparsed if (table = Nabu::RegnalYears.default).nil?

          table.span(parsed[:ruler], parsed[:year])
        end

        # The ruler + numeric year (0 = unknown or broken — the whole reign)
        # and the shape that carried them, or nil.
        def parse_regnal(dating)
          if (m = REGNAL.match(dating))
            broken = m[2].match?(BROKEN_YEAR)
            { ruler: m[1], year: broken ? 0 : m[2].to_i, shape: broken ? :broken : :plain }
          elsif (m = SLASH_REGNAL.match(dating))
            { ruler: m[1], year: m[2].to_i, shape: :slash }
          end
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
