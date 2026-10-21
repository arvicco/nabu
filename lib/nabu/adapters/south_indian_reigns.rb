# frozen_string_literal: true

require "yaml"

module Nabu
  # The South-Indian regnal accession table (owner-approved):
  # config/south_indian_reigns.yml rows turning a REGNAL dating statement
  # of the DHARMA Tamil-country titles ("time of Rājarāja I Cōḻa, year 19")
  # into a CE envelope. The regnal sibling of Nabu::Eras (an era-typed
  # year) and Nabu::RegnalYears (cdli's Mesopotamian reigns).
  #
  # Each reign carries its accession as a RANGE where the field's
  # chronologies disagree, one cited chronology per dynasty, and a
  # generous end. Regnal year N → [earliest accession + N − 1, latest
  # accession + N] (a regnal year straddles two Julian years); no usable
  # year → the whole-reign span. A title spelling maps to its candidate
  # reigns: homonyms convert as the envelope over the candidates whose
  # reign can reach year N, never a pick; alternating titles
  # (Rājakesari / Parakesari) and floating chronologies are declared
  # unconvertible and mint nothing — as does any unlisted spelling.
  #
  # It lives beside its consumer under adapters/ (not in the shared
  # lib/nabu/ core like Nabu::Eras) so the derivation fingerprint scopes
  # it to the adapters that reference it: a table-code edit re-parses the
  # DHARMA Tamil source, never the whole library.
  class SouthIndianReigns
    Reign = Data.define(:key, :label, :dynasty, :accession_low, :accession_high, :end_year) do
      # The highest regnal year the reign can carry.
      def max_year = end_year - accession_low + 1

      def span(year)
        return [accession_low, end_year] if year.nil?
        return nil if year > max_year

        [accession_low + year - 1, accession_high + year]
      end
    end

    # One conversion: the candidate reigns that survived, the regnal year
    # (nil = the whole-reign span) and the CE envelope.
    Conversion = Data.define(:reigns, :regnal_year, :not_before, :not_after) do
      def to_date_bounds = { "not_before" => not_before, "not_after" => not_after }
    end

    def self.load(path)
      return nil unless File.file?(path)

      raw = YAML.safe_load_file(path) || {}
      dynasties = raw.fetch("dynasties", {})
      reigns = raw.fetch("reigns", {}).to_h { |key, entry| [key, build_reign(key, entry, dynasties)] }
      titles = raw.fetch("titles", {}).to_h do |title, keys|
        unknown = Array(keys) - reigns.keys
        raise ArgumentError, "south_indian_reigns.yml #{title}: unknown reign(s) #{unknown.join(', ')}" if unknown.any?

        [title, Array(keys)]
      end
      new(dynasties: dynasties, reigns: reigns, titles: titles, unconvertible: raw.fetch("unconvertible", {}),
          max_envelope: raw["max_envelope_years"] && Integer(raw["max_envelope_years"]))
    end

    def self.build_reign(key, entry, dynasties)
      unless dynasties.dig(entry["dynasty"], "source")
        raise ArgumentError, "south_indian_reigns.yml #{key}: dynasty #{entry['dynasty'].inspect} has no source"
      end

      low, high = Array(entry.fetch("accession")).map { |year| Integer(year) }
      high ||= low
      end_year = Integer(entry.fetch("end"))
      unless high.between?(low, end_year)
        raise ArgumentError, "south_indian_reigns.yml #{key}: accession #{low}–#{high} / end #{end_year} out of order"
      end

      Reign.new(key: key, label: entry["label"] || key, dynasty: entry["dynasty"],
                accession_low: low, accession_high: high, end_year: end_year)
    end
    private_class_method :build_reign

    # The config-repo table, memoized per process (the Eras precedent).
    def self.default
      return @default if defined?(@default)

      @default = load(File.join(Nabu::Config::PROJECT_ROOT, "config", "south_indian_reigns.yml"))
    end

    def self.reset!
      remove_instance_variable(:@default) if defined?(@default)
    end

    # The title fold: NFC, downcase, spaces / dots / hyphens dropped.
    def self.fold(name)
      name.to_s.unicode_normalize(:nfc).downcase.gsub(/[.\s-]/, "")
    end

    # A trailing reference ("29 (SII 2.1)") and an ordinal suffix ("3rd")
    # are not part of the year; "(5)" is the editor's restored year.
    YEAR_REFERENCE = /\s*\((?:SII|EI|ARE)\b[^)]*\)\z/
    YEAR_SUM = /\A\d+(?:\s*\+\s*\d+)*\z/

    # The regnal year a title's "year …" text gives as a number — an
    # integer, an ordinal, or a sum ("4 + 9", the "year N opposite to
    # year M" count) — or nil (lost, damaged, doubted, cyclic-year names:
    # the whole-reign span applies).
    def self.regnal_year(text)
      return nil if text.nil?

      cleaned = text.strip.sub(YEAR_REFERENCE, "").sub(/\A\((\d+)\)\z/, '\1').sub(/\A(\d+)(?:st|nd|rd|th)\z/, '\1')
      return nil unless cleaned.match?(YEAR_SUM)

      year = cleaned.split("+").sum { |part| Integer(part.strip, 10) }
      year.positive? ? year : nil
    end

    def initialize(dynasties:, reigns:, titles:, unconvertible:, max_envelope: nil)
      @dynasties = dynasties
      @max_envelope = max_envelope
      @reigns = reigns
      @titles = titles.transform_keys { |title| self.class.fold(title) }
      @title_keys = titles.keys
      @unconvertible = unconvertible.transform_keys { |title| self.class.fold(title) }
    end

    attr_reader :title_keys, :max_envelope

    def size = @reigns.size

    def reign_keys = @reigns.keys

    def label(key) = @reigns.fetch(key).label

    # The dynasty chronology a reign's accession follows.
    def source(key) = @dynasties.dig(@reigns.fetch(key).dynasty, "source")

    # The candidate reign keys for a title spelling, or nil.
    def candidates(title) = @titles[self.class.fold(title)]

    def unconvertible?(title) = @unconvertible.key?(self.class.fold(title))

    # Title + regnal year (Integer, or nil for the whole-reign span) →
    # Conversion over the surviving candidates, or nil (unlisted or
    # declared unconvertible title; a year beyond every candidate's reign;
    # an envelope wider than the table's max_envelope_years — a claim
    # coarser than the dynasty's period band already makes).
    def convert(title, year)
      keys = candidates(title) or return nil
      spans = keys.filter_map do |key|
        span = @reigns.fetch(key).span(year)
        span && [key, span]
      end
      return nil if spans.empty?

      not_before = spans.map { |_, span| span.first }.min
      not_after = spans.map { |_, span| span.last }.max
      return nil if @max_envelope && not_after - not_before > @max_envelope

      Conversion.new(reigns: spans.map(&:first), regnal_year: year, not_before: not_before, not_after: not_after)
    end
  end
end
