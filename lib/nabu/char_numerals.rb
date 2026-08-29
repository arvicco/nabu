# frozen_string_literal: true

require "yaml"

module Nabu
  # The letter-numeral fact tables (config/char_numerals.yml, P86-4b/№R-49):
  # the alphabetic numeral conventions — Greek isopsephy, Hebrew gematria,
  # Arabic abjad, Cyrillic titlo numerals, Gothic letter numerals — that
  # Unicode's own numeric property deliberately does not carry (α has no
  # UnicodeData numeric value; the convention is scholarly, not a character
  # property). Read by the universal char card ("numeric (isopsephy): 1").
  #
  # These are project definition (config/, git-shared) — objective, tiny
  # fact tables, the ewts/starling precedent — NOT the curated prose
  # overlay (nabu-data).
  module CharNumerals
    PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "char_numerals.yml")

    # One scheme's answer for a glyph. +extended+ marks values from a
    # scheme's secondary convention (the Hebrew sofit finals), so the card
    # can say which count it is quoting.
    Value = Data.define(:scheme, :name, :value, :extended)

    # The whole file, memoized per path: scheme key => raw table hash.
    def self.table(path: PATH)
      (@table ||= {})[path] ||= YAML.safe_load_file(path)
    end

    def self.reset! = (@table = nil)

    # Every scheme value the glyph carries (case-folded), [] when none —
    # a glyph can legitimately answer under several schemes at once when
    # scripts share letters, so the card lists each labeled.
    def self.lookup(glyph, path: PATH)
      folded = glyph.to_s.downcase
      table(path: path).flat_map do |scheme, row|
        values = row.fetch("values", {})
        extended = row.fetch("extended_values", {})
        hits = []
        if (value = values[folded] || values[glyph.to_s])
          hits << Value.new(scheme: scheme, name: row.fetch("name"), value: value, extended: false)
        end
        if (value = extended[folded] || extended[glyph.to_s])
          hits << Value.new(scheme: scheme, name: row.fetch("name"), value: value, extended: true)
        end
        hits
      end
    end
  end
end
