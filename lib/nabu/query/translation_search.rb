# frozen_string_literal: true

require_relative "catalog_join"
require_relative "stored_snippet"

module Nabu
  module Query
    # Search over ANNOTATION-HELD translations (`nabu search --translations`):
    # the read side of Store::TranslationIndex. A query in the translation's
    # language (English, German, Arabic, Russian, Dutch, Spanish … whatever
    # the registered layers carry) finds the ORIGINAL passage whose
    # annotations hold the matching rendering — the hit's urn is the
    # original's, so `nabu show <urn>` lands on the text itself.
    #
    # == Desk rule: precompiled index only
    #
    # The page is answered from passages_translations (bm25-ranked) plus a
    # primary-key catalog join for the displayed hits — never a scan of
    # annotations_json. A fulltext file without the lane raises
    # IndexMissing carrying the build hint; the surfaces print it.
    #
    # == Query grammar (deliberately small)
    #
    # Words are implicitly ANDed; "double quotes" make a phrase; a trailing
    # * makes a prefix (merod*). Everything else is literal: the query
    # folds the ONE way the index folded (Store::TranslationIndex.fold —
    # NFC, downcase, mark strip), and folding lowercases, so AND/OR/NOT are
    # plain words exactly as in the main search. User text reaches SQL only
    # as the bound MATCH parameter, each word re-quoted — an FTS syntax
    # error is impossible by construction.
    #
    # == Filters
    #
    # --lang (the ORIGINAL passage's language, code-variant aware) and
    # --source/--axis ride INSIDE the MATCH as the sentinel columns the
    # main index uses — no starved post-filter. --license is catalog-side,
    # announced through the shared incomplete-page hint when it thins a
    # full window.
    class TranslationSearch
      include CatalogJoin

      # The absent-index condition (desk rule): the surfaces render the
      # message — the exact command that builds the lane.
      class IndexMissing < Nabu::Error
        def initialize
          super("no translations index in this fulltext file — build it with " \
                "`bundle exec rake index:translations` (the next nabu rebuild also derives it)")
        end
      end

      # One hit: the ORIGINAL passage (urn, language, its stored text) and
      # the translation layer that matched (its annotation key path —
      # "translation", "tr.en", "translations.text_en" — and a stored-text
      # snippet of that layer with the earliest matched term bracketed).
      Result = Data.define(:urn, :language, :text, :layer, :snippet, :document_title, :license_class, :credit)

      # Same candidate over-fetch as Search/Fuzzy: the catalog side (license,
      # the two-level visibility rule) can thin the window; exhaustion is
      # ANNOUNCED via incomplete_hint (P35-6).
      # census: 317267, 2026-10-22, layer-bearing live passages across the 14
      # registry sources (TranslationKeys) — a window of limit×10 bm25 hits
      INNER_LIMIT_FACTOR = 10

      WORD = /[\p{L}\p{N}\p{M}]+/

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      def available? = !@fulltext.nil? && Store::TranslationIndex.built?(@fulltext)

      # [[slug, passages]] the CURRENT build indexed (the scope table) —
      # the honest coverage line; nil when the lane is absent.
      def scope
        return nil unless available?

        @fulltext[Store::TranslationIndex::SCOPE_TABLE].order(:slug).select_map(%i[slug passages])
      end

      def run(query, lang: nil, license: nil, source: nil, sources: nil, limit: 20)
        raise IndexMissing unless available?

        @incomplete_hint = nil
        match = expression(query)
        return [] if match.nil?

        filters = index_filters(lang, source, sources)
        match = "(#{match}) AND #{filters}" if filters
        inner_limit = limit * INNER_LIMIT_FACTOR
        ids = hits(match, inner_limit)
        rows = catalog_rows(ids, lang: nil, license: license).to_h { |row| [row.fetch(:passage_id), row] }
        page = ids.filter_map { |id| rows[id] }.first(limit)
        note_page_completeness(window_exhausted: ids.size >= inner_limit, filters_active: !license.nil?,
                               page_size: page.size, limit: limit)
        build_results(page, words(query))
      end

      private

      # The MATCH expression for +query+ (class note grammar), or nil when
      # the query folds to no word at all.
      def expression(query)
        folded = Store::TranslationIndex.fold(query.to_s)
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

      # bm25-ordered passage ids (rowid = the original passage id). The
      # raw MATCH/bm25 fragments are the standing FTS exception; user text
      # is only ever the bound parameter.
      def hits(match, inner_limit)
        @fulltext[Store::TranslationIndex::TABLE]
          .where(Sequel.lit("passages_translations MATCH ?", match))
          .order(Sequel.lit("bm25(passages_translations)"))
          .limit(inner_limit)
          .select_map(Sequel.lit("rowid"))
      end

      # The pristine query words the snippet locator folds and brackets.
      def words(query) = query.to_s.scan(WORD)

      # The displayed hits' annotations + source slugs — one primary-key
      # probe for the page (≤ limit rows), never a scan.
      def layer_inputs(ids)
        @catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:id] => ids)
          .select(Sequel[:passages][:id], Sequel[:passages][:annotations_json], Sequel[:sources][:slug])
          .to_hash(:id)
      end

      def build_results(page, terms)
        inputs = layer_inputs(page.map { |row| row.fetch(:passage_id) })
        folded_terms = terms.map { |term| Store::TranslationIndex.fold(term) }
        page.filter_map do |row|
          input = inputs.fetch(row.fetch(:passage_id))
          layers = TranslationKeys.layers(input.fetch(:annotations_json), TranslationKeys.specs_for(input.fetch(:slug)))
          # An index row whose catalog layer is gone (the index predates a
          # load that has not refreshed it) is not served as a hit.
          next if layers.empty?

          label, text = matched_layer(layers, folded_terms)
          Result.new(urn: row.fetch(:urn), language: row.fetch(:language), text: row.fetch(:text),
                     layer: label,
                     snippet: StoredSnippet.build(text: text, language: nil, terms: terms),
                     document_title: row.fetch(:document_title), license_class: row.fetch(:license_class),
                     credit: row.fetch(:credit))
        end
      end

      # The first layer whose folded text carries a query term (a passage
      # can hold English AND Arabic renderings; show the one that matched),
      # else the first layer.
      def matched_layer(layers, folded_terms)
        layers.find do |_label, text|
          folded = Store::TranslationIndex.fold(text)
          folded_terms.any? { |term| folded.include?(term) }
        end || layers.first
      end
    end
  end
end
