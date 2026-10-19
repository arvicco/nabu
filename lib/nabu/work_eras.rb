# frozen_string_literal: true

require "yaml"
require_relative "period_bands"

module Nabu
  # The ruled per-work attributed-era table (config/work_eras.yml): for a
  # source whose documents carry no date but whose WORK is a known
  # composition, one row per work (keyed on a declared metadata field)
  # naming its attributed composition era — a dynasty label resolved
  # through the period_bands sinological rows (the kanripo/cbeta dynasty-
  # band precedent) or an explicit envelope with its own label. A work
  # declared without an era (a contested attribution) answers nil: the
  # row records the decision, the lookup mints nothing. Every row carries
  # its reasoning (`note`). Data, not code — extending it is a ruled edit
  # in the YAML.
  class WorkEras
    class ConfigError < Nabu::Error; end

    Era = Data.define(:band, :label)

    def self.load(path, period_bands: PeriodBands.default)
      return nil unless File.file?(path)

      new(YAML.safe_load_file(path) || {}, period_bands: period_bands)
    end

    # The config-repo table, memoized per process (ruled config data — the
    # PeriodBands precedent).
    def self.default
      return @default if defined?(@default)

      @default = load(File.join(Nabu::Config::PROJECT_ROOT, "config", "work_eras.yml"))
    end

    def self.reset!
      remove_instance_variable(:@default) if defined?(@default)
    end

    def initialize(doc, period_bands:)
      @sources = (doc["sources"] || {}).to_h do |slug, spec|
        works = (spec["works"] || {}).to_h { |work, row| [work.to_s, parse_row(slug, work, row || {}, period_bands)] }
        [slug.to_s, { key: spec.fetch("key", "book").to_s, works: works }]
      end
    end

    def key_for(slug) = @sources.dig(slug, :key)
    def works(slug) = (@sources.dig(slug, :works) || {}).keys

    def note(slug, work) = @sources.dig(slug, :works, work, :note)

    # The attributed Era for +work+ in +slug+'s table, or nil (unknown
    # source, unknown work, or a work declared without an era).
    def lookup(slug, work)
      @sources.dig(slug, :works, work.to_s, :era)
    end

    private

    def parse_row(slug, work, row, period_bands)
      era = if row["band"]
              band = Array(row["band"]).map { |year| Integer(year) }
              raise ConfigError, "work_eras: #{slug}/#{work} band must be [not_before, not_after]" unless band.size == 2

              Era.new(band: band, label: row.fetch("label") { "#{band[0]}–#{band[1]}" }.to_s)
            elsif row["era"]
              band = period_bands&.lookup(row["era"])
              if band.nil?
                raise ConfigError,
                      "work_eras: #{slug}/#{work} era #{row['era'].inspect} has no config/period_bands.yml row"
              end

              Era.new(band: band, label: row["era"].to_s)
            end
      { era: era, note: row["note"].to_s }
    end
  end
end
