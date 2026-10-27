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
      # - dat_jahr_a / dat_jahr_e → not_before / not_after. A LONE dat_jahr_a
      #   is EDH's point year, not an open range: the record's own EpiDoc
      #   carries <origDate when-custom="…"> for 3,528 of the 3,529 such
      #   rows (the 3,529th has an attribute-less origDate) — censused
      #   2026-10-22, correcting the survey-era open-ended reading. So
      #   not_after = not_before there. precision: "year" for a point,
      #   "range" for a span — width is visible in the honest bounds. date_raw
      #   joins the verbatim column values ("71–130"; a point "217").
      # - dat_monat / dat_tag: upstream's typed month and day (1,093 / 997
      #   rows; 671 a full day on a point year — the GODOT-dated consular and
      #   imperial dates). On a point year they sharpen the same artifact row:
      #   precision "day" (or "month"), date_raw ISO-shaped "217-05-22" /
      #   "-44-03". On a year SPAN (299 rows — a dated day of an undated
      #   year) the range stands and the day rides date_raw only ("171–230
      #   (day 13.7.)"). The GODOT record identity itself rides the links
      #   graph (Nabu::EdhCitations), not a timeline column. A literal year 0 is the Timeline
      #   tripwire: skipped, counted invalid, never stored. The 330 records
      #   dated past 640 CE (post-antique copies/forgeries EDH records as
      #   such, up to 1998) ingest verbatim — the timeline does not editorialize.
      # - place_name = the ancient findspot (fo_antik), modern (fo_modern) as
      #   fallback; place_ref = the Pleiades URL (pl_ancient_loc1) where
      #   present, else the GeoNames URL (geo_id1) — the same gazetteers the
      #   HGV/ORACC refs point at, verbatim strings, no gazetteer resolution
      #   (the §1.4 stance).
      # - place_lat/place_lon = the koordinaten1 WGS84 findspot pair
      #   ("40.8471577,14.0550756" — 79,488 of 82,450 rows at the 2026-09-26
      #   census), both-or-nothing, riding the rundata coordinates lane
      #   (migration 027). P104-1 reverses the survey-v2
      #   canonical-only stance — the aggressive-mining law rules all metadata mined; the
      #   secondary koordinaten2 pair stays canonical-only (a second locus
      #   claim on 838 rows, no axis column pair to honestly carry it).
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
          TimelineBuilder.writing_axes(catalog) do |axes|
            CSV.foreach(path, headers: true) do |row|
              document_id = urn_ids["#{URN_PREFIX}#{row['hd_nr'].to_s.strip.downcase}"] or next

              insert_row(axes, document_id, row, counts)
            end
          end
          counts
        end

        def insert_row(axes, document_id, row, counts)
          timeline = extract(row)
          if timeline == :invalid
            counts[:invalid] += 1
            return
          end
          counts[:undated] += 1 if timeline.nil? || timeline[:not_before].nil?
          return if timeline.nil?

          TimelineBuilder.insert_timeline(axes, document_id, timeline, EDH_SLUG)
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
          # A lone dat_jahr_a is a POINT year (module note) — never open-ended.
          not_after ||= not_before
          place_name, place_ref = extract_place(row)
          lat, lon = coordinates(row)
          return nil if not_before.nil? && not_after.nil? && place_name.nil? && lat.nil?

          {
            not_before: not_before, not_after: not_after,
            precision: precision(row, not_before, not_after),
            date_raw: date_raw(row, not_before, not_after),
            place_name: place_name, place_ref: place_ref,
            place_lat: lat, place_lon: lon
          }
        end

        # The koordinaten1 "lat,lon" pair → floats, both-or-nothing (a lone
        # or malformed coordinate is not a point — never guessed).
        COORDINATE_PAIR = /\A(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\z/
        def coordinates(row)
          match = COORDINATE_PAIR.match(row["koordinaten1"].to_s.strip) or return [nil, nil]

          [Float(match[1]), Float(match[2])]
        end

        # "day"/"month" when upstream types the day/month of a point year,
        # else "year" for a point, "range" for a span.
        def precision(row, not_before, not_after)
          return nil if not_before.nil? && not_after.nil?
          return "range" unless not_before == not_after

          month, day = day_month(row)
          return "day" if month && day

          month ? "month" : "year"
        end

        # For display: a point year verbatim ("217"), with upstream's month
        # and day ISO-shaped behind it ("217-05-22", "-44-03"); a span as
        # the verbatim column values ("71–130"), a typed day kept in words
        # ("171–230 (day 13.7.)"). nil for a place-only row.
        def date_raw(row, not_before, not_after)
          return nil if not_before.nil? && not_after.nil?

          first = row["dat_jahr_a"].to_s.strip
          month, day = day_month(row)
          if not_before == not_after
            [first, month && format("%02d", month), month && day && format("%02d", day)].compact.join("-")
          else
            span = "#{first}–#{row['dat_jahr_e'].to_s.strip}"
            day && month ? "#{span} (day #{day}.#{month}.)" : span
          end
        end

        # [month, day] as integers from dat_monat/dat_tag, each nil when
        # absent or outside the calendar (a day never stands without its
        # month).
        def day_month(row)
          month = calendar_int(row["dat_monat"], 12)
          day = calendar_int(row["dat_tag"], 31)
          [month, month && day]
        end

        def calendar_int(value, max)
          text = value.to_s.strip
          return nil unless text.match?(/\A\d{1,2}\z/)

          number = text.to_i
          number.between?(1, max) ? number : nil
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
