# frozen_string_literal: true

require_relative "catalog_join"
require_relative "stored_snippet"
require_relative "../gloss_lines"
require_relative "../store/gloss_line_index"

module Nabu
  module Query
    # Content search over the passages' upstream TOKEN GLOSSES (`nabu
    # search --gloss-lines QUERY`): the read side of Store::GlossLineIndex.
    # "king" finds every PASSAGE with a word glossed king — BHSA's Hebrew
    # and Aramaic verses, achemenet's Akkadian leases, tlhdig's Hittite
    # lines (as König) — and, because the glosses are read as one line in
    # token order, words AND within the passage ("king eternity" is Dan
    # 2:4) and a quoted phrase runs across tokens ("to the king"). The
    # sibling of the word-grain GlossSearch (`--gloss WORD`: which words,
    # one row per lemma+gloss) and of AnnotationSearch (same desk rule,
    # grammar, filters and render).
    #
    # == Desk rule: precompiled index only
    #
    # Answered from passages_gloss_lines (bm25-ranked) plus a primary-key
    # catalog join for the displayed hits — never a token scan. A fulltext
    # file without the lane raises IndexMissing carrying the build hint.
    #
    # == Query grammar and folding
    #
    # Words AND, "double quotes" make a phrase, word* a prefix; every word
    # is re-quoted, so an FTS syntax error is impossible by construction.
    # The index folded each gloss by its declared GLOSS language, so the
    # query folds once per declared gloss language (GlossLines.query_forms),
    # the distinct forms ORed — never by the passage language.
    #
    # == Filters
    #
    # --lang (the PASSAGE language, code-variant aware) and --source/--axis
    # ride INSIDE the MATCH on the sentinel columns; --license is
    # catalog-side, announced through the shared incomplete-page hint when
    # it thins a full window.
    class GlossLineSearch
      include CatalogJoin

      # The absent-index condition (desk rule): the surfaces render the
      # message — the exact command that builds the lane.
      class IndexMissing < Nabu::Error
        def initialize
          super("no gloss-lines index in this fulltext file — build it with " \
                "`bundle exec rake index:gloss_lines` (the next nabu rebuild also derives it)")
        end
      end

      # One hit: the passage (urn, language, its stored text, source), a
      # snippet of its gloss line with the earliest term bracketed, and the
      # matching tokens as [[surface form, upstream gloss], …] in token order.
      Result = Data.define(:urn, :language, :text, :source, :snippet, :words, :document_title, :license_class,
                           :credit)

      # The house over-fetch: the catalog side can thin the window;
      # exhaustion is ANNOUNCED via incomplete_hint.
      # const: the house over-fetch multiplier (limit×10 bm25 hits), not a corpus claim
      INNER_LIMIT_FACTOR = 10

      WORD = /[\p{L}\p{N}\p{M}]+/
      WORD_CLASS = "[\\p{L}\\p{N}\\p{M}]"

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      def available? = !@fulltext.nil? && Store::GlossLineIndex.built?(@fulltext)

      # [[slug, passages]] the CURRENT build indexed — the honest coverage
      # line; nil when the lane is absent.
      def scope
        return nil unless available?

        @fulltext[Store::GlossLineIndex::SCOPE_TABLE].order(:slug).select_map(%i[slug passages])
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
        build_results(page, terms(query))
      end

      private

      # The MATCH expression: each gloss-language fold of the query parsed
      # by the class-note grammar, the distinct ones ORed; nil when the
      # query folds to no word at all.
      def expression(query)
        variants = GlossLines.query_forms(query).filter_map { |form| variant_expression(form) }.uniq
        return nil if variants.empty?

        variants.one? ? variants.first : variants.map { |variant| "(#{variant})" }.join(" OR ")
      end

      def variant_expression(folded)
        parts = parse(folded).map do |words, prefix|
          phrase = %("#{words.join(' ')}")
          prefix ? "#{phrase}*" : phrase
        end
        parts.empty? ? nil : parts.join(" ")
      end

      # The grammar's terms: [[words, prefix?], …] — a quoted phrase is one
      # term, every other whitespace-separated token one term.
      def parse(text)
        terms = []
        rest = text.gsub(/"([^"]*)"/) do
          words = Regexp.last_match(1).scan(WORD)
          terms << [words, false] unless words.empty?
          " "
        end
        rest.split(/\s+/).each do |token|
          words = token.scan(WORD)
          terms << [words, token.end_with?("*")] unless words.empty?
        end
        terms
      end

      # The pristine query terms, for locating the match on display.
      def terms(query) = parse(query.to_s)

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
        @fulltext[Store::GlossLineIndex::TABLE]
          .where(Sequel.lit("passages_gloss_lines MATCH ?", match))
          .order(Sequel.lit("bm25(passages_gloss_lines)"))
          .limit(inner_limit)
          .select_map(Sequel.lit("rowid"))
      end

      # The displayed hits' annotations + source slugs — one primary-key
      # probe for the page (≤ limit rows), never a scan.
      def line_inputs(ids)
        @catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:id] => ids)
          .select(Sequel[:passages][:id], Sequel[:passages][:annotations_json], Sequel[:sources][:slug])
          .to_hash(:id)
      end

      def build_results(page, terms)
        inputs = line_inputs(page.map { |row| row.fetch(:passage_id) })
        page.filter_map do |row|
          input = inputs.fetch(row.fetch(:passage_id))
          slug = input.fetch(:slug)
          entries = GlossLines.entries(input.fetch(:annotations_json), slug)
          # An index row whose catalog glosses are gone (the index predates
          # a load that has not refreshed it) is not served as a hit.
          next if entries.empty?

          Result.new(urn: row.fetch(:urn), language: row.fetch(:language), text: row.fetch(:text), source: slug,
                     snippet: snippet(entries, slug, terms), words: matched_words(entries, slug, terms),
                     document_title: row.fetch(:document_title), license_class: row.fetch(:license_class),
                     credit: row.fetch(:credit))
        end
      end

      # A stored-text snippet of the gloss line (folded by the gloss
      # language), the earliest term — a whole phrase when quoted —
      # bracketed; whole-word unless the query carries a prefix term.
      def snippet(entries, slug, terms)
        StoredSnippet.build(text: GlossLines.line(entries), language: GlossLines.language(slug),
                            terms: terms.map { |words, _prefix| words.join(" ") },
                            word: terms.none? { |_words, prefix| prefix })
      end

      # The tokens whose glosses realize a term: every whole-word (or
      # prefix) occurrence of a term in the folded line, a phrase across
      # adjacent glosses naming every token it spans.
      def matched_words(entries, slug, terms)
        folded = entries.map { |_index, _form, gloss| GlossLines.fold(gloss, slug) }
        spans = []
        line = +""
        folded.each do |text|
          line << " " unless line.empty?
          spans << [line.length, line.length + text.length]
          line << text
        end
        hits = terms.flat_map { |words, prefix| occurrences(line, words, prefix, slug) }
        entries.each_index.filter_map do |i|
          start, finish = spans[i]
          [entries[i][1], entries[i][2]] if hits.any? { |from, to| from < finish && to > start }
        end
      end

      def occurrences(line, words, prefix, slug)
        folded = words.map { |word| GlossLines.fold(word, slug) }
        body = folded.map { |word| Regexp.escape(word) }.join("[^\\p{L}\\p{N}\\p{M}]+")
        source = "(?<!#{WORD_CLASS})#{body}#{"(?!#{WORD_CLASS})" unless prefix}"
        pattern = Regexp.new(source.encode(Encoding::UTF_8))
        line.to_enum(:scan, pattern).map { [Regexp.last_match.begin(0), Regexp.last_match.end(0)] }
      end
    end
  end
end
