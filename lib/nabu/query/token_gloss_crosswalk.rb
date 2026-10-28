# frozen_string_literal: true

require "json"

require_relative "../normalize"
require_relative "../store/indexer"
require_relative "catalog_join"
require_relative "token_glosses"

module Nabu
  module Query
    # The crosswalked token gloss: a source whose tokens carry
    # no gloss of their own but DO carry a lexeme id in ANOTHER source's
    # lexeme space borrows that source's gloss at READ time — no index, no
    # precomputation, nothing stored.
    #
    # The one row today is dss → bhsa: DSS words carry lex_etcbc, the ETCBC
    # crosswalk onto BHSA's lexeme ids (422,325 of 422,424 lex_etcbc-bearing
    # words name a BHSA lexeme, 99.98%), and BHSA words carry the per-lexeme
    # English "gloss". The join, per distinct (lex, language) on a result
    # page:
    #
    #   1. the lemma index narrows to the passages attesting the token's
    #      CONSONANTAL lexeme (lex_utf8_etcbc folds exactly as bhsa's
    #      lex_utf8 did — the same both-sides fold LemmaSearch relies on),
    #      so the probe is bounded by that lemma's attestation count, never
    #      a corpus scan;
    #   2. among those, the visible target-source passages whose stored
    #      annotations mention the exact "lex":"<id>" (a SQL LIKE prefilter
    #      — the canonical JSON never pads), checked in passage order and in
    #      slices so a common lexeme stops at the first slice;
    #   3. that passage's token with the exact lex AND language (BHSA lexeme
    #      ids are per-language: Hebrew and Aramaic KFDJ/ are distinct
    #      entries) supplies the gloss.
    #
    # The exact-lex join is what keeps consonantal homographs apart (DSS
    # <D "unto" never borrows BHSA <D=/ "witness"). No target in the
    # catalog, or no matching token, is an honest nil. Results are memoized
    # per instance (one query page).
    class TokenGlossCrosswalk
      include CatalogJoin

      Row = Data.define(:key, :lemma_key, :lang_key, :target, :target_key)

      ROWS = {
        "dss" => Row.new(key: "lex_etcbc", lemma_key: "lex_utf8_etcbc", lang_key: "lang_etcbc",
                         target: "bhsa", target_key: "lex")
      }.freeze

      # DSS lang_etcbc's two values onto the target tokens' "lang" codes.
      LANGUAGE_BY_NAME = { "Hebrew" => "hbo", "Aramaic" => "arc" }.freeze

      # const: candidate passage ids per probe query (an IN-list size), not a corpus claim
      SLICE = 500

      def self.sources = ROWS.keys

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
        @memo = {}
      end

      # The crosswalked gloss for +token+ of +source+ (+language+ = its
      # passage language, the fold key), or nil.
      def gloss(token, source:, language:)
        row = ROWS[source]
        return nil unless row && token.is_a?(Hash)

        lex = token[row.key]
        consonantal = token[row.lemma_key]
        return nil unless lex.is_a?(String) && !lex.empty? && consonantal.is_a?(String)

        lang = LANGUAGE_BY_NAME.fetch(token[row.lang_key], token["lang"])
        @memo.fetch([row.target, lex, lang]) do |key|
          @memo[key] = resolve(row, lex, lang, Normalize.search_form(consonantal, language: language))
        end
      end

      private

      def resolve(row, lex, lang, folded)
        return nil if folded.to_s.empty?

        needle = %("#{row.target_key}":#{JSON.generate(lex)})
        pattern = "%#{@catalog[:passages].escape_like(needle)}%"
        candidates(folded).each_slice(SLICE) do |slice|
          target_annotations(row.target, slice, pattern).each do |json|
            gloss = matching_gloss(json, row, lex, lang)
            return gloss if gloss
          end
        end
        nil
      end

      # The lemma index's passage keys for +folded+, in passage order.
      def candidates(folded)
        key = Store::Indexer.lemma_passage_key(@fulltext)
        @fulltext[Store::Indexer::LEMMA_TABLE].where(lemma_folded: folded).order(key).distinct.select_map(key)
      end

      def target_annotations(target, slice, pattern)
        key = Store::Indexer.lemma_passage_key(@fulltext) == :urn ? :urn : :id
        visible_passages(lang: nil, license: nil, source: target)
          .where(Sequel[:passages][key] => slice)
          .where(Sequel.like(Sequel[:passages][:annotations_json], pattern))
          .order(Sequel[:passages][:id])
          .select_map(Sequel[:passages][:annotations_json])
      end

      def matching_gloss(json, row, lex, lang)
        tokens = JSON.parse(json)["tokens"]
        return nil unless tokens.is_a?(Array)

        tokens.grep(Hash).each do |token|
          next unless token[row.target_key] == lex && (lang.nil? || token["lang"] == lang)

          gloss = TokenGlosses.gloss(token, source: row.target)
          return gloss if gloss
        end
        nil
      end
    end
  end
end
