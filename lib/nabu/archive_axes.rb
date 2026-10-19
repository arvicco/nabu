# frozen_string_literal: true

require "yaml"
require_relative "period_bands"
require_relative "regnal_years"

module Nabu
  # The ruled archive-grain axes table (config/archive_axes.yml): for a
  # source whose documents carry only an upstream ARCHIVE label (the
  # publication group) and a designation, each archive's findspot — the
  # name plus the gazetteer refs the catalog already holds for it — and
  # its dating ladder, first hit wins:
  #
  #   1. a designation naming a REIGN volume ("Strassmaier, Cyrus 45")
  #      → the HELD regnal table's whole-reign span (precision
  #      "regnal-reign"; the ruler key must exist in regnal_years.yml);
  #   2. the archive's own stated span (a volume title's dates —
  #      precision "volume");
  #   3. the source's corpus period band (a period_bands.yml row).
  #
  # An archive without a findspot (a publication grouping many sites)
  # answers no place. Every archive row carries its reasoning (`note`).
  class ArchiveAxes
    class ConfigError < Nabu::Error; end

    Dating = Data.define(:band, :raw, :precision)

    def self.load(path, period_bands: PeriodBands.default, regnal: RegnalYears.default)
      return nil unless File.file?(path)

      new(YAML.safe_load_file(path) || {}, period_bands: period_bands, regnal: regnal)
    end

    def self.default
      return @default if defined?(@default)

      @default = load(File.join(Nabu::Config::PROJECT_ROOT, "config", "archive_axes.yml"))
    end

    def self.reset!
      remove_instance_variable(:@default) if defined?(@default)
    end

    def initialize(doc, period_bands:, regnal:)
      @regnal = regnal
      @sources = (doc["sources"] || {}).to_h do |slug, spec|
        corpus_label = spec["corpus_period"]
        corpus_band = corpus_label && period_bands&.lookup(corpus_label)
        if corpus_label && corpus_band.nil?
          raise ConfigError, "archive_axes: #{slug} corpus_period #{corpus_label.inspect} has no period_bands row"
        end

        archives = (spec["archives"] || {}).to_h { |name, row| [name.to_s, parse_archive(slug, name, row || {})] }
        [slug.to_s, { corpus: corpus_band && [corpus_band, corpus_label.to_s], archives: archives }]
      end
    end

    # [name, ref] for +archive+'s findspot, or nil.
    def place(slug, archive)
      row = @sources.dig(slug, :archives, archive.to_s) or return nil
      row[:place] && [row[:place], row[:place_ref]]
    end

    # The Dating for one document (archive + designation), or nil when the
    # source has no table.
    def dating(slug, archive, designation)
      source = @sources[slug] or return nil
      row = source[:archives][archive.to_s]
      reign_dating(row, designation) || stated_dating(row) || corpus_dating(source)
    end

    private

    def reign_dating(row, designation)
      reigns = row && row[:reigns] or return nil
      word = reigns[:pattern].match(designation.to_s)&.[](1) or return nil
      ruler = reigns[:rulers][word] or return nil
      span = @regnal.span(ruler, 0)
      Dating.new(band: span, raw: "#{designation} — #{ruler} reign volume", precision: "regnal-reign")
    end

    def stated_dating(row)
      return nil unless row && row[:band]

      Dating.new(band: row[:band], raw: row[:band_raw], precision: "volume")
    end

    def corpus_dating(source)
      band, label = source[:corpus]
      band && Dating.new(band: band, raw: "#{label} (corpus period)", precision: "period")
    end

    def parse_archive(slug, name, row)
      {
        place: row["place"], place_ref: row["place_ref"],
        band: row["band"] && Array(row["band"]).map { |year| Integer(year) },
        band_raw: row["band_raw"],
        reigns: row["reigns"] && parse_reigns(slug, name, row["reigns"])
      }
    end

    def parse_reigns(slug, name, spec)
      rulers = (spec["rulers"] || {}).to_h { |word, key| [word.to_s, key.to_s] }
      rulers.each_value do |key|
        next unless @regnal.nil? || @regnal.span(key, 0) == :unruled

        raise ConfigError, "archive_axes: #{slug}/#{name} ruler #{key.inspect} has no regnal_years.yml row"
      end
      { pattern: Regexp.new(spec.fetch("pattern")), rulers: rulers }
    end
  end
end
