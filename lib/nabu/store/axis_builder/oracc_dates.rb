# frozen_string_literal: true

require "json"

require_relative "../../date_axis"
require_relative "../../normalize"

module Nabu
  module Store
    module AxisBuilder
      # ORACC catalogue dates (P16-3, part 2 of the date/place axis). Every
      # ORACC project ships a catalogue.json whose members carry `period`
      # (33/33 catalogues, 25,330/25,502 members on the 2026-07-13 census) and
      # — in the royal-inscription and SAA projects — `date_of_origin` (7,343
      # members: regnal formulas, absolute BCE ranges, century phrases).
      #
      # == Extraction policy (census-backed, never guessed)
      #
      # 1. `date_of_origin` first, when it parses:
      #    - SAA regnal formula "Sargon2.000.00.00" / eponym variant
      #      "Esarhaddon.limu Nabu-belu-usur.02.16" → the king's reign range
      #      from REIGNS (precision "reign"). The census found NO nonzero
      #      regnal years, so day-level resolution is moot; an unknown king
      #      ("00.000.00.00") falls through to the period.
      #    - absolute BCE range "704-681" / "ca. 1233-1197" / "625–605"
      #      (precision "range"/"ca"), single year "748" (precision "year"),
      #      century phrase "9th-8th century" / "late 16th or early 15th
      #      century" (precision "century"). All BCE — a range must DESCEND
      #      (first bound ≥ second) or it is unparseable.
      # 2. else `period` via PERIODS (precision "period"); a compound
      #    "X or Y" period envelopes its mapped parts.
      # 3. else the document is counted undated — skipped, never guessed
      #    ("Uncertain"/"uncertain"/"Unknown" are deliberately unmapped).
      #
      # Place: `provenience` verbatim (NFC), except the no-place values
      # unclear/uncertain/unknown; `pleiades_id` becomes the place_ref URL
      # (same gazetteer HGV's refs point at). A translation document
      # (…:<textid>-en, P13-4) carries its tablet's axis row: the date/place
      # of the artifact, not of the modern rendering — so the English witness
      # inherits the time filter.
      module OraccDates
        ORACC_SLUG = "oracc"
        URN_PREFIX = "urn:nabu:oracc:"
        PLEIADES = "https://pleiades.stoa.org/places/"

        # Mesopotamian period → signed historical year range, MIDDLE CHRONOLOGY.
        # Names are the ORACC/CDLI periodisation used verbatim in the
        # catalogues (census 2026-07-13: 30 distinct values); absolute bounds
        # follow CDLI's conventional middle-chronology dates (cdli.mpiwg-berlin.
        # mpg.de period list, after J. A. Brinkman's chronology appendix in
        # A. L. Oppenheim, Ancient Mesopotamia, rev. ed. 1977). All bounds are
        # honest "ca." ranges — periodisation is convention, not measurement.
        PERIODS = {
          "Archaic" => [-3350, -3000], # proto-cuneiform Uruk IV–III horizon
          "Uruk IV" => [-3350, -3200],
          "Uruk III" => [-3200, -3000],
          "Early Dynastic" => [-2900, -2340], # ED I-II .. ED IIIb envelope
          "ED I-II" => [-2900, -2700],
          "ED IIIa" => [-2600, -2500],
          "Early Dynastic IIIa" => [-2600, -2500],
          "ED IIIb" => [-2500, -2340],
          "Early Dynastic IIIb" => [-2500, -2340],
          "Ebla" => [-2350, -2250],
          "Old Akkadian" => [-2340, -2200],
          "Lagaš II" => [-2200, -2100],
          "Ur III" => [-2100, -2000],
          "Early Old Babylonian" => [-2000, -1900],
          "Old Assyrian" => [-1950, -1850],
          "Old Babylonian" => [-1900, -1600],
          "Middle Babylonian" => [-1400, -1100],
          "Middle Assyrian" => [-1400, -1000],
          "Neo-Assyrian" => [-911, -612],
          "Neo-Babylonian" => [-626, -539],
          # Fall of Babylon (539) through the latest dated cuneiform text
          # (an astronomical almanac of 75 CE) — honest-wide, the catalogues
          # use "Late Babylonian" for anything post-NB.
          "Late Babylonian" => [-539, 75],
          "Achaemenid" => [-547, -331],
          "Hellenistic" => [-323, -63],
          "Seleucid" => [-312, -63], # Seleucid era epoch 312/311
          "First Millennium" => [-1000, -1] # verbatim honesty: the whole millennium
        }.freeze

        # Neo-Assyrian kings as the SAA/RIAO catalogues spell them → reign
        # (signed historical years, BCE). The standard Neo-Assyrian chronology,
        # eponym-canon anchored (absolute via the Bur-Saggilê solar eclipse,
        # 763 BCE); conventional regnal dates after A. K. Grayson (Assyrian
        # Rulers, RIMA; CAH III/1). Post-631 reigns (Assurbanipal's end,
        # Assur-etel-ilani, Sin-sharru-ishkun) are the conventional
        # approximations — the sources themselves are uncertain there.
        REIGNS = {
          "Shalmaneser3" => [-858, -824],
          "Shamshi-Adad5" => [-823, -811],
          "Adad-narari3" => [-810, -783],
          "Assur-dan3" => [-772, -755],
          "Tiglath-pileser3" => [-744, -727],
          "Shalmaneser5" => [-726, -722],
          "Sargon2" => [-721, -705],
          "Sennacherib" => [-704, -681],
          "Esarhaddon" => [-680, -669],
          "Assurbanipal" => [-668, -631],
          "Assur-etel-ilani" => [-630, -627],
          "Sin-sharru-ishkun" => [-626, -612]
        }.freeze

        # Members whose provenience is an explicit don't-know, not a place.
        NO_PLACE = %w[unclear uncertain unknown].freeze

        # "Sargon2.000.00.00" or "Esarhaddon.limu Nabu-belu-usur.02.16" — the
        # king is everything before the first dot.
        REGNAL = /\A([A-Za-z][A-Za-z'’-]*\d*)\./
        # "704-681", "ca. 1233-1197", "625–605" (hyphen or en dash).
        ABS_RANGE = /\A(ca\.\s*)?(\d{3,4})\s*[-–]\s*(?:ca\.\s*)?(\d{3,4})\z/
        ABS_YEAR = /\A(ca\.\s*)?(\d{3,4})\z/
        # "9th-8th century", "15th century", "late 16th or early 15th century",
        # "10th-7th centuries", "23th or 22nd century" (sic, upstream).
        QUALIFIER = /(?:late|early|mid)\s+/i
        CENTURIES = /\A#{QUALIFIER}?(\d{1,2})(?:st|nd|rd|th)
                     (?:\s*(?:[-–]|or)\s*#{QUALIFIER}?(\d{1,2})(?:st|nd|rd|th))?
                     \s+centur(?:y|ies)\z/x

        module_function

        # Walk every catalogue.json under canonical/oracc, join each member to
        # the catalog documents it produced (base + "-en" translation), insert
        # one document-grain axis row per joined document. Returns
        # { documents:, undated: } — +undated+ counts joined documents whose
        # date did not resolve (they may still carry a place-only row).
        def build(catalog:, canonical_dir:)
          root = File.join(canonical_dir, ORACC_SLUG)
          return { documents: 0, undated: 0 } unless Dir.exist?(root)

          urn_ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}%")).select_hash(:urn, :id)
          documents = 0
          undated = 0
          catalogue_paths(root).each do |path|
            data = JSON.parse(File.read(path))
            project = data["project"].to_s.tr("/", "-")
            next if project.empty?

            data.fetch("members", {}).each do |textid, member|
              ids = document_ids(urn_ids, project, textid)
              next if ids.empty?

              axis = extract(member)
              undated += ids.size if axis.nil? || axis[:not_before].nil?
              next if axis.nil?

              ids.each { |id| AxisBuilder.insert_axis(catalog, id, axis, "oracc") }
              documents += ids.size
            end
          end
          { documents: documents, undated: undated }
        end

        # The two layouts on disk: <project>/catalogue.json and the
        # sub-project nesting <project>/<sub>/catalogue.json (saao-saa01/saa01).
        def catalogue_paths(root)
          Dir.glob([File.join(root, "*", "catalogue.json"), File.join(root, "*", "*", "catalogue.json")])
        end

        # The catalog documents one member produced: the tablet document and —
        # when the project ships translations (P13-4) — its "-en" witness.
        def document_ids(urn_ids, project, textid)
          ["#{URN_PREFIX}#{project}:#{textid}", "#{URN_PREFIX}#{project}:#{textid}-en"]
            .filter_map { |urn| urn_ids[urn] }
        end

        # One member's axis fields, or nil when it yields neither date nor
        # place. Every date has BOTH bounds (period/reign/range tables are
        # closed intervals) — so a nil not_before means "no date resolved".
        def extract(member)
          date = extract_date(member)
          place_name, place_ref = extract_place(member)
          return nil if date.nil? && place_name.nil?

          date ||= { not_before: nil, not_after: nil, precision: nil, date_raw: nil }
          date.merge(place_name: place_name, place_ref: place_ref)
        end

        def extract_date(member)
          raw = member["date_of_origin"].to_s.strip
          parsed = parse_date_of_origin(raw) unless raw.empty?
          return parsed if parsed

          period_range(member["period"].to_s.strip)
        end

        def parse_date_of_origin(raw)
          parse_regnal(raw) || parse_absolute(raw) || parse_centuries(raw)
        end

        def parse_regnal(raw)
          king = REGNAL.match(raw)&.captures&.first
          bounds = REIGNS[king] or return nil

          { not_before: bounds[0], not_after: bounds[1], precision: "reign", date_raw: raw }
        end

        # Absolute BCE years. A range must descend ("704-681"): ascending
        # numbers would mean CE, which no ORACC catalogue uses — unparseable,
        # so it is skipped and counted rather than misread. A 0 year is the
        # year-0 tripwire: unparseable, never stored (DateAxis invariant).
        def parse_absolute(raw)
          if (m = ABS_RANGE.match(raw))
            hi = m[2].to_i
            lo = m[3].to_i
            return nil if hi < lo || lo.zero?

            { not_before: -hi, not_after: -lo, precision: m[1] ? "ca" : "range", date_raw: raw }
          elsif (m = ABS_YEAR.match(raw))
            year = m[2].to_i
            return nil if year.zero?

            { not_before: -year, not_after: -year, precision: m[1] ? "ca" : "year", date_raw: raw }
          end
        end

        # "9th-8th century" → 900–701 BCE: the earlier (larger-numbered)
        # century opens the range, the later one closes it, via the same
        # DateAxis century bounds the --century flag uses (BCE century -N).
        def parse_centuries(raw)
          m = CENTURIES.match(raw) or return nil

          indices = [m[1].to_i, (m[2] || m[1]).to_i]
          return nil if indices.any?(&:zero?)

          not_before = DateAxis.century_bounds(-indices.max).first
          not_after = DateAxis.century_bounds(-indices.min).last
          { not_before: not_before, not_after: not_after, precision: "century", date_raw: raw }
        end

        # PERIODS lookup; a compound "X or Y" envelopes its parts (each part
        # retried with a leading late/early/mid qualifier stripped — "Late
        # Middle Assyrian or early Neo-Assyrian"). Any unmapped part →
        # unmapped whole → nil (skipped, counted; never guessed).
        def period_range(period)
          return nil if period.empty?

          parts = period.split(/\s+or\s+/).map { |part| lookup_period(part.strip) }
          return nil if parts.any?(&:nil?)

          {
            not_before: parts.map(&:first).min, not_after: parts.map(&:last).max,
            precision: "period", date_raw: period
          }
        end

        def lookup_period(name)
          PERIODS[name] || PERIODS[name.sub(QUALIFIER, "")]
        end

        def extract_place(member)
          name = AxisBuilder.normalize(member["provenience"].to_s)
          name = nil if name && NO_PLACE.include?(name.downcase)
          pleiades = member["pleiades_id"].to_s.strip
          ref = name && pleiades.match?(/\A\d+\z/) ? "#{PLEIADES}#{pleiades}" : nil
          [name, ref]
        end
      end
    end
  end
end
