# frozen_string_literal: true

module Nabu
  module Adapters
    # The openMGH Diplomata charter-date reader: the edition's own
    # German dating line for each charter (sourceDesc/bibl/date —
    # "(498) Dezember 29, Reims", "Aachen 833 Dezember 9.", "[481 – 511
    # November 27], Ferrières", "Palermo, 1196 Januar") → year bounds and
    # the issuing place, as STRUCTURED claims beside the verbatim string.
    #
    # == The census (every dated charter on disk, 2026-10-19)
    #
    # 2,037 charter passages carry a dating line across 10 Diplomata
    # volumes (the three DD F. II. volumes ship a bare <date/> on all
    # their 760 charters — nothing to read). Three volume dialects:
    #
    #   date-first   "(1158) Juli 8, bei Verona am Gardasee."  (DD Merov.,
    #                DD F I., DD H VI., DD W.) — the place follows the
    #                LAST date-bearing comma segment
    #   place-first  "Aachen 833 Dezember 9."  (DD Lo I./Lo II., DD Arn,
    #                DD Rudolf.) — the place is the text before the year
    #   place-comma  "Palermo, 1196 Januar"  (DD Ko. II.)
    #
    # with the edition's conventions inside: a bracketed/parenthesized/
    # angled year ("(628)", "[630, vor April 8]", "<645>") is the editor's
    # INFERRED year — still the edition's dating claim, read as such;
    # a wholly parenthesized line ("(1246 August 13, Frankfurt).") infers
    # both; "--"/"–"/"—" is the edition's unknown-place filler.
    #
    # == The conservative reading (bounds never invented)
    #
    # Years are the 3–4 digit tokens inside the plausibility band (the
    # Diplomata span Clovis to Wilhelm of Holland, 481–1256 — the band
    # 400..1400 brackets it); "692/93" and "703/4" are both-year split
    # dates. The bounds are the ENVELOPE of every year the line names
    # (the HGV alternatives policy: "1163 Februar oder 1165 Mai–Juni" →
    # 1163..1165), minus an edition-flagged error ("1186 (irrig 1185)").
    # A lone year after "vor"/"nach" is an open bound ("vor 1162 August
    # 1" → ..1162, "nach 1165 Mai 23" → 1165..). Every HEDGE — "?",
    # "um", "etwa", "ca.", "wohl", "vermutlich", "wahrscheinlich",
    # "danach" — keeps the line verbatim-only (no bounds, no place),
    # like an implausible or garbled year ("Messina, 119 (8 Januar)",
    # "Aix(-les-Bains) 985186."). Census outcome 2026-10-19: 1,915
    # bounded, 110 hedged, 12 unreadable — verbatim-only, counted by the
    # timeline lane.
    #
    # The place is the edition's issuing-place text verbatim ("Kaiserswerth,
    # im Lager", "im Gebiet von Vercelli", "S. Salvatore bei Pavia") —
    # resolution against a gazetteer is the places lane's job, never this
    # reader's. A line naming TWO places (the Handlung/Beurkundung split,
    # "Gray – 1178 September 13, Besançon.") claims none.
    module OpenmghCharterDate
      Result = Data.define(:not_before, :not_after, :place)

      PLAUSIBLE = (400..1400)
      MONTHS = %w[Januar Februar März April Mai Juni Juli August September Oktober November Dezember].freeze
      # Hedges: a bound under any of them would be invented.
      HEDGE = /\?|\b(?:um|etwa|wohl|vermutlich|wahrscheinlich|danach)\b|\bca\./i
      YEAR = %r{(?<![\d/])(\d{3,4})(?:/(\d{1,2}))?(?!\d)}
      GARBLED = /\d{5,}/
      # The edition's own error flag: "(irrig 1185)" names the WRONG year.
      ERRATUM = /\(\s*irrig\b[^)]*\)/
      OPEN_BEFORE = /\bvor\s+\z/
      OPEN_AFTER = /\bnach\s+\z/
      # Words that make a segment date-bearing (the place follows the last one).
      DATE_WORDS = /\d|\b(?:#{MONTHS.join('|')}|Ende|Anfang|Mitte|Sommer|Herbst|Winter|Frühjahr|
                    vor|nach|zwischen|bis|spätestens|frühestens|richtiger|oder)\b/x
      PLACEHOLDER = /\A[\s\-–—.,]*\z/

      module_function

      # Result (any of its fields may be nil) or nil when the line carries
      # no claim this reader can honestly structure.
      def parse(raw)
        text = unwrap(raw.to_s.gsub(/[[:space:]]+/, " ").strip.sub(/\.\z/, "").strip)
        return nil if text.empty? || HEDGE.match?(text) || GARBLED.match?(text)

        bounds = year_bounds(text)
        return nil if bounds.nil?

        Result.new(not_before: bounds[0], not_after: bounds[1], place: place_of(text))
      end

      # A wholly wrapped line — "(1246 August 13, Frankfurt)" — is the
      # editor's inference of the whole claim; its content reads the same.
      def unwrap(text)
        text = text[1..-2].strip while text.start_with?("(") && text.end_with?(")") && closes_at_end?(text)
        text
      end

      def closes_at_end?(text)
        depth = 0
        text.each_char.with_index do |char, index|
          depth += 1 if char == "("
          depth -= 1 if char == ")"
          return index == text.size - 1 if depth.zero?
        end
        false
      end

      # [not_before, not_after] — either may be nil for an open bound —
      # or nil when no plausible year is named.
      def year_bounds(text)
        scan = text.gsub(ERRATUM, "")
        years = []
        opens = []
        scan.to_enum(:scan, YEAR).each do
          match = Regexp.last_match
          years.concat(split_years(match[1], match[2]))
          prefix = scan[0, match.begin(0)]
          opens << (OPEN_BEFORE.match?(prefix) ? :before : (:after if OPEN_AFTER.match?(prefix)))
        end
        return nil if years.empty? || !years.all? { |year| PLAUSIBLE.cover?(year) }

        if years.size == 1 && opens.first
          return opens.first == :before ? [nil, years.first] : [years.first, nil]
        end

        years.minmax
      end

      # "692/93" → [692, 693]; "703/4" → [703, 704]; "1158" → [1158].
      def split_years(year, tail)
        first = Integer(year, 10)
        return [first] if tail.nil?

        [first, Integer(year[0, year.size - tail.size] + tail, 10)]
      end

      def place_of(text)
        leading = leading_place(text)
        trailing = trailing_place(text)
        return nil if leading && trailing # two places: the line claims neither

        leading || trailing
      end

      # Place-first dialects: the text before the first year/bracket token
      # ("Aachen 833 …", "Palermo, 1196 …", "(Messina, 1212 …)" unwrapped);
      # a prefix carrying a date word ("nicht lange vor 1176 …", "Talloires
      # Ende 1030 …") is not a clean place and claims none.
      def leading_place(text)
        return nil unless text.match?(/\A\p{L}/)

        # A parenthesis inside the name stays ("Aix(-les-Bains) 1011 …"); one
        # opening the date ("Foo (1018) März") does not.
        prefix = text[/\A[^\d\[<,]*/].sub(/\(\s*\z/, "").strip
        return nil if DATE_WORDS.match?(prefix)

        clean(prefix)
      end

      # Date-first dialect: the comma segments after the last date-bearing
      # one; a place glued to a closing parenthesis ("1248 (November 10 –
      # Dezember 23) Kaiserswerth, im Lager") joins them.
      def trailing_place(text)
        segments = text.split(/,\s*/)
        index = segments.rindex { |segment| DATE_WORDS.match?(segment) } or return nil
        tail = segments[(index + 1)..]
        glued = segments[index][/\)\s*([^()\d]+)\z/, 1]
        tail = [glued, *tail] if glued && !DATE_WORDS.match?(glued)
        clean(tail.join(", "))
      end

      # Verbatim minus the line's furniture: a trailing period, the
      # unknown-place dashes, an inferred place's own parentheses, and a
      # bracket left unbalanced by the comma split.
      def clean(place)
        place = place.to_s.strip.sub(/\.\z/, "").sub(/[\s\-–—]+\z/, "").strip
        place = place[1..-2].strip if place.start_with?("(") && place.end_with?(")") && closes_at_end?(place)
        place = place.sub(/\A\((\p{L}[^()]*)\)/, '\1')
        place = place.delete("()") if place.count("(") != place.count(")")
        place = place.delete("[]") if place.count("[") != place.count("]")
        place = place.strip.sub(/\.\z/, "").strip
        return nil if place.empty? || PLACEHOLDER.match?(place) || place.match?(/\d/)

        place
      end
    end
  end
end
