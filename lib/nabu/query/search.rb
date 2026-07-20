# frozen_string_literal: true

require_relative "../normalize"
require_relative "catalog_join"

module Nabu
  # Query surface over the derived store (architecture §2: lib/nabu/query/).
  module Query
    # Full-text search: FTS5 MATCH over the index of boundary-folded search
    # forms (P6-4), then a catalog join (the shared CatalogJoin module) for
    # display text, language, and license filtering.
    #
    # == Why the query matches a UNION of folds
    #
    # The index carries text_normalized exactly as stored: the per-language
    # search form minted at the adapter boundary (Passage.new →
    # Normalize.search_form — generic mark-strip + downcase everywhere, plus
    # grc final-sigma ς→σ and lat v→u/j→i; conventions.md §9). A query
    # carries NO language, so no single per-language fold can be picked.
    # Normalize.query_forms therefore returns every distinct variant (generic
    # + each language rule applied to the generic form) and we OR them in the
    # MATCH. This cannot miss: a passage in language L is indexed as
    # extra_L(generic(text)), and the variant set always contains
    # extra_L(generic(query)) — the query folds, on that variant, exactly the
    # way the document was folded. And it cannot over-fold: variants are
    # ORed, so the generic variant still matches languages with no extra rule
    # (a Gothic "jah" stays findable even though the lat variant reads "iah").
    #
    # Two-step id join (not ATTACH) and the exact-class license semantics are
    # documented on CatalogJoin, which owns that half.
    class Search
      include CatalogJoin

      # One search hit. `text` is the pristine passage text (for display);
      # `snippet` is the FTS-generated highlight over the FOLDED index form, so
      # its accents are stripped — it marks WHERE the match is, not how the
      # source spelled it. `license_class` is the effective class after override.
      Result = Data.define(:urn, :language, :text, :snippet, :document_title, :license_class)

      # Snippet markers and window (FTS5 snippet(): table, column, start, end,
      # ellipsis, max tokens). column 0 is text_normalized, the only indexed one.
      SNIPPET_SQL = "snippet(passages_fts, 0, '[', ']', '…', 10)"
      # FTS5 default relevance rank; lower (more negative) is a better match.
      RANK_SQL = "bm25(passages_fts)"

      # Pull more FTS hits than the caller's limit so that catalog-side filtering
      # (language/license) can drop non-matching rows and still fill the page.
      # Exhaustion is ANNOUNCED (P35-6): a full window + active filters + a
      # short page sets incomplete_hint (CatalogJoin::INCOMPLETE_PAGE_HINT).
      # census: 5505159, 2026-07-20, live passages at re-measure (3.76M at tuning)
      INNER_LIMIT_FACTOR = 10

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      # Search +query+ and return up to +limit+ Result values in bm25 rank order.
      # +lang+ filters on passage language; +license+ on effective license class.
      # +from+/+to+/+place+ (P15-2) filter on the document's timeline
      # (signed historical years, place LIKE pattern); +facets+ (P17-2) on the
      # document's facet rows ({facet name => pattern} — search --type/
      # --province/--material); +source+ (P22-1) scopes to one source slug.
      # +urn+ restricts the match to one passage — a ranking-independent
      # "is this passage findable by this query" probe (the health golden
      # replay), not a pagination knob. +loans+ (P34-2) keeps only passages
      # whose stored annotations carry ≥1 loan token of that origin code
      # (passage-grain, read straight off annotations_json — no reparse).
      def run(query, lang: nil, license: nil, limit: 20, urn: nil, from: nil, to: nil, place: nil,
              facets: nil, source: nil, loans: nil)
        @incomplete_hint = nil
        variants = Nabu::Normalize.query_forms(query.to_s)
        return [] if variants.first.strip.empty? # generic form first; extras never add characters

        inner_limit = limit * INNER_LIMIT_FACTOR
        hits = fts_hits_with_literal_fallback(variants, inner_limit: inner_limit, urn: urn)
        return [] if hits.empty?

        ordered_ids = hits.map { |row| row.fetch(:passage_id) }
        snippets = hits.to_h { |row| [row.fetch(:passage_id), row.fetch(:snippet)] }
        rows = catalog_rows(ordered_ids, lang: lang, license: license,
                                         from: from, to: to, place: place, facets: facets, source: source,
                                         loans: loans)
               .to_h { |row| [row.fetch(:passage_id), row] }

        # Reassemble in FTS rank order (the catalog query returns no order),
        # dropping ids filtered out catalog-side, then trim to the page.
        page = ordered_ids.filter_map { |id| rows[id] }.first(limit)
        note_page_completeness(
          window_exhausted: hits.size >= inner_limit,
          filters_active: [lang, license, from, to, place, source, loans].compact.any? || (facets || {}).any?,
          page_size: page.size, limit: limit
        )
        page.map { |row| build_result(row, snippets.fetch(row.fetch(:passage_id))) }
      end

      private

      # The user's text passes through as FTS5 syntax first (power queries —
      # AND/OR/NEAR/"phrases" — keep working verbatim). When FTS5 rejects it
      # (owner report 2026-07-18: `search --help` crashed with a raw fts5
      # backtrace; so does any hyphen-leading or unbalanced-quote query),
      # retry ONCE with every token literal-quoted (internal quotes doubled
      # — the escaped form cannot syntax-error), so hyphenated words and
      # option-looking strings just search. Non-fts errors re-raise.
      def fts_hits_with_literal_fallback(variants, inner_limit:, urn: nil)
        fts_hits(match_expression(variants), inner_limit: inner_limit, urn: urn)
      rescue Sequel::DatabaseError => e
        raise unless e.message.match?(/fts5|unterminated string|no such column/)

        literal = variants.map { |variant| literal_expression(variant) }
        fts_hits(match_expression(literal), inner_limit: inner_limit, urn: urn)
      end

      # Every whitespace token as a quoted FTS5 phrase (implicit AND), internal
      # double quotes doubled per the FTS5 string rules.
      def literal_expression(text)
        text.split.map { |token| %("#{token.gsub('"', '""')}") }.join(" ")
      end

      # One variant passes through untouched (preserving the user's own FTS
      # syntax exactly as before); multiple variants are each parenthesized
      # and ORed, so whatever expression the user typed stays intact inside
      # each variant.
      def match_expression(variants)
        return variants.first if variants.one?

        variants.map { |variant| "(#{variant})" }.join(" OR ")
      end

      # FTS5 MATCH. The user's text reaches SQL only as a bound parameter in the
      # MATCH fragment (the one raw-SQL exception, per the Indexer class note);
      # bm25()/snippet() are FTS auxiliary functions with no Sequel dataset API,
      # so they ride along as literal fragments with no user input.
      def fts_hits(match, inner_limit:, urn: nil)
        dataset = @fulltext[Store::Indexer::TABLE]
                  .where(Sequel.lit("passages_fts MATCH ?", match))
        dataset = dataset.where(urn: urn) if urn # urn rides UNINDEXED in the index row
        dataset
          .select(:passage_id, Sequel.lit(SNIPPET_SQL).as(:snippet))
          .order(Sequel.lit(RANK_SQL))
          .limit(inner_limit)
          .all
      end

      def build_result(row, snippet)
        Result.new(
          urn: row.fetch(:urn),
          language: row.fetch(:language),
          text: row.fetch(:text),
          snippet: snippet,
          document_title: row.fetch(:document_title),
          license_class: row.fetch(:license_class)
        )
      end
    end
  end
end
