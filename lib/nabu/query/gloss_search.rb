# frozen_string_literal: true

require_relative "catalog_join"
require_relative "../store/gloss_index"

module Nabu
  module Query
    # Search over upstream TOKEN GLOSSES across lemmas (`nabu search --gloss
    # WORD` with no --lemma): the read side of Store::GlossIndex. "king"
    # finds every word some source glosses king — BHSA's Hebrew and Aramaic
    # מלך, achemenet's šarru, tlhdig's LUGAL (as König) — each hit one WORD
    # (lemma + upstream gloss + its token/passage counts) with its first
    # attestation's passage. The attestations themselves are the existing
    # lemma-anchored pass: `search --lemma <lemma> --gloss <word>`.
    #
    # == Desk rule: precompiled index only
    #
    # The page is answered from token_glosses (bm25, then the most-attested
    # word first) plus a primary-key catalog join for the displayed hits'
    # example passages — never a token scan. A fulltext file without the
    # lane raises IndexMissing carrying the build hint.
    #
    # == Query grammar (the translations lane's, deliberately small)
    #
    # Words AND together; "double quotes" make a phrase; a trailing *
    # makes a prefix (könig* also finds "Königs"). Matching is whole-word,
    # case- and diacritic-insensitive: the query folds the ONE way the index
    # folded (GlossIndex.fold). User text reaches SQL only as the bound
    # MATCH parameter, each word re-quoted.
    #
    # == Filters
    #
    # --lang (the attesting passage's language, code-variant aware) and
    # --source/--axis ride INSIDE the MATCH as sentinel columns. --license
    # is catalog-side (the example passage's effective license — the
    # source's, bar a document override), announced through the shared
    # incomplete-page hint when it thins a full window.
    class GlossSearch
      include CatalogJoin

      # The absent-index condition (desk rule).
      class IndexMissing < Nabu::Error
        def initialize
          super("no token-gloss index in this fulltext file — build it with " \
                "`bundle exec rake index:glosses` (the next nabu rebuild also derives it)")
        end
      end

      # One hit: a word — its source, the attesting passage's language, the
      # lemma (empty for a lemma-less token, then +form+ is the word), the
      # upstream gloss verbatim, token and passage counts — and its first
      # attestation (urn + surface form + the passage's text).
      Result = Data.define(:source, :language, :lemma, :form, :gloss, :tokens, :passages, :urn, :text,
                           :document_title, :license_class, :credit)

      # Same candidate over-fetch as TranslationSearch: only the --license
      # filter thins the window (the rest ride inside the MATCH).
      # const: the house over-fetch multiplier (limit×10 bm25 hits), not a corpus claim
      INNER_LIMIT_FACTOR = 10

      WORD = /[\p{L}\p{N}\p{M}]+/

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      def available? = !@fulltext.nil? && Store::GlossIndex.built?(@fulltext)

      # [[slug, words, tokens]] the CURRENT build indexed; nil when absent.
      def scope
        return nil unless available?

        @fulltext[Store::GlossIndex::SCOPE_TABLE].order(:slug).select_map(%i[slug words tokens])
      end

      def run(query, lang: nil, license: nil, source: nil, sources: nil, limit: 20)
        raise IndexMissing unless available?

        @incomplete_hint = nil
        match = expression(query)
        return [] if match.nil?

        filters = index_filters(lang, source, sources)
        match = "(#{match}) AND #{filters}" if filters
        inner_limit = limit * INNER_LIMIT_FACTOR
        words = hits(match, inner_limit)
        rows = catalog_rows(words.map { |word| word.fetch(:passage_id) }.uniq, lang: nil, license: license)
               .to_h { |row| [row.fetch(:passage_id), row] }
        page = words.filter_map { |word| (row = rows[word.fetch(:passage_id)]) && [word, row] }.first(limit)
        note_page_completeness(window_exhausted: words.size >= inner_limit, filters_active: !license.nil?,
                               page_size: page.size, limit: limit)
        slugs = slug_tokens
        page.map { |word, row| build_result(word, row, slugs) }
      end

      private

      def expression(query)
        folded = Store::GlossIndex.fold(query.to_s)
        parts = []
        rest = folded.gsub(/"([^"]*)"/) do
          parts << quoted(Regexp.last_match(1).scan(WORD))
          " "
        end
        rest.split(/\s+/).each do |token|
          phrase = quoted(token.scan(WORD))
          parts << (phrase && token.end_with?("*") ? "#{phrase}*" : phrase)
        end
        parts = parts.compact
        parts.empty? ? nil : parts.join(" ")
      end

      def quoted(words) = words.empty? ? nil : %("#{words.join(' ')}")

      def index_filters(lang, source, sources)
        conjuncts = []
        if lang
          tokens = Nabu::Languages.code_variants(lang).map { |code| Store::Indexer.language_token(code) }
          conjuncts << column_filter("language", tokens)
        end
        conjuncts << column_filter("source", [Store::Indexer.source_token(source)]) if source
        slugs = Array(sources)
        conjuncts << column_filter("source", slugs.map { |slug| Store::Indexer.source_token(slug) }) if slugs.any?
        conjuncts.empty? ? nil : conjuncts.join(" AND ")
      end

      def column_filter(column, tokens) = "#{column} : (#{tokens.map { |token| %("#{token}") }.join(' OR ')})"

      # bm25-ordered word rows, the most-attested word first among equals.
      # The raw MATCH/bm25 fragments are the standing FTS exception; user
      # text is only ever the bound parameter.
      def hits(match, inner_limit)
        @fulltext[Store::GlossIndex::TABLE]
          .where(Sequel.lit("token_glosses MATCH ?", match))
          .order(Sequel.lit("bm25(token_glosses)"), Sequel.desc(:tokens))
          .limit(inner_limit)
          .select(:source, :lemma, :display, :form, :passage_id, :tokens, :passages)
          .all
      end

      # source sentinel token => slug, from the scope table (the slugs
      # this build indexed).
      def slug_tokens
        @fulltext[Store::GlossIndex::SCOPE_TABLE].select_map(:slug)
                                                 .to_h { |slug| [Store::Indexer.source_token(slug), slug] }
      end

      def build_result(word, row, slugs)
        Result.new(source: slugs.fetch(word.fetch(:source), word.fetch(:source)), language: row.fetch(:language),
                   lemma: word.fetch(:lemma), form: word.fetch(:form), gloss: word.fetch(:display),
                   tokens: word.fetch(:tokens), passages: word.fetch(:passages), urn: row.fetch(:urn),
                   text: row.fetch(:text), document_title: row.fetch(:document_title),
                   license_class: row.fetch(:license_class), credit: row.fetch(:credit))
      end
    end
  end
end
