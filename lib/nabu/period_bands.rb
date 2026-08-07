# frozen_string_literal: true

require "yaml"
require_relative "lect_rules"

module Nabu
  # The ruled period→band table (P62-0, core layers wave 2):
  # config/period_bands.yml rows mapping NORMALIZED Assyriological period
  # labels to [not_before, not_after] year bands, each row citing its
  # convention (CDLI's own parenthetical gloss where the field states one).
  # Lookup normalizes with the SAME fold the lect period rules use
  # (LectRules.normalize_value — parenthetical glosses and the trailing
  # cataloguer's "?" strip), so "Ur III (ca. 2100-2000 BC)", "Ur III ?" and
  # bare "Ur III" share one ruled row. A label without a row returns nil —
  # Uncertain/Unknown/Standard-Babylonian-as-period stay honestly unbanded
  # (the table's own header records why).
  class PeriodBands
    def self.load(path)
      return nil unless File.file?(path)

      raw = YAML.safe_load_file(path) || {}
      rows = (raw["periods"] || {}).to_h do |label, entry|
        [LectRules.normalize_value(label), entry.fetch("band")]
      end
      new(rows: rows)
    end

    # The config-repo table, memoized per process (ruled config data, not
    # catalog state — the lect-rules precedent).
    def self.default
      return @default if defined?(@default)

      @default = load(File.join(Nabu::Config::PROJECT_ROOT, "config", "period_bands.yml"))
    end

    def initialize(rows:)
      @rows = rows
    end

    def size
      @rows.size
    end

    # [not_before, not_after] for +raw+ (normalized first), or nil.
    def lookup(raw)
      return nil if raw.nil?

      @rows[LectRules.normalize_value(raw)]
    end
  end
end
