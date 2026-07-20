# frozen_string_literal: true

require_relative "../normalize"
require_relative "catalog_join"
require_relative "search"

module Nabu
  module Query
    # Proximity search (P14-8): "term A within N words of term B", the
    # TLG-style daily-use collocation probe — `search λόγος --near θεός
    # --window 5`. Built on FTS5's NEAR operator over the SAME index Search
    # uses (Store::Indexer::TABLE, the boundary-folded search forms), so it
    # needs no new schema; the catalog join, snippet, and license semantics are
    # shared with Search verbatim (CatalogJoin + Search's constants/Result).
    #
    # == The FTS5 NEAR mechanics (measured, not assumed)
    #
    # `NEAR("a" "b", N)` matches a passage when at least one instance of each
    # phrase occurs with AT MOST N tokens between them — order-independent, so
    # "a … b" and "b … a" both count. N is FTS5's second argument verbatim:
    # N=0 means the terms are immediately adjacent, N=5 allows up to five words
    # between them. (Boundary probed on SQLite 3.53: N=0 matches only "a b";
    # gap-k passages need N≥k.) That is exactly what `--window N` exposes — no
    # hidden ±1. Default window is 10, FTS5's own default.
    #
    # == NEAR counts FOLDED tokens (conventions §9)
    #
    # The index tokenizes text_normalized — the per-language SEARCH form, marks
    # stripped and downcased (grc ς→σ, lat v→u/j→i). NEAR windows are therefore
    # measured over folded tokens, and both query terms are folded the same way
    # before they reach the MATCH. For most languages folding is per-word
    # (token count preserved), so "N words apart" is honest. The one caveat is
    # the cuneiform fold (akk/sux): sign-joining `-`/`.` and determinative
    # braces open to SPACES, so a single transliterated word (`du-un-nu-um`,
    # `{d}EN.ZU`) becomes several folded tokens and inflates the window count —
    # the snippet still shows what matched, but a window tuned for Greek reads
    # tighter in Akkadian. Said honestly rather than hidden.
    #
    # == Two anchors, one NEAR builder
    #
    # The query carries no language, so each side folds to the Normalize
    # .query_forms UNION (the P6-4 argument: the union always contains the
    # variant the document was folded on). A NEAR clause needs ONE phrase per
    # side, so the match is the OR of NEAR clauses over the cartesian product of
    # the two sides' variants — `NEAR("av" "bv", N) OR …`. Whichever variant
    # pair the document folded on is present, so it cannot miss; the others just
    # never match.
    #
    #   - text anchor (`--near` with a positional query): anchor variants =
    #     query_forms(query).
    #   - lemma anchor (`--lemma X --near`): the lemma side expands to its
    #     attested FOLDED surface forms via the passage_lemmas index
    #     (#lemma_surface_forms) — λέγω becomes {λεγει, ειπε, εἰπειν, …} — and
    #     each folded form is a NEAR phrase. This is what makes proximity
    #     lemma-aware: εἶπε near κύριος counts as λέγω near κύριος. Homograph
    #     honesty: a folded surface form attested for this lemma may, in some
    #     passage, spell a DIFFERENT lemma's token; surface-expansion cannot
    #     tell them apart (true lemma-position search would need token offsets
    #     the FTS index does not carry). Documented, not silently precise.
    #
    # == Deliberately out of scope (said honestly)
    #
    #   - Cross-passage adjacency: the passage is the unit. Two terms in
    #     adjacent passages are NOT a proximity hit — NEAR lives inside one
    #     indexed document (one passage row), and that boundary is the honest
    #     unit of "nearness" here.
    #   - `--morph` with `--near`: morphology-narrowed proximity would need
    #     per-token offset+facet intersection the surface-expansion path cannot
    #     give; rejected at the surface with a clear message, a clean follow-up.
    #   - Collocation STATISTICS (frequency/association scores): a Phase 15
    #     concern, not painted out — this packet returns the hit passages, the
    #     raw material such a count would aggregate.
    #   - Prefix/boolean operators inside a proximity term: each side is folded
    #     and phrase-quoted, so `*`/AND/OR are taken literally. Operator-rich
    #     queries stay with plain `search`; proximity terms are words/phrases.
    class Proximity
      include CatalogJoin

      # FTS5 NEAR's own default window (max tokens between the terms).
      DEFAULT_WINDOW = 10

      # Safety valve on the lemma expansion: a paradigm is finite and folding
      # collapses accent variants (measured live: ὁ→25, εἰμί→99, λέγω→140
      # distinct folded forms), so this cap is never reached in practice for the
      # attested languages — it only guards FTS5's expression-tree limits
      # against a pathological lemma. Deterministic slice (surface_forms come
      # back index-ordered), so results stay stable.
      MAX_LEMMA_FORMS = 400

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      # Proximity search. The anchor is EITHER +query+ (text) XOR +lemma+
      # (expanded to attested surface forms); +near+ is the second term. Returns
      # up to +limit+ Search::Result values in bm25 rank order — the snippet
      # brackets BOTH matched terms because both are NEAR phrases. +window+ is
      # the max folded tokens between the two terms (see class note). +lang+ /
      # +license+ / +source+ filter catalog-side exactly as in Search.
      def run(near:, query: nil, lemma: nil, window: DEFAULT_WINDOW, lang: nil, license: nil, limit: 20,
              source: nil, loans: nil)
        unless [query, lemma].compact.one?
          raise ArgumentError, "give exactly one of query or lemma as the proximity anchor"
        end

        near_variants = folded_variants(near)
        anchor = lemma ? lemma_surface_forms(lemma) : folded_variants(query)
        return [] if near_variants.empty? || anchor.empty?

        match = near_match(anchor, near_variants, window.to_i)
        hits = fts_hits(match, inner_limit: limit * Search::INNER_LIMIT_FACTOR)
        assemble(hits, lang: lang, license: license, limit: limit, source: source, loans: loans)
      end

      private

      # query_forms minus the empty generic (a query of only marks folds away) —
      # the same guard Search uses, applied to a proximity term.
      def folded_variants(term)
        variants = Nabu::Normalize.query_forms(term.to_s)
        variants.first.strip.empty? ? [] : variants
      end

      # The lemma's attested distinct FOLDED surface forms, via the
      # passage_lemmas index. surface_forms is the pristine ", "-joined list per
      # passage; each form folds by ITS passage language (search_form), matching
      # how the FTS index folded it. Capped (see MAX_LEMMA_FORMS).
      #
      # BOTH TIERS, deliberately (P26-4, the P26-0 journaled decision): the
      # lemma here is a RETRIEVAL EXPANSION — the hits are real text matched
      # by the FTS NEAR, judged by the reader from their snippets, and no
      # per-hit annotation claim is rendered that a tier label could attach
      # to. Scoping to gold would gut the surface for Greek literature
      # (Diorisis is the only lemma layer most of it has); mirroring search
      # --lemma's inclusive stance, silver-attested inflections expand the
      # anchor too (test-pinned). The precision cost — a silver row can hang
      # a form on the wrong lemma — is bounded by the visible snippet.
      def lemma_surface_forms(lemma)
        variants = Nabu::Normalize.query_forms(lemma.to_s)
        return [] if variants.first.strip.empty?

        rows = @fulltext[Store::Indexer::LEMMA_TABLE]
               .where(lemma_folded: variants)
               .select(:surface_forms, :language)
               .distinct
               .all
        forms = rows.flat_map do |row|
          language = row.fetch(:language)
          row.fetch(:surface_forms).split(", ").map { |form| Nabu::Normalize.search_form(form, language: language) }
        end
        forms.reject(&:empty?).uniq.first(MAX_LEMMA_FORMS)
      end

      # OR of NEAR clauses over the cartesian product of the two sides' folded
      # variants (class note). Each side is phrase-quoted (folded forms can be
      # multi-token — the cuneiform fold — so a phrase, not a bare token) with
      # any embedded quote doubled per FTS5 phrase syntax.
      def near_match(anchor_variants, near_variants, window)
        anchor_variants.product(near_variants).map do |a, b|
          %(NEAR(#{phrase(a)} #{phrase(b)}, #{window}))
        end.join(" OR ")
      end

      def phrase(text)
        %("#{text.gsub('"', '""')}")
      end

      # The FTS MATCH — identical machinery to Search#fts_hits (same snippet and
      # bm25 fragments, same bound-parameter discipline: the built match is the
      # one raw-SQL fragment, carrying no user text except folded variants).
      def fts_hits(match, inner_limit:)
        @fulltext[Store::Indexer::TABLE]
          .where(Sequel.lit("passages_fts MATCH ?", match))
          .select(:passage_id, Sequel.lit(Search::SNIPPET_SQL).as(:snippet))
          .order(Sequel.lit(Search::RANK_SQL))
          .limit(inner_limit)
          .all
      end

      # Reassemble in FTS rank order after the catalog join drops filtered rows,
      # then trim to the page — the Search#run tail verbatim.
      def assemble(hits, lang:, license:, limit:, source: nil, loans: nil)
        return [] if hits.empty?

        ordered_ids = hits.map { |row| row.fetch(:passage_id) }
        snippets = hits.to_h { |row| [row.fetch(:passage_id), row.fetch(:snippet)] }
        rows = catalog_rows(ordered_ids, lang: lang, license: license, source: source, loans: loans)
               .to_h { |row| [row.fetch(:passage_id), row] }
        ordered_ids.filter_map { |id| rows[id] }
                   .first(limit)
                   .map { |row| build_result(row, snippets.fetch(row.fetch(:passage_id))) }
      end

      def build_result(row, snippet)
        Search::Result.new(
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
