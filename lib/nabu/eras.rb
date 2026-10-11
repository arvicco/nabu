# frozen_string_literal: true

require "yaml"

module Nabu
  # The shared Indian-calendar era table (P118-5): config/eras.yml rows
  # (Śaka, Vikrama, Kollam, Gupta–Valabhī — Sewell & Dikshit 1896) turning
  # an ERA-TYPED year into a CE envelope. The two-value eras carry an
  # explicit uncertainty width (an era year straddles two Julian years);
  # the conversion is always the envelope [Y+offset, Y+offset+width],
  # never a picked epoch — the titus-bactrian ERA_OFFSETS ruling,
  # generalized. Untyped years are never this table's business.
  class Eras
    Row = Data.define(:offset, :width, :label, :aliases, :source)

    # One conversion: the era key, the era year, and the signed CE bounds
    # (catalog convention — negative = BCE, no year zero).
    Conversion = Data.define(:era, :year, :not_before, :not_after) do
      def width = not_after - not_before

      # The MetadataDates :structured bound pair.
      def to_date_bounds = { "not_before" => not_before, "not_after" => not_after }
    end

    def self.load(path)
      return nil unless File.file?(path)

      raw = YAML.safe_load_file(path) || {}
      rows = (raw["eras"] || {}).to_h do |key, entry|
        width = Integer(entry.fetch("width", 0))
        raise ArgumentError, "eras.yml #{key}: width must be >= 0 (got #{width})" if width.negative?

        [key, Row.new(offset: Integer(entry.fetch("offset")), width: width,
                      label: entry["label"] || key, aliases: Array(entry["aliases"]),
                      source: entry.fetch("source"))]
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

    private

    # Astronomical → the catalog's signed year (no year zero: 0 → -1).
    def signed(astronomical)
      astronomical.positive? ? astronomical : astronomical - 1
    end
  end
end
