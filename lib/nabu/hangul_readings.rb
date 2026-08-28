# frozen_string_literal: true

require "yaml"

module Nabu
  # The hangul jamo reading table (config/hangul_readings.yml, P86 — the
  # owner's "Hangul cards need IPA or Romanized reading" request): per
  # positional jamo, the Revised Romanization TRANSLITERATION letter and
  # the IPA value. RR-transliteration is letter-wise and deterministic, so
  # a syllable's reading composes mechanically from its jamo (입 → "ib") —
  # and it diverges from Unicode's jamo short names (WEO→wo, YI→ui), which
  # is why this is a fact table, not a name-downcase.
  module HangulReadings
    PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "hangul_readings.yml")

    POSITION_LABELS = {
      "choseong" => "initial", "jungseong" => "vowel", "jongseong" => "final",
      "historical" => "historical"
    }.freeze

    # One positional jamo's reading. +rr+ nil = pre-modern (RR would be an
    # invention); +rr+ "" = the real silent initial; +ipa+ nil = a cluster
    # final whose surface value depends on sound rules the card does not
    # apply (absent is honest).
    Reading = Data.define(:position, :rr, :ipa, :note)

    class << self
      def table(path: PATH)
        (@table ||= {})[path] ||= YAML.safe_load_file(path).each_with_object({}) do |(section, rows), out|
          rows.each do |hex, row|
            out[Integer(hex, 16)] = Reading.new(
              position: section, rr: row["rr"], ipa: presence(row["ipa"]),
              note: row["note"]
            )
          end
        end
      end

      def reset! = (@table = nil)

      def lookup(codepoint, path: PATH) = table(path: path)[codepoint]

      # The composed letter-wise RR reading of a syllable's jamo sequence,
      # or nil when any part is off the table (an archaic syllable stays
      # honest rather than half-romanized).
      def syllable_rr(jamo_codepoints, path: PATH)
        parts = jamo_codepoints.map { |codepoint| lookup(codepoint, path: path)&.rr }
        return nil if parts.any?(&:nil?)

        parts.join
      end

      # The one-line reading description for a jamo (or compat-letter) card:
      # "b (RR) · IPA [p̚] — final", "silent — the initial ieung", or the
      # historical note. nil for a non-jamo code point. A COMPAT letter
      # (U+3131… ㅂ) resolves through its positional twins by UCD name
      # ("HANGUL LETTER PIEUP" → CHOSEONG/JONGSEONG PIEUP), initial and
      # final both when they differ.
      def describe(codepoint, ucd: nil, path: PATH)
        if (reading = lookup(codepoint, path: path))
          return describe_one(reading)
        end
        return nil unless ucd

        name = ucd.lookup(codepoint)&.name
        return nil unless name&.start_with?("HANGUL LETTER ")

        suffix = name.delete_prefix("HANGUL LETTER ")
        twins = table(path: path).filter_map do |twin_cp, reading|
          twin = ucd.lookup(twin_cp)
          reading if twin && twin.name.end_with?(" #{suffix}")
        end
        return nil if twins.empty?

        twins.map { |reading| describe_one(reading) }.uniq.join(" · ")
      end

      private

      def describe_one(reading)
        label = POSITION_LABELS.fetch(reading.position, reading.position)
        if reading.rr.nil?
          [reading.ipa && "IPA [#{reading.ipa}]", reading.note].compact.join(" — ")
        elsif reading.rr.empty?
          "silent — #{reading.note || "#{label} ieung"}"
        else
          ["#{reading.rr} (RR)", reading.ipa && "IPA [#{reading.ipa}]"].compact.join(" · ") +
            " — #{label}"
        end
      end

      def presence(value) = value.to_s.empty? ? nil : value
    end
  end
end
