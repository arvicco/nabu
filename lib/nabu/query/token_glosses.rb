# frozen_string_literal: true

require_relative "../errors"
require_relative "../normalize"

module Nabu
  module Query
    # Token glosses — the morph façade's sibling (conventions §6.1): the
    # upstream LEXICAL gloss some sources store on each token, made
    # displayable on every lemma hit and filterable on the lemma-anchored
    # token pass (`search --lemma X --gloss Y`, composing with --morph).
    #
    # One row per source: the token key that carries the gloss and the
    # gloss's language. Measured shapes (fixture + held canonical census):
    #
    # - bhsa "gloss": English, per lexeme, on every word (426,590 words,
    #   ~6.1k distinct glosses). The lemma key is the CONSONANTAL lexeme
    #   (LemmaKeys), so homographs merge (דבר = "speak" / "word"); the
    #   gloss filter splits them back apart.
    # - aes "gloss": German contextual translation (upstream
    #   cotext_translation) — 783,162 of 815,027 tokens (96.1%).
    # - achemenet "eng": English, from upstream's BabyLemmatizer (the
    #   source's lemma tier is silver; the gloss shares that provenance) —
    #   218,568 of 262,128 tokens.
    # - tlhdig "gloss": German, minted only beside the lemma of a selected
    #   (or single-candidate) analysis — the aoxml lemma discipline.
    #
    # Deliberately NOT rows:
    # - tla-hf "gloss" is GRAMMATICAL (Leipzig labels, 259 distinct values
    #   over all 212,018 tokens: PREP, N.m, -3sg.m, "(undefined)" …) — a
    #   morphology-class layer, not a word meaning.
    # - ceipom "meaning" (English, 32,917 of 37,041 tokens) is lexical, but
    #   the source is the EQUIVALENCE tier: its lemma rows are Latin keys
    #   (latin_equivalent), which the token pass does not yet read. A row
    #   here would filter nothing — it waits for that wiring.
    #
    # Matching is whole-word and case-insensitive over the NFC gloss
    # ("glas" finds "Fayence; Glas (aus Silicium)"; "Fay" finds nothing):
    # glosses are short free text, and a substring match would make
    # "art" find "party".
    module TokenGlosses
      # A blank gloss query: caller-fixable, surfaced as a usage error.
      class Error < Nabu::Error; end

      Field = Data.define(:key, :language)

      FIELDS = {
        "bhsa" => Field.new(key: "gloss", language: "en"),
        "aes" => Field.new(key: "gloss", language: "de"),
        "achemenet" => Field.new(key: "eng", language: "en"),
        "tlhdig" => Field.new(key: "gloss", language: "de")
      }.freeze

      module_function

      # The sources carrying a registered gloss layer.
      def sources = FIELDS.keys

      # The token's upstream lexical gloss (stripped), or nil — an
      # unregistered source, a non-token, or a blank value.
      def gloss(token, source:)
        field = FIELDS[source]
        return nil unless field && token.is_a?(Hash)

        value = token[field.key]
        return nil unless value.is_a?(String)

        value = value.strip
        value.empty? ? nil : value
      end

      # A whole-word, case-insensitive matcher for +query+ (raises Error on
      # a blank query).
      def matcher(query)
        text = Normalize.nfc(query.to_s.strip).downcase
        raise Error, "empty gloss — give a word to look for, e.g. king" if text.empty?

        /(?<![[:alnum:]])#{Regexp.escape(text)}(?![[:alnum:]])/
      end

      # Does +token+'s gloss contain the +matcher+'s word(s)?
      def match?(token, matcher, source:)
        value = gloss(token, source: source)
        !value.nil? && matcher.match?(Normalize.nfc(value).downcase)
      end
    end
  end
end
