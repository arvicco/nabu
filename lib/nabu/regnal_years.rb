# frozen_string_literal: true

require "yaml"

module Nabu
  # The ruled regnal-year table (№R-28, 2026-08-11 — the P73-6 scout
  # ratified): config/regnal_years.yml maps cdli's dates_referenced ruler
  # spellings to accession year + reign length under a STATED chronology
  # commitment (middle chronology for the second millennium; Parker &
  # Dubberstein for the astronomically fixed first). The table converts
  # "Šulgi.44" from period-band precision (±100–300 years) to the one
  # conventional year — an unruled ruler stays period-banded and is
  # censused, never guessed.
  class RegnalYears
    def self.load(path)
      return nil unless File.file?(path)

      raw = YAML.safe_load_file(path) || {}
      rows = (raw["rulers"] || {}).transform_values do |entry|
        { accession: Integer(entry.fetch("accession")), reign: Integer(entry.fetch("reign")) }
      end
      new(rows: rows)
    end

    # The config-repo table, memoized per process (ruled config data — the
    # PeriodBands precedent).
    def self.default
      return @default if defined?(@default)

      @default = load(File.join(Nabu::Config::PROJECT_ROOT, "config", "regnal_years.yml"))
    end

    def self.reset!
      remove_instance_variable(:@default) if defined?(@default)
    end

    def initialize(rows:)
      @rows = rows
    end

    def size = @rows.size

    # The absolute span for +ruler+'s year +year_number+:
    #   [y, y]            a numbered year (accession + YY - 1; us2 +1)
    #   [acc, last]       YY = 0 — year unknown, the whole-reign span
    #   :unruled          the ruler has no table row
    #   :out_of_range     YY exceeds the reign — a data error, censused
    def span(ruler, year_number, us2: false)
      entry = @rows[ruler.to_s]
      return :unruled if entry.nil?

      accession = entry[:accession]
      return [accession, accession + entry[:reign] - 1] if year_number.zero?
      return :out_of_range if year_number > entry[:reign]

      year = accession + (year_number - 1) + (us2 ? 1 : 0)
      [year, year]
    end
  end
end
