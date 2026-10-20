# frozen_string_literal: true

require "yaml"

module Nabu
  # The shared era table (P118-5; the Japanese nengō rows owner-ruled
  # 2026-10-20): config/eras.yml rows turning an ERA-TYPED year into a CE
  # envelope.
  #
  # The Indian-calendar rows (Śaka, Vikrama, Kollam, Gupta–Valabhī —
  # Sewell & Dikshit 1896) carry an explicit uncertainty width (an era
  # year straddles two Julian years); the conversion is always the
  # envelope [Y+offset, Y+offset+width], never a picked epoch — the
  # titus-bactrian ERA_OFFSETS ruling, generalized.
  #
  # The nengō rows (family "nengo": the standard era list, 大化 645 →
  # 令和 2019) are the same shape — offset = start − 1, width 0 — plus
  # +max_year+ (the era's last numbered year) and a +parse+ flag: Chinese
  # print-era homonyms and the one-year eras are held in the table but
  # never read out of prose (#nengo_years). Untyped years are never this
  # table's business.
  class Eras
    Row = Data.define(:offset, :width, :label, :aliases, :source, :family, :max_year, :parse)

    # One conversion: the era key, the era year, and the signed CE bounds
    # (catalog convention — negative = BCE, no year zero).
    Conversion = Data.define(:era, :year, :not_before, :not_after) do
      def width = not_after - not_before

      # The MetadataDates :structured bound pair.
      def to_date_bounds = { "not_before" => not_before, "not_after" => not_after }
    end

    # One era-year phrase read out of prose: the matched text verbatim
    # ("寛政4", "天保十一年", "同二年") and its conversion.
    NengoHit = Data.define(:text, :conversion)

    def self.load(path)
      return nil unless File.file?(path)

      raw = YAML.safe_load_file(path) || {}
      rows = (raw["eras"] || {}).to_h do |key, entry|
        width = Integer(entry.fetch("width", 0))
        raise ArgumentError, "eras.yml #{key}: width must be >= 0 (got #{width})" if width.negative?

        [key, Row.new(offset: Integer(entry.fetch("offset")), width: width,
                      label: entry["label"] || key, aliases: Array(entry["aliases"]),
                      source: entry.fetch("source"), family: entry["family"],
                      max_year: entry["max_year"] && Integer(entry["max_year"]),
                      parse: entry.fetch("parse", true) != false)]
      end
      new(rows: rows)
    end

    # The config-repo table, memoized per process (ruled config data — the
    # RegnalYears / PeriodBands precedent).
    def self.default
      return @default if defined?(@default)

      @default = load(File.join(Nabu::Config::PROJECT_ROOT, "config", "eras.yml"))
    end

    def self.reset!
      remove_instance_variable(:@default) if defined?(@default)
    end

    # The alias fold: NFC, downcase, dots and whitespace dropped
    # ("G.E." == "GE" == "ge").
    def self.fold(name)
      name.to_s.unicode_normalize(:nfc).downcase.gsub(/[.\s]/, "")
    end

    def initialize(rows:)
      @rows = rows
      @aliases = rows.each_with_object({}) do |(key, row), index|
        ([key] + row.aliases).each { |name| index[self.class.fold(name)] = key }
      end
    end

    def keys = @rows.keys

    def size = @rows.size

    def source(key) = @rows.fetch(key).source

    def label(key) = @rows.fetch(key).label

    def family(key) = @rows.fetch(key).family

    # The era key an upstream spelling types, or nil (unruled — never a
    # guess).
    def resolve(name)
      @aliases[self.class.fold(name)]
    end

    # Era year +year+ of era +key+ → Conversion. Raises KeyError for an
    # unknown key (resolve first when the spelling is upstream's).
    def to_ce(key, year)
      row = @rows.fetch(key)
      low = year + row.offset
      Conversion.new(era: key, year: year, not_before: signed(low), not_after: signed(low + row.width))
    end

    # -- nengō prose ---------------------------------------------------------

    # Old-form kanji the bibliographies write era names in (寶永, 承應,
    # 萬延 …) → the list's forms. Matching only — the raw stays verbatim.
    NENGO_FOLD = { "寶" => "宝", "寳" => "宝", "應" => "応", "萬" => "万", "曆" => "暦", "龜" => "亀",
                   "德" => "徳", "祿" => "禄", "壽" => "寿", "齊" => "斉", "靈" => "霊", "觀" => "観",
                   "寬" => "寛" }.freeze
    NENGO_FOLD_RE = Regexp.union(NENGO_FOLD.keys)
    KANJI_DIGITS = { "一" => 1, "二" => 2, "三" => 3, "四" => 4, "五" => 5, "六" => 6, "七" => 7,
                     "八" => 8, "九" => 9 }.freeze
    # A year number: 1–2 ASCII/full-width digits (the bibliographic
    # "寛政4刊"), kanji numerals before 年 (天保十一年, 明治廿四年, 享保拾五年),
    # or 元 (year 1) before 年 or a bibliographic mark (寛政元序).
    YEAR_NUMBER = /
      (?<digits>[0-9０-９]{1,2})(?![0-9０-９])
      | (?<kanji>[一二三四五六七八九十廿卅拾]{1,4})(?=年)
      | (?<gannen>元)(?=年|[刊序跋写成印識\s,，、・\-–~〜?？\])）]|\z)
    /x
    # Chinese era names ending in a ruled Japanese name: "太平興国5" is
    # the Song era, never 興国 (1340).
    LONGER_CHINESE_ERAS = { "興国" => "太平" }.freeze

    # Every era-year phrase in +text+ the nengō rows read: ruled
    # (parse-enabled) era + year number within the era's span, and a
    # following "同N年" (the same era) or bare range end ("元文3-5")
    # continuing the last named one.
    # Homonym / one-year rows, out-of-range years and pre-Taika names
    # (no row) read nothing.
    def nengo_years(text)
      folded = text.to_s.gsub(NENGO_FOLD_RE, NENGO_FOLD)
      hits = []
      last_era = nil
      folded.scan(nengo_pattern) do
        match = Regexp.last_match
        era = match[:era] ? @aliases[self.class.fold(match[:era])] : last_era
        next if era.nil?
        next if match[:era] && inside_longer_chinese_era?(folded, match, era)

        last_era = era if match[:era]
        year = year_number(match)
        row = @rows.fetch(era)
        next if year.nil? || year < 1 || (row.max_year && year > row.max_year)

        hits << NengoHit.new(text: text.to_s[match.begin(0)...match.end(0)], conversion: to_ce(era, year))
      end
      hits
    end

    # The MetadataDates :structured "date" hash spanning every era year
    # +text+ states (a range, or preface and print dates, span), or nil.
    def nengo_date(text, basis:)
      hits = nengo_years(text)
      return nil if hits.empty?

      { "not_before" => hits.map { |hit| hit.conversion.not_before }.min,
        "not_after" => hits.map { |hit| hit.conversion.not_after }.max,
        "raw" => text, "eras" => hits.map(&:text), "basis" => basis }
    end

    private

    # Parse-enabled nengō names, longest first (天平勝宝 before 天平), or a
    # "同" continuation, each followed by its year number.
    def nengo_pattern
      @nengo_pattern ||= begin
        names = @rows.select { |_key, row| row.family == "nengo" && row.parse }
                     .flat_map { |key, row| [key] + row.aliases }
                     .sort_by { |name| -name.size }
        /(?:(?<era>#{Regexp.union(names).source})|同|(?<=[0-9０-９][-–〜~]))\s*(?:#{YEAR_NUMBER.source})年?/x
      end
    end

    def inside_longer_chinese_era?(folded, match, era)
      prefix = LONGER_CHINESE_ERAS[era]
      !prefix.nil? && folded[0...match.begin(0)].end_with?(prefix)
    end

    def year_number(match)
      if match[:digits] then Integer(match[:digits].tr("０-９", "0-9"), 10)
      elsif match[:gannen] then 1
      else kanji_number(match[:kanji])
      end
    end

    # 十一 → 11, 二十三 → 23, 廿四 → 24, 拾五 → 15; nil for a shape that is
    # not a positional count (二二).
    def kanji_number(text)
      total = 0
      unit = nil
      text.each_char do |char|
        case char
        when "十", "拾" then total += (unit || 1) * 10
                             unit = nil
        when "廿" then total += 20
        when "卅" then total += 30
        else return nil unless unit.nil?

             unit = KANJI_DIGITS.fetch(char)
        end
      end
      total + (unit || 0)
    end

    # Astronomical → the catalog's signed year (no year zero: 0 → -1).
    def signed(astronomical)
      astronomical.positive? ? astronomical : astronomical - 1
    end
  end
end
