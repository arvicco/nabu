# frozen_string_literal: true

require_relative "../languages"
require_relative "../normalize"
require_relative "../store/indexer"
require_relative "catalog_join"
require_relative "stored_snippet"
require_relative "term_frequency"

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
    # == --lang rides IN the MATCH when the index carries it (P42-3)
    #
    # The P40-r2 starvation genus, measured at P41 scale: a catalog-side
    # --lang WHERE thins the bounded inner window AFTER the MATCH, so a term
    # whose hits concentrate in other languages starves the page (empty at
    # any realistic --limit while matches exist). When the fts table carries
    # the P42-3 language column (feature-detected; the column appears at the
    # owner's next full rebuild), the plain path composes the filter into
    # the MATCH itself — `(<query>) AND language : ("0langgrc" OR …)`, the
    # Indexer's sentinel tokens over the code_variants equivalence set — and
    # drops the catalog-side language WHERE; visibility and license stay
    # catalog-side. In-MATCH, lang can no longer starve the window, so it
    # also stops counting toward the P35-6 incomplete-page hint. Two edges,
    # both deliberate: the token mint is case-insensitive where the catalog
    # WHERE was case-sensitive (a stored "san-Deva" is now reachable as
    # --lang san-deva — a friendlier equality, documented on the Indexer);
    # and --exact/--word keep the catalog-side filter (their paginated
    # verify scan already reads every candidate's catalog row, and their
    # --limit semantics never leaned on the inner window). Against a
    # pre-rebuild index the old catalog-side path runs byte-identically,
    # honesty hint included.
    #
    # Two-step id join (not ATTACH) and the exact-class license semantics are
    # documented on CatalogJoin, which owns that half.
    class Search
      include CatalogJoin

      # One search hit. `text` is the pristine passage text (for display);
      # `snippet` (P39-r3) is a window of that STORED text with the match in
      # [brackets], built by StoredSnippet — NOT the folded index form, which
      # renders glyphs the passage never held (学 as 學, だ as た). It marks
      # WHERE the match is AND how the source spelled it. `license_class` is the
      # effective class after override.
      Result = Data.define(:urn, :language, :text, :snippet, :document_title, :license_class)

      # FTS5 default relevance rank; lower (more negative) is a better match.
      # (The old SNIPPET_SQL fragment is gone: neither plain search nor proximity
      # draws its highlight from the folded index column any more — both rebuild
      # the snippet from the pristine stored text via StoredSnippet, P40-w.)
      RANK_SQL = "bm25(passages_fts)"

      # The ubiquitous-term guard (P42-2). MEASURED (P41 scale review): FTS5
      # `ORDER BY rank` computes bm25 for EVERY matching row before LIMIT, so
      # a term present in a large fraction of the corpus (الله across the
      # Arabic shelves) cost ~10s a page while rare terms cost 0.27s — the
      # curve is per-term document frequency. When the estimated candidate
      # set (TermFrequency#candidate_ceiling — sum over ORed fold variants of
      # the min df across each variant's ANDed tokens) exceeds this many
      # postings, the ranked ORDER BY is skipped and the page is served in
      # corpus (rowid) order, announced via #rank_note. TUNING RATIO: the
      # measured endpoints put bm25 at roughly 0.3µs/candidate (10s over the
      # ~31M-row candidate set of a ~50%-df term), so 1M candidates ≈ 0.3s —
      # the house per-command budget — and 1M ≈ 1.6% of the 62.8M corpus.
      # P42-5 (the orchestrator's live re-measure) should plot ranked latency
      # at df ≈ 0.5M/1M/2M and move this to where the curve crosses ~0.5s.
      # census: 62800000, 2026-07-23, live passages (P41 scale review; ranked latency 0.27s rare / ~10s at ~50% df)
      UBIQUITY_THRESHOLD = 1_000_000

      # The honest footer clause for a guard-skipped rank (the P35 rule:
      # a degraded page must say what it did). Shared verbatim by the CLI
      # footer and the MCP note field.
      RANK_SKIP_NOTE = "term too common to rank — corpus order"

      # The guard threshold, as a stubbable seam for surface-level tests
      # (crossing 1M postings in a fixture corpus is not reasonable).
      def self.ubiquity_threshold
        UBIQUITY_THRESHOLD
      end

      # Pull more FTS hits than the caller's limit so that catalog-side filtering
      # (license, timeline, facets, source — and language only against a
      # pre-P42-3 index; on the current shape --lang rides in the MATCH, class
      # note) can drop non-matching rows and still fill the page.
      # Exhaustion is ANNOUNCED (P35-6): a full window + active filters + a
      # short page sets incomplete_hint (CatalogJoin::INCOMPLETE_PAGE_HINT).
      # census: 24415015, 2026-07-20, live passages (settled full rebuild; 3.76M at tuning)
      INNER_LIMIT_FACTOR = 10

      # --exact honesty ceiling (P39-r3): the glyph-literal post-filter can
      # reject an unbounded run of fold candidates (a fold-heavy term with
      # millions of candidates and zero literal hits), so the paginated exact
      # scan stops after this many candidates. If the ceiling truncates the scan
      # before the stream is exhausted and the page is still short, the surface
      # ANNOUNCES it (the P35 truncation-honesty rule) — it never serves a
      # clean-looking short page over an abandoned scan. A generous default
      # (25 pages at the default limit); overridable per call as a test/tuning
      # seam. Non-exact search never paginates, so this does not touch it.
      # const: a bounded-work safety valve, not a corpus census — the honesty
      # hint fires whenever it truncates a real scan, so the value only trades
      # worst-case latency against how deep a zero-literal query is chased.
      SCAN_CEILING = 5000

      # --word (P40-w) has no honest meaning over the corpus's SPACELESS scripts:
      # Han ideographs and Japanese kana run without word delimiters, so there is
      # no boundary to bound a match on. A query carrying any such glyph is
      # REFUSED loudly rather than silently degraded — the user is pointed at
      # --exact, the glyph-literal escape hatch that IS defined there. (Hangul is
      # space-delimited in modern usage, so it is NOT spaceless — --word treats
      # it as any alphabetic script.)
      SPACELESS_WORD_SCRIPTS = /[\p{Han}\p{Hiragana}\p{Katakana}]/
      WORD_REFUSAL = "word boundaries are not defined for spaceless CJK text — " \
                     "use --exact for glyph-literal matching"

      # The refusal message for a --word +query+ that carries a spaceless-script
      # glyph, or nil when --word is honest for it. Shared by the CLI (a clean
      # Thor::Error before any DB work) and Search#run (the library guard).
      def self.word_refusal_for(query)
        query.to_s.match?(SPACELESS_WORD_SCRIPTS) ? WORD_REFUSAL : nil
      end

      # +term_frequency+ is the df probe seam (defaults to the real fts5vocab
      # reader over +fulltext+); tests inject a stub to pin the fail-open path.
      def initialize(catalog:, fulltext:, term_frequency: nil)
        @catalog = catalog
        @fulltext = fulltext
        @term_frequency = term_frequency || TermFrequency.new(fulltext: fulltext)
      end

      # nil, or RANK_SKIP_NOTE when the last #run served its page in corpus
      # order because the term was too common to rank (the P42-2 guard).
      # Reset on every run, like incomplete_hint.
      attr_reader :rank_note

      # Search +query+ and return up to +limit+ Result values in bm25 rank order.
      # +lang+ filters on passage language — inside the MATCH when the index
      # carries the P42-3 language column, catalog-side against an older index
      # (class note); +license+ on effective license class.
      # +from+/+to+/+place+ (P15-2) filter on the document's timeline
      # (signed historical years, place LIKE pattern); +facets+ (P17-2) on the
      # document's facet rows ({facet name => pattern} — search --type/
      # --province/--material); +source+ (P22-1) scopes to one source slug.
      # +urn+ restricts the match to one passage — a ranking-independent
      # "is this passage findable by this query" probe (the health golden
      # replay), not a pagination knob. +loans+ (P34-2) keeps only passages
      # whose stored annotations carry ≥1 loan token of that origin code
      # (passage-grain, read straight off annotations_json — no reparse).
      # +ubiquity_threshold+ (P42-2) is the guard's candidate-postings ceiling
      # (see UBIQUITY_THRESHOLD) — a seam for tests and for P42-5 tuning runs.
      def run(query, lang: nil, license: nil, limit: 20, urn: nil, from: nil, to: nil, place: nil,
              facets: nil, source: nil, sources: nil, loans: nil, exact: false, word: false,
              scan_ceiling: SCAN_CEILING, ubiquity_threshold: self.class.ubiquity_threshold)
        @incomplete_hint = nil
        @rank_note = nil
        raise Nabu::Error, WORD_REFUSAL if word && self.class.word_refusal_for(query)

        variants = Nabu::Normalize.query_forms(query.to_s)
        return [] if variants.first.strip.empty? # generic form first; extras never add characters

        filters = { lang: lang, license: license, from: from, to: to, place: place,
                    facets: facets, source: source, sources: sources, loans: loans }
        page = if exact || word
                 verified_page(variants, query, filters, limit: limit, urn: urn,
                                                         scan_ceiling: scan_ceiling, exact: exact, word: word)
               else
                 folded_page(variants, filters, limit: limit, urn: urn, ubiquity_threshold: ubiquity_threshold)
               end
        page.map { |row| build_result(row, query, exact: exact, word: word) }
      end

      # Term-less filtered browse (P42-6): a direct filtered page of the
      # catalog in CORPUS ORDER — passages.id ascending, the catalog's
      # insertion order, which mirrors the FTS index's rowid corpus order the
      # ubiquity guard (#rank?) falls back to, so a browse and a rank-skipped
      # search agree on what "corpus order" means. There is NO FTS MATCH and NO
      # ranking here: the page is drawn straight from the catalog under the
      # active filters. Two consequences, both deliberate: the page has no inner
      # window (it is not a bounded FTS window the catalog join then thins), so
      # the P35-6 incomplete-page hint CANNOT arm — page-fill is exact against
      # +limit+ — and there is no rank to skip, so #rank_note stays nil. The
      # snippet has no term to bracket: build_result with an empty query renders
      # a leading window of the stored text (StoredSnippet's no-term path).
      #
      # The LEGALITY of a term-less browse — that at least one content-narrowing
      # filter (date window, place, genre facet, or loans) must be present, and
      # that --lang/--license/--source/--axis do not qualify alone — is enforced
      # at the CLI seam, not here: this method lists whatever the filters select,
      # exactly as visible_passages composes them for ranked search.
      def browse(lang: nil, license: nil, limit: 20, from: nil, to: nil, place: nil,
                 facets: nil, source: nil, sources: nil, loans: nil)
        @incomplete_hint = nil
        @rank_note = nil
        rows = visible_passages(lang: lang, license: license, from: from, to: to, place: place,
                                facets: facets, source: source, sources: sources, loans: loans)
               .order(Sequel[:passages][:id])
               .select(*catalog_columns)
               .limit(limit)
               .all
        rows.map { |row| build_result(row, "", exact: false, word: false) }
      end

      # --exact verification: every whitespace token of the NFC-normalized
      # query must appear as a glyph-literal substring in the NFC-normalized
      # stored text. Glyph-exact, NOT display-exact — the query is NFC-folded
      # (so a decomposed input still matches composed storage) but nothing
      # else: no diacritic strip, no case fold, no reform fold. This is what
      # tells 弁 (the folded default, which also finds 辨/瓣/辯) apart from a
      # literal 弁.
      #
      # Both sides are NFC-normalized AT MATCH TIME (P40-w item 3): hbo/arc are
      # stored byte-verbatim in Masoretic mark order, which can diverge from NFC,
      # so a query typed in canonical order would miss the raw stored bytes if
      # only the query were folded. Normalizing the haystack too reconciles the
      # order without touching storage (or the snippet's stored-byte display).
      def exact_glyph_match?(text, query)
        haystack = Nabu::Normalize.nfc(text.to_s)
        Nabu::Normalize.nfc(query.to_s).split.all? { |token| haystack.include?(token) }
      end

      private

      # Non-exact page (the folded FTS path, unchanged semantics): one bounded
      # inner window, reassembled in FTS rank order after the catalog join drops
      # filtered rows, trimmed to the page. --limit already means "displayed
      # hits" here — only catalog-side filters thin the window, and that
      # thinning is announced by the P35-6 exhausted-window hint.
      # The P42-3 lang seam rides FIRST: when the index carries the language
      # column, --lang becomes a MATCH conjunct and leaves the catalog-side
      # filter set entirely — the window cannot starve on it, and
      # filters_active? honestly stops counting it toward the hint. On a
      # pre-rebuild index index_language_match is nil and the filters hash
      # passes through untouched: byte-identical to the old path.
      # The P42-2 guard rides here too: before ranking, the fts5vocab df probe
      # bounds the candidate set the bm25 ORDER BY would have to score. Above
      # +ubiquity_threshold+ postings the rank is skipped — same MATCH, same
      # filters, same snippets, corpus (rowid) order — and #rank_note arms the
      # honest footer clause. Below (or when the probe is unavailable — nil —
      # or under the ranking-independent urn probe), byte-identical to before.
      # (The probe reads the TEXT variants only; the sentinel language tokens
      # are invisible to it, so the ceiling stays a valid upper bound — a
      # lang-narrowed candidate set is only ever smaller.)
      def folded_page(variants, filters, limit:, urn:, ubiquity_threshold:)
        lang_match = index_language_match(filters[:lang])
        filters = filters.merge(lang: nil) if lang_match
        ranked = urn ? true : rank?(variants, ubiquity_threshold)
        @rank_note = ranked ? nil : RANK_SKIP_NOTE
        inner_limit = limit * INNER_LIMIT_FACTOR
        hits = fts_hits_with_literal_fallback(variants, inner_limit: inner_limit, urn: urn,
                                                        ranked: ranked, lang_match: lang_match)
        return [] if hits.empty?

        ordered_ids = hits.map { |row| row.fetch(:passage_id) }
        rows = catalog_rows(ordered_ids, **filters).to_h { |row| [row.fetch(:passage_id), row] }
        page = ordered_ids.filter_map { |id| rows[id] }.first(limit)
        note_page_completeness(
          window_exhausted: hits.size >= inner_limit,
          filters_active: filters_active?(filters), page_size: page.size, limit: limit
        )
        page
      end

      # The guard verdict: rank when the estimated candidate set is bounded
      # (≤ threshold) or unknowable (nil — no vocabulary, fail open). The
      # probe under-counts FTS power syntax to 0 by construction (quoted or
      # starred tokens miss the vocabulary), so those queries always rank,
      # exactly as before the guard.
      def rank?(variants, threshold)
        ceiling = @term_frequency.candidate_ceiling(variants)
        ceiling.nil? || ceiling <= threshold
      end

      # The composed `language :` MATCH conjunct for +lang+ — nil when no
      # --lang is active or the index predates the P42-3 column (the caller
      # then leaves the filter catalog-side, exactly the old path). Tokens
      # are the Indexer's sentinel mint over the code_variants equivalence
      # set (P40-r2: the typed code always a member), ORed inside one column
      # filter so any stored spelling of the language matches.
      def index_language_match(lang)
        return nil unless lang && index_language_column?

        tokens = Nabu::Languages.code_variants(lang).map { |code| Store::Indexer.language_token(code) }
        "language : (#{tokens.map { |token| %("#{token}") }.join(' OR ')})"
      end

      # Feature-detect, memoized per instance: does the live fts table carry
      # the P42-3 language column? A missing fts table reads as false — the
      # MATCH itself then raises exactly as it always has.
      def index_language_column?
        return @index_language_column if defined?(@index_language_column)

        @index_language_column = begin
          Store::Indexer.fts_language_column?(@fulltext)
        rescue Sequel::DatabaseError
          false
        end
      end

      # --exact / --word paginated page (P39-r3 Defect 1, extended P40-w). A
      # glyph-literal OR whole-word post-filter can reject an unbounded run of
      # fold candidates, so --limit CANNOT mean an internal candidate-pool size
      # (owner ruling 2026-07-22: "he will understand --limit as the number of
      # ultimate hits to display"). Instead we PAGINATE the candidate scan —
      # fetch candidate pages in bm25 order and keep verifying until +limit+
      # VERIFIED hits accumulate or the stream is exhausted. A pathological
      # fold-heavy zero-match query is bounded by +scan_ceiling+ candidates; a
      # ceiling that truncates the scan before exhaustion arms the honesty hint
      # (the page never poses as complete over an abandoned scan).
      def verified_page(variants, query, filters, limit:, urn:, scan_ceiling:, exact:, word:)
        page_size = limit * INNER_LIMIT_FACTOR
        verified = []
        offset = 0
        truncated = false
        loop do
          hits = fts_hits_with_literal_fallback(variants, inner_limit: page_size, offset: offset, urn: urn)
          collect_verified(hits, query, filters, into: verified, limit: limit, exact: exact, word: word)
          break if verified.size >= limit || hits.size < page_size # filled, or stream exhausted

          offset += page_size
          if offset >= scan_ceiling
            truncated = true
            break
          end
        end
        @incomplete_hint = scan_truncated_hint(scan_ceiling, exact: exact, word: word) if truncated
        verified.first(limit)
      end

      # Verify one candidate page in bm25 order, appending the catalog-visible
      # rows whose PRISTINE stored text passes the active post-filter (the
      # candidates-then-verify pattern, the fuzzy/define precedent) until the
      # page limit is reached.
      def collect_verified(hits, query, filters, into:, limit:, exact:, word:)
        return if hits.empty?

        ordered_ids = hits.map { |row| row.fetch(:passage_id) }
        rows = catalog_rows(ordered_ids, **filters).to_h { |row| [row.fetch(:passage_id), row] }
        ordered_ids.each do |id|
          row = rows[id]
          next unless row && verified_hit?(row, query, exact: exact, word: word)

          into << row
          break if into.size >= limit
        end
      end

      # A candidate passes when it carries the query glyph-literally (--exact),
      # as a whole word (--word), or both (the word filter enforces the glyph
      # literality on the exact path via StoredSnippet.word_match?(exact: true)).
      def verified_hit?(row, query, exact:, word:)
        if word
          Nabu::Query::StoredSnippet.word_match?(
            text: row.fetch(:text), language: row.fetch(:language),
            terms: word_terms(query, exact: exact), exact: exact
          )
        else
          exact_glyph_match?(row.fetch(:text), query)
        end
      end

      # The query's locator tokens for the word filter / snippet: the raw
      # whitespace tokens for --exact (glyph-literal, matching exact_glyph_match?),
      # else the folded snippet terms (phrase quotes dropped, trailing prefix-*
      # stripped).
      def word_terms(query, exact:)
        exact ? query.to_s.split : snippet_terms(query)
      end

      def filters_active?(filters)
        %i[lang license from to place source loans].any? { |key| filters[key] } ||
          (filters[:facets] || {}).any? || Array(filters[:sources]).any?
      end

      # The --exact/--word scan-ceiling truncation hint (P35 truncation honesty):
      # say what was hidden, naming the active filter. The old INCOMPLETE_PAGE_HINT
      # ("raise --limit to search deeper") is WRONG under the new --limit semantics
      # and is never emitted on this path — raising --limit widens the page, it
      # does not deepen the scan.
      def scan_truncated_hint(scan_ceiling, exact:, word:)
        kind = if exact && word then "whole-word glyph-literal"
               elsif exact then "glyph-literal"
               else "whole-word"
               end
        "scanned the first #{scan_ceiling} fold candidates for #{kind} matches — " \
          "later candidates were not checked, so more may exist"
      end

      # The user's text passes through as FTS5 syntax first (power queries —
      # AND/OR/NEAR/"phrases" — keep working verbatim). When FTS5 rejects it
      # (owner report 2026-07-18: `search --help` crashed with a raw fts5
      # backtrace; so does any hyphen-leading or unbalanced-quote query),
      # retry ONCE with every token literal-quoted (internal quotes doubled
      # — the escaped form cannot syntax-error), so hyphenated words and
      # option-looking strings just search. Non-fts errors re-raise.
      def fts_hits_with_literal_fallback(variants, inner_limit:, offset: 0, urn: nil, ranked: true,
                                         lang_match: nil)
        fts_hits(match_expression(variants), inner_limit: inner_limit, offset: offset, urn: urn,
                                             ranked: ranked, lang_match: lang_match)
      rescue Sequel::DatabaseError => e
        raise unless e.message.match?(/fts5|unterminated string|no such column/)

        literal = variants.map { |variant| literal_expression(variant) }
        fts_hits(match_expression(literal), inner_limit: inner_limit, offset: offset, urn: urn,
                                            ranked: ranked, lang_match: lang_match)
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
      # bm25() is an FTS auxiliary function with no Sequel dataset API, so it
      # rides along as a literal fragment with no user input. Only passage_ids
      # are pulled — the snippet is rebuilt from stored text (StoredSnippet),
      # never from the folded index column. +offset+ pages the candidate scan
      # for --exact (bm25 order is stable, so OFFSET paging is deterministic).
      # +ranked: false+ (the P42-2 guard) keeps the identical MATCH but orders
      # by rowid — the index's insertion order, which the Indexer streams in
      # catalog (document/sequence) order — so no bm25 is computed at all.
      # +lang_match+ (P42-3) is the pre-built `language :` conjunct (or nil);
      # AND-composed around the whole user expression — the user's own syntax
      # stays intact inside its parentheses, on the literal-fallback retry too.
      def fts_hits(match, inner_limit:, offset: 0, urn: nil, ranked: true, lang_match: nil)
        match = "(#{match}) AND #{lang_match}" if lang_match
        dataset = @fulltext[Store::Indexer::TABLE]
                  .where(Sequel.lit("passages_fts MATCH ?", match))
        dataset = dataset.where(urn: urn) if urn # urn rides UNINDEXED in the index row
        dataset
          .select(:passage_id)
          .order(ranked ? Sequel.lit(RANK_SQL) : :rowid)
          .limit(inner_limit)
          .offset(offset)
          .all
      end

      # A hit's snippet is a window of its STORED text (StoredSnippet), never the
      # folded index form. The query's tokens locate the match — its whitespace
      # tokens for --exact (matching exact_glyph_match?), else the FTS terms with
      # phrase quotes dropped and a trailing prefix-* stripped.
      def build_result(row, query, exact:, word:)
        terms = word_terms(query, exact: exact)
        Result.new(
          urn: row.fetch(:urn),
          language: row.fetch(:language),
          text: row.fetch(:text),
          snippet: Nabu::Query::StoredSnippet.build(
            text: row.fetch(:text), language: row.fetch(:language), terms: terms, exact: exact, word: word
          ),
          document_title: row.fetch(:document_title),
          license_class: row.fetch(:license_class)
        )
      end

      # The query's locatable terms for a folded snippet: drop FTS phrase quotes,
      # split on whitespace, strip a trailing prefix-* from each token (the KWIC
      # precedent — the terms are folded per-hit inside StoredSnippet).
      def snippet_terms(query)
        query.to_s.tr('"', " ").split(/\s+/).filter_map do |token|
          stem = token.sub(/\*\z/, "")
          stem.empty? ? nil : stem
        end
      end
    end
  end
end
