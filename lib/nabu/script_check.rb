# frozen_string_literal: true

module Nabu
  # The surface-script byte check (P61, D60-b's machine half): classify
  # held text by Unicode script property and name the dominant writing
  # system as a registry script tag (lowercased ISO 15924). The ~script
  # axis claims the script of the text AS HELD — which makes every claim
  # checkable against the bytes; this module is the checker, shared by the
  # layer-suggest census (P61-2) and the script_surface_mismatch health
  # invariant (P61-4).
  #
  # The tag set mirrors the registry's global scripts table where Ruby's
  # regex engine names the property; a text dominated by none of them
  # (punctuation-only, digits) classifies nil — honest, never guessed.
  # P86-2: the mirror claim is now ENFORCED — test/script_check_test.rb is
  # the drift guard (registry tags = PROPERTIES ∪ UNMIRRORED, no ghosts), so
  # a nabu-lects script mint without a row here turns the suite red.
  module ScriptCheck
    PROPERTIES = {
      "latn" => /\p{Latin}/,
      "grek" => /\p{Greek}/,
      "ogam" => /\p{Ogham}/,
      "deva" => /\p{Devanagari}/,
      "ital" => /\p{Old_Italic}/,
      "egyp" => /\p{Egyptian_Hieroglyphs}/,
      "hebr" => /\p{Hebrew}/,
      "arab" => /\p{Arabic}/,
      "syrc" => /\p{Syriac}/,
      "copt" => /\p{Coptic}/,
      "cyrl" => /\p{Cyrillic}/,
      "glag" => /\p{Glagolitic}/,
      "armn" => /\p{Armenian}/,
      "hant" => /\p{Han}/,
      "runr" => /\p{Runic}/,
      "goth" => /\p{Gothic}/,
      "xsux" => /\p{Cuneiform}/,
      "phnx" => /\p{Phoenician}/,
      "tibt" => /\p{Tibetan}/,
      "ethi" => /\p{Ethiopic}/,
      "hang" => /\p{Hangul}/,
      "avst" => /\p{Avestan}/,
      "ugar" => /\p{Ugaritic}/,
      "xpeo" => /\p{Old_Persian}/
    }.freeze

    # Registry scripts a byte check CANNOT mirror, with the reason stated —
    # the drift guard accepts a tag here instead of a PROPERTIES row, so the
    # gap is a documented decision, never an oversight.
    UNMIRRORED = {
      "egyd" => "Egyptian Demotic has no Unicode encoding — held surfaces are " \
                "transliteration (latn) or hieroglyphic; the ~egyd claim is an " \
                "artifact-script fact, not a byte-checkable surface",
      "jpan" => "a COMPOSITE surface (Han + Hiragana + Katakana): its Han " \
                "characters byte-classify as hant, and the kana scripts are not " \
                "separate registry claims — a ~jpan surface is asserted at the " \
                "collection grain, not per byte"
    }.freeze

    # {tag => char count} over +text+, script-bearing characters only.
    def self.classify(text)
      tally = Hash.new(0)
      text.each_char do |char|
        PROPERTIES.each do |tag, property|
          if property.match?(char)
            tally[tag] += 1
            break
          end
        end
      end
      tally
    end

    # [dominant tag, share 0.0..1.0] across +texts+, or [nil, 0.0] when no
    # script-bearing character appears.
    def self.dominant(texts)
      tally = Hash.new(0)
      texts.each { |text| classify(text.to_s).each { |tag, n| tally[tag] += n } }
      total = tally.values.sum
      return [nil, 0.0] if total.zero?

      tag, count = tally.max_by { |_, n| n }
      [tag, count.fdiv(total)]
    end
  end
end
