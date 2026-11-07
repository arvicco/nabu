# frozen_string_literal: true

require_relative "catalog_join"
require_relative "stored_snippet"

module Nabu
  module Query
    # Search over the DECLARED searchable annotation layers (`nabu search
    # --annotations`): the read side of Store::AnnotationIndex — cantus'
    # standardized spellings, korpus16's marginal notes. A query finds the
    # passage whose annotations hold the matching layer; the hit's urn is
    # the passage's own, so `nabu show <urn>` lands on it. The sibling of
    # TranslationSearch, same desk rule, grammar, filters and render.
    #
    # == Desk rule: precompiled index only
    #
    # Answered from passages_annotations (bm25-ranked) plus a primary-key
    # catalog join for the displayed hits — never a scan of
    # annotations_json. A fulltext file without the lane raises
    # IndexMissing carrying the build hint.
    #
    # == Query grammar and folding
    #
    # Words AND, "double quotes" make a phrase, word* a prefix; every word
    # is re-quoted, so an FTS syntax error is impossible by construction.
    # The layers are in their passage's own language and the index folded
    # them by it, so the query folds the main search's way: the union of
    # Normalize.query_forms variants (script-scoped; --lang asserts its
    # language's full rules), ORed — the P6-4 cannot-miss argument, so
    # "jam" reaches the Latin-folded "iam".
    #
    # == Filters
    #
    # --lang (code-variant aware) and --source/--axis ride INSIDE the MATCH
    # on the sentinel columns; --license is catalog-side, announced through
    # the shared incomplete-page hint when it thins a full window.
    class AnnotationSearch
      include CatalogJoin

      # The absent-index condition (desk rule): the surfaces render the
      # message — the exact command that builds the lane.
      class IndexMissing < Nabu::Error
        def initialize
          super("no annotations index in this fulltext file — build it with " \
                "`bundle exec rake index:annotations` (the next nabu rebuild also derives it)")
        end
      end

      # One hit: the passage (urn, language, its stored text) and the
      # annotation layer that matched (its key — "standardized", "notes" —
      # and a stored-text snippet of that layer, earliest term bracketed).
      Result = Data.define(:urn, :language, :text, :layer, :snippet, :document_title, :license_class, :credit)

      # Same candidate over-fetch as TranslationSearch: the catalog side can
      # thin the window; exhaustion is ANNOUNCED via incomplete_hint.
      # census: 2336455, 2026-11-07, live passages carrying a declared key across the 31
      # registry sources (AnnotationKeys) — a window of limit×10 bm25 hits
      INNER_LIMIT_FACTOR = 10

      WORD = /[\p{L}\p{N}\p{M}]+/

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      def available? = !@fulltext.nil? && Store::AnnotationIndex.built?(@fulltext)

      # [[slug, passages]] the CURRENT build indexed — the honest coverage
      # line; nil when the lane is absent.
      def scope
        return nil unless available?

        @fulltext[Store::AnnotationIndex::SCOPE_TABLE].order(:slug).select_map(%i[slug passages])
      end

      def run(query, lang: nil, license: nil, source: nil, sources: nil, limit: 20)
        raise IndexMissing unless available?

        @incomplete_hint = nil
        match = expression(query, lang)
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

      # The MATCH expression for +query+: each query_forms variant parsed
      # by the class-note grammar, the distinct ones ORed; nil when the
      # query folds to no word at all.
      def expression(query, lang)
        variants = Normalize.query_forms(query.to_s, language: lang).filter_map { |form| variant_expression(form) }
        variants = variants.uniq
        return nil if variants.empty?

        variants.one? ? variants.first : variants.map { |variant| "(#{variant})" }.join(" OR ")
      end

      def variant_expression(folded)
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

      # bm25-ordered passage ids. The raw MATCH/bm25 fragments are the
      # standing FTS exception; user text is only ever the bound parameter.
      def hits(match, inner_limit)
        @fulltext[Store::AnnotationIndex::TABLE]
          .where(Sequel.lit("passages_annotations MATCH ?", match))
          .order(Sequel.lit("bm25(passages_annotations)"))
          .limit(inner_limit)
          .select_map(Sequel.lit("rowid"))
      end

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
        page.filter_map do |row|
          input = inputs.fetch(row.fetch(:passage_id))
          layers = AnnotationKeys.spec_layers(input.fetch(:annotations_json),
                                              AnnotationKeys.specs_for(input.fetch(:slug)))
          # An index row whose catalog layer is gone (the index predates a
          # load that has not refreshed it) is not served as a hit.
          next if layers.empty?

          language = row.fetch(:language)
          label, text, spec = matched_layer(layers, terms, language)
          Result.new(urn: row.fetch(:urn), language: language, text: row.fetch(:text), layer: label,
                     snippet: StoredSnippet.build(text: text, language: AnnotationKeys.fold_language(spec, language),
                                                  terms: terms),
                     document_title: row.fetch(:document_title), license_class: row.fetch(:license_class),
                     credit: row.fetch(:credit))
        end
      end

      # The first layer (a korpus16 page carries dozens of notes) whose
      # folded text carries a query term under any of its query forms,
      # else the first layer.
      def matched_layer(layers, terms, language)
        layers.find do |_label, text, spec|
          folded = AnnotationKeys.fold(text, spec, language)
          terms.any? { |term| Normalize.query_forms(term, language: language).any? { |form| folded.include?(form) } }
        end || layers.first
      end
    end
  end
end
