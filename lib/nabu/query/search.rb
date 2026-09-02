# frozen_string_literal: true

require_relative "../lects"
require_relative "../languages"
require_relative "../normalize"
require_relative "../store/indexer"
require_relative "../tibetan_words"
require_relative "catalog_join"
require_relative "lect_filter"
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
    # extra_L(generic(query)) for a query in L's script — the query folds,
    # on that variant, exactly the way the document was folded. And it
    # cannot over-fold: variants are ORed, so the generic variant still
    # matches languages with no extra rule (a Gothic "jah" stays findable
    # even though the lat variant reads "iah") — and, since P79-1, a rule
    # only touches queries whose dominant script it declares
    # (Normalize::QUERY_FOLD_SCRIPTS: the gml α/β delete no longer folds a
    # Greek αγαπη to γπη; conventions.md §9). P81-2 extends the discipline
    # to script neutralizations (Normalize::QUERY_NEUTRALIZATION_SCRIPTS:
    # the Slavonic Latin-diplomatic ou→u arm no longer folds a Portuguese
    # houlá to hula) — and an active --lang is passed through to
    # Normalize.query_forms as the asserted language, so `search oubi
    # --lang chu` still reaches damaskini's indexed "ubi" skeleton: the
    # caller named the language, its full pipeline joins the union.
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
    # == --source/--axis ride the same lane (P81-3)
    #
    # The same genus, found live 2026-08-20: `search 王 --source sillok`
    # returned empty because the global top window filled with cbeta/kanripo
    # rows the catalog-side source filter then rejected. When the fts table
    # carries the P81-3 source column, --source becomes a
    # `source : ("0srcsillok")` MATCH conjunct and --axis an OR of its
    # member slugs' tokens (an axis is a registry tag over sources, expanded
    # CLI-side — it deliberately has no index column of its own), both
    # leaving the catalog-side filter set exactly as --lang did. Same
    # --exact/--word carve-out, same pre-rebuild fallback.
    #
    # Two-step id join (not ATTACH) and the exact-class license semantics are
    # documented on CatalogJoin, which owns that half.
    class Search
      include CatalogJoin
      include LectFilter

      # One search hit. `text` is the pristine passage text (for display);
      # `snippet` (P39-r3) is a window of that STORED text with the match in
      # [brackets], built by StoredSnippet — NOT the folded index form, which
      # renders glyphs the passage never held (学 as 學, だ as た). It marks
      # WHERE the match is AND how the source spelled it. `license_class` is the
      # effective class after override.
      # +credit+ (P43-2): the source's optional attribution line (nil on every
      # ordinary source), for the credit duty a hit's text render carries.
      Result = Data.define(:urn, :language, :text, :snippet, :document_title, :license_class, :credit) do
        def initialize(credit: nil, **) = super
      end

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
      # corpus (rowid) order, announced via #rank_note. CALIBRATED (P42-5,
      # post-rebuild live curve): ranked cost is NOT a pure function of df —
      # posting/docsize locality dominates. Terms whose matches cluster in
      # the early, well-cached rowid range (Greek/Latin: γαρ 220K→0.11s,
      # εν 254K→0.48s, δε 457K→0.68s, και 739K→0.88s) ranked ~1.5µs/doc,
      # while terms scattered across the 33M-row openiti tail measured
      # 8–14µs/doc (اربع 154K→1.19s, اخذ 271K→2.28s, الملك 414K→5.53s,
      # يوم 835K→7.24s, الله 6.8M→11.4s). The worst class crosses ~0.5s
      # near df ≈ 100K, so the ceiling sits there: worst unguarded rank
      # ≈ 1.4s, and everything newly guarded is function-word-frequency
      # territory where bm25 ordering is noise. The old 1M ceiling was set
      # from the well-clustered ratio and let the Arabic 0.4–1M band stall
      # at 5–7s.
      # census: 68408109, 2026-08-04, live passages (P42-5 calibration curve, this
      # comment; +9% since the 62.8M calibration — a timing-curve claim, unmoved)
      UBIQUITY_THRESHOLD = 100_000

      # The honest footer clause for a guard-skipped rank (the P35 rule:
      # a degraded page must say what it did). Shared verbatim by the CLI
      # footer and the MCP note field. P42-r3: the skipped-rank page is a
      # corpus-wide SAMPLE, not the head of the posting list — the owner's
      # gate review showed the corpus-order page collapsing onto the first
      # matching document in id space (twenty الله hits, all Abu Talib's
      # dīwān), the same degenerate page for every guarded term.
      RANK_SKIP_NOTE = "term too common to rank — corpus-wide sample"

      # How many probe draws a sampled page may spend per needed hit before
      # settling for what it has (anchors that collide on the same posting
      # dedupe away — common when a term's postings cluster in one shelf's
      # rowid range and every anchor before the cluster resolves to its first
      # posting). The same bounded-retry idea as Random::PROBE_ATTEMPTS; a
      # miss just means a shorter sample pool, never an error.
      # const: bounded-retry budget per sampled hit (engine knob, not a corpus census)
      SAMPLE_ATTEMPTS = 4

      # The --scan mode's page label (P75 C-10) — rides the rank_note slot:
      # the page IS unranked, and the label must say which order replaced it.
      SCAN_MODE_NOTE = "corpus-order scan of the filtered set (--scan)"

      # const: postings pulled per keyset seek in --scan (engine knob)
      SCAN_MODE_PAGE = 10_000
      # const: postings walked before --scan gives up and announces the
      # truncation (engine knob — each page is one cheap rowid-seek MATCH
      # plus one bounded catalog probe, so the worst case stays interactive)
      SCAN_MODE_CEILING = 200_000

      # The guard threshold, as a stubbable seam for surface-level tests
      # (crossing 1M postings in a fixture corpus is not reasonable).
      def self.ubiquity_threshold
        UBIQUITY_THRESHOLD
      end

      # Pull more FTS hits than the caller's limit so that catalog-side filtering
      # (license, timeline, facets — and language/source/axis only against a
      # pre-P42-3/P81-3 index; on the current shape those ride in the MATCH,
      # class note) can drop non-matching rows and still fill the page.
      # Exhaustion is ANNOUNCED (P35-6): a full window + active filters + a
      # short page sets incomplete_hint (CatalogJoin::INCOMPLETE_PAGE_HINT).
      # census: 68408109, 2026-08-04, live passages (P57 full rebuild; 3.76M at tuning,
      # re-affirmed at 24.4M and 68.4M — exhaustion stays ANNOUNCED, class note)
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

      # --words (P54-4): the Tibetan word-grain post-filter. Tibetan sits in
      # the --word gap deliberately left at P40-w: the script IS delimited —
      # but at SYLLABLE grain (tsheg), one level below the word, so a
      # multi-syllable query also matches an ACCIDENTAL syllable run crossing
      # a word boundary. words: true keeps only hits where some occurrence of
      # the query in the stored text aligns with word boundaries per the
      # nabu-data xct/segmentation vocabulary (Nabu::TibetanWords). Only
      # meaningful for Tibetan-script queries; anything else DEGRADES to
      # plain search plus one honest note — never an error (the seam may
      # simply not be synced on this box).
      TIBETAN_SCRIPT = /\p{Tibetan}/
      WORDS_MODULE_NOTE = "word-grain: nabu-data module not synced — run: nabu sync nabu-data"
      WORDS_SCRIPT_NOTE = "word-grain: only for Tibetan-script queries"

      # --lect (P57-4): a resolution-level filter over Nabu::Lects — every
      # (language, source) pair the catalog carries is resolved through
      # #resolve and kept when the result IS the given lect id, or a more
      # specific lect UNDER it (prefix semantics over the ":"/"/"/"@" axis
      # grammar — LectFilter#lect_matches_target?). Absent the module, the
      # flag is refused loudly (never a silent no-filter or a stored-code
      # guess). The machinery lives in Query::LectFilter since P59-3
      # (parallels shares it); the constant stays addressable here.
      LECT_MODULE_MISSING = LectFilter::LECT_MODULE_MISSING

      # +term_frequency+ is the df probe seam (defaults to the real fts5vocab
      # reader over +fulltext+); tests inject a stub to pin the fail-open path.
      # +rng+ (P42-r3) drives the sampled guarded page — injectable for
      # deterministic tests, exactly the Random sampler's seam.
      # +tibetan_words+ (P54-4) is the word-grain segmentation seam: :auto
      # feature-detects the nabu-data dataset LAZILY on the first words: true
      # run (the define.rb form_lemma/verb_lemma contract — absent tree,
      # byte-identical behavior); tests inject a fixture seam or nil.
      # +lects+ (P57-4) is the `--lect` resolution seam, same :auto/loaded/nil
      # contract as +tibetan_words+ — feature-detected lazily on the first
      # lect: filter, never touched otherwise.
      # +places+ (P75 C-1) is the nabu-places registry read seam
      # (Nabu::Places or nil) feeding --place name resolution; the place
      # index and crosswalk lanes read the catalog and need no seam.
      def initialize(catalog:, fulltext:, term_frequency: nil, rng: ::Random.new, tibetan_words: :auto,
                     lects: :auto, places: nil)
        @catalog = catalog
        @fulltext = fulltext
        @term_frequency = term_frequency || TermFrequency.new(fulltext: fulltext)
        @rng = rng
        @tibetan_words = tibetan_words
        @lects = lects
        @places = places
      end

      # nil, or RANK_SKIP_NOTE when the last #run served its page in corpus
      # order because the term was too common to rank (the P42-2 guard).
      # Reset on every run, like incomplete_hint.
      attr_reader :rank_note

      # nil, or the meter facet's honesty line after a #run/#browse with an
      # active --meter/--meter-pattern (P45-5): the filter NAMES ITS SOURCE
      # when it worked ("meter: pedecerto/hypotactic enrichments"), explains
      # an EMPTY LAYER (no meter rows in this catalog) rather than serving a
      # silent zero, and on a code that matches nothing corpus-wide lists the
      # meters that ARE scannable. Reset on every run, like incomplete_hint.
      attr_reader :meter_note

      # How many distinct meter values the unknown-code miss note lists
      # before eliding (the live layer holds ~5 distinct values).
      # const: a render cap on the miss note's value list (elision is marked
      # with … whenever it truncates), not a corpus census
      METER_NOTE_VALUES = 12

      # nil, or the word-grain degrade note (P54-4) after a words: true #run
      # that could not filter — WORDS_SCRIPT_NOTE for a non-Tibetan query,
      # WORDS_MODULE_NOTE when the nabu-data seam is absent. The page served
      # alongside is plain search, honestly labelled. Reset on every run.
      attr_reader :words_note

      # nil, or the --place lane note (P75 C-1) after a run/browse with an
      # active place filter: the identity refs a mint or resolved name
      # matched on (crosswalk-expanded), or the honest name-LIKE fallback
      # for a name with no registered identity. A LIKE pattern (%/_) is the
      # user asking for the historical lane by name — silent. Reset every
      # run, like meter_note.
      attr_reader :place_note

      # const: a render cap on the place note's identity list (truncation
      # announced, never silent); a cap on the LABEL only, the filter
      # itself always matches every identity — not a corpus census
      PLACE_NOTE_IDS = 6

      # true when the last #run actually APPLIED the word-grain post-filter
      # (words: true, Tibetan query, seam present) — the surfaces' present-only
      # marker (MCP word_grain key). nil otherwise; reset on every run.
      attr_reader :word_grain

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
      # +meter+/+meter_pattern+ (P45-5) keep only passages carrying a meter
      # enrichment whose code / foot pattern matches (case-insensitive; the
      # CatalogJoin note argues the read-time cost). #meter_note carries the
      # facet's honesty line afterwards.
      # +words+ (P54-4) post-filters the assembled page to Tibetan word-grain
      # matches (class note at WORDS_MODULE_NOTE); filtered-out hits are simply
      # absent, degrade cases serve the plain page plus #words_note.
      # +lect+ (P57-4) keeps only passages whose (language, source) resolves
      # to this lect id or a more specific one under it (class note at
      # LECT_MODULE_MISSING); raises Nabu::Error when Lects is unavailable.
      # +script+ (P75 C-2) keeps only documents whose resolved lect id
      # claims the held-surface script (~code) or whose artifact-script
      # axis claims the artifact's system (CatalogJoin#script_exists).
      # +within+ (P75 C-9, №R-5): [lat, lon, km] — only documents whose
      # coordinates-lane find-location falls in the radius
      # (CatalogJoin#within_exists; coordinate-less documents fall out,
      # like undated ones under a date filter).
      def run(query, lang: nil, license: nil, limit: 20, urn: nil, from: nil, to: nil, place: nil,
              facets: nil, source: nil, sources: nil, loans: nil, meter: nil, meter_pattern: nil,
              exact: false, word: false, words: false, lect: nil, script: nil, within: nil,
              scan_ceiling: SCAN_CEILING, ubiquity_threshold: self.class.ubiquity_threshold)
        @incomplete_hint = nil
        @rank_note = nil
        @meter_note = nil
        @words_note = nil
        @word_grain = nil
        @place_note = nil
        raise Nabu::Error, WORD_REFUSAL if word && self.class.word_refusal_for(query)

        variants = Nabu::Normalize.query_forms(query.to_s, language: lang)
        return [] if variants.first.strip.empty? # generic form first; extras never add characters

        filters = { lang: lang, license: license, from: from, to: to, place: place_resolution(place),
                    facets: facets, source: source, sources: sources, loans: loans,
                    meter: meter, meter_pattern: meter_pattern,
                    script: script_code(script), within: within_spec(within) }.merge(lect_filter(lect))
        page = if exact || word
                 verified_page(variants, query, filters, limit: limit, urn: urn,
                                                         scan_ceiling: scan_ceiling, exact: exact, word: word)
               else
                 folded_page(variants, filters, limit: limit, urn: urn, ubiquity_threshold: ubiquity_threshold)
               end
        page = word_grain_page(page, query) if words
        # P75 C-10: a guard-sampled page thinned below its limit by active
        # CATALOG-SIDE filters is the starvation genus — the note teaches
        # the mode built for that question instead of serving degenerate
        # pages silently. A lang (P42-3) or source/axis (P81-3) that rode
        # IN the MATCH filtered the draw itself, so it never thins and
        # never fires this.
        catalog_side = catalog_side_filters(filters)
        if @rank_note && page.size < limit && filters_active?(catalog_side)
          @rank_note = "#{@rank_note} — filters thinned the sampled page; " \
                       "--scan walks the filtered set deterministically"
        end
        note_meter(meter, meter_pattern, empty: page.empty?)
        page.map { |row| build_result(row, query, exact: exact, word: word) }
      end

      # Term-less filtered browse (P42-6): a direct filtered page of the
      # catalog in CORPUS ORDER — passages.id ascending, the catalog's
      # insertion order. (A rank-skipped SEARCH page is, since P42-r3, a
      # corpus-wide sample presented in this same order — browse stays a
      # deterministic walk because its filters, not a term, bound the page.) There is NO FTS MATCH and NO
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
                 facets: nil, source: nil, sources: nil, loans: nil, meter: nil, meter_pattern: nil,
                 lect: nil, script: nil, within: nil)
        @incomplete_hint = nil
        @rank_note = nil
        @meter_note = nil
        @place_note = nil
        rows = visible_passages(lang: lang, license: license, from: from, to: to,
                                place: place_resolution(place),
                                facets: facets, source: source, sources: sources, loans: loans,
                                meter: meter, meter_pattern: meter_pattern,
                                script: script_code(script), within: within_spec(within),
                                **lect_filter(lect))
               .order(Sequel[:passages][:id])
               .select(*catalog_columns)
               .limit(limit)
               .all
        note_meter(meter, meter_pattern, empty: rows.empty?)
        rows.map { |row| build_result(row, "", exact: false, word: false) }
      end

      # The filter-first mode (P75 C-10, owner-ruled: guard-sampled search
      # and filter-first search are TWO DIFFERENT MODES). #run answers
      # "where does this term rank corpus-wide?" — and under the ubiquity
      # guard its page is a corpus-wide SAMPLE that selective filters can
      # thin to nothing. #run_scan answers "which of THESE documents carry
      # the term?": it streams the term's postings in CORPUS ORDER (keyset
      # rowid seeks — the sampled_hits lesson: FTS5 honors rowid range
      # constraints without materializing the posting list) and intersects
      # each posting page with the catalog filters until the page fills.
      # Deterministic by contract — no rank, no sample, same MATCH
      # semantics as #run. Bounded by +scan_ceiling+ postings walked; the
      # truncation is announced via #incomplete_hint, never silent.
      def run_scan(query, lang: nil, license: nil, limit: 20, from: nil, to: nil, place: nil,
                   facets: nil, source: nil, sources: nil, loans: nil, meter: nil, meter_pattern: nil,
                   lect: nil, script: nil, within: nil,
                   scan_page: SCAN_MODE_PAGE, scan_ceiling: SCAN_MODE_CEILING)
        @incomplete_hint = nil
        @meter_note = nil
        @words_note = nil
        @word_grain = nil
        @place_note = nil
        @rank_note = SCAN_MODE_NOTE
        variants = Nabu::Normalize.query_forms(query.to_s, language: lang)
        return [] if variants.first.strip.empty?

        filters = { lang: lang, license: license, from: from, to: to, place: place_resolution(place),
                    facets: facets, source: source, sources: sources, loans: loans,
                    meter: meter, meter_pattern: meter_pattern, script: script_code(script),
                    within: within_spec(within) }.merge(lect_filter(lect))
        index_match = index_match_filter(filters)
        filters = catalog_side_filters(filters)

        page = scan_walk(variants, filters, limit: limit, scan_page: scan_page,
                                            scan_ceiling: scan_ceiling, index_match: index_match)
        note_meter(meter, meter_pattern, empty: page.empty?)
        page.map { |row| build_result(row, query, exact: false, word: false) }
      end

      # Search-by-sign (P75 C-4, the inverse of `nabu signs`): the page
      # matches ANY of +values+ — a sign's OSL reading values, each folded
      # through the standard query variants and ORed in the MATCH (exactly
      # the fold-union machinery multi-variant queries already ride).
      # Document-grain filters compose as in #run; the exact/word/words
      # modifiers and the meter facet do not (value-token grain — the CLI
      # refuses the composition). The snippet brackets the value that
      # actually matched each hit. The ubiquity guard applies unchanged: a
      # sign with a function-word-frequency value (𒀀's "a") serves the
      # honest corpus-order sample, rank_note armed.
      def run_sign(values, lang: nil, license: nil, limit: 20, from: nil, to: nil, place: nil,
                   facets: nil, source: nil, sources: nil, loans: nil, lect: nil, script: nil,
                   ubiquity_threshold: self.class.ubiquity_threshold)
        @incomplete_hint = nil
        @rank_note = nil
        @meter_note = nil
        @words_note = nil
        @word_grain = nil
        @place_note = nil
        variants = values.flat_map { |value| Nabu::Normalize.query_forms(value.to_s) }
                         .reject { |form| form.strip.empty? }.uniq
        return [] if variants.empty?

        filters = { lang: lang, license: license, from: from, to: to, place: place_resolution(place),
                    facets: facets, source: source, sources: sources, loans: loans,
                    script: script_code(script) }.merge(lect_filter(lect))
        page = folded_page(variants, filters, limit: limit, urn: nil, ubiquity_threshold: ubiquity_threshold)
        page.map { |row| build_result(row, matched_value(row, values), exact: false, word: false) }
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

      # Resolve a raw --place term once per run (P75 C-1) — identity claims
      # + name pattern per the PlaceFilter lanes; nil passes through. Every
      # surface over this class (CLI, MCP) inherits identity-awareness here.
      def place_resolution(place)
        return place unless place.is_a?(String)

        resolution = PlaceFilter.resolve(place, catalog: @catalog, places: @places)
        @place_note = place_note_for(resolution)
        resolution
      end

      # Validate a --within spec (P75 C-9): [lat, lon, km], WGS84 ranges,
      # positive radius — one enforcement point for every surface.
      def within_spec(within)
        return nil if within.nil?

        lat, lon, km = within
        unless within.size == 3 && [lat, lon, km].all?(Numeric) &&
               lat.abs <= 90 && lon.abs <= 180 && km.positive?
          raise Nabu::Error,
                "within: give LAT,LON,KM — latitude −90..90, longitude −180..180, a positive " \
                "radius in km (got #{within.inspect})"
        end
        [lat.to_f, lon.to_f, km.to_f]
      end

      # Fold and validate a --script tag (P75 C-2): the registry spelling
      # is a lowercase 4-letter ISO 15924-style tag (latn, xsux, egyd) —
      # anything else is refused with the expected shape, one enforcement
      # point for every surface (CLI and MCP both arrive here).
      def script_code(script)
        return nil if script.nil?

        code = script.to_s.strip.downcase
        unless code.match?(/\A[a-z]{4}\z/)
          raise Nabu::Error,
                "script: give a 4-letter ISO 15924-style tag as the registry spells it " \
                "(latn, xsux, egyd) — got #{script.inspect}"
        end
        code
      end

      # The lane note for +resolution+ (attr note above): nil for an
      # explicit LIKE pattern, the identity list (capped, truncation
      # announced) when identities matched, the honest fallback line
      # otherwise.
      def place_note_for(resolution)
        return nil if resolution.pattern&.match?(/[%_]/)

        return "place: \"#{resolution.term}\" has no registered identity — name-LIKE lane" unless resolution.identity?

        shown = resolution.identities.first(PLACE_NOTE_IDS).map { |ns, id| "#{ns}:#{id}" }
        extra = resolution.identities.size - shown.size
        ids = shown.join(" = ")
        ids += " … and #{extra} more" if extra.positive?
        if resolution.pattern
          "place: \"#{resolution.term}\" → #{ids} (identity refs + name match)"
        else
          "place: #{ids} (identity refs)"
        end
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
      # filters, same snippets — and #rank_note arms the honest footer clause.
      # Below (or when the probe is unavailable — nil — or under the
      # ranking-independent urn probe), byte-identical to before.
      # (The probe reads the TEXT variants only; the sentinel language and
      # source tokens are invisible to it, so the ceiling stays a valid
      # upper bound — a lang/source-narrowed candidate set is only ever
      # smaller.)
      # P42-r3: the skipped-rank window is a corpus-wide SAMPLE (rowid-anchor
      # probes over the posting list), not the head of the list — the head
      # window collapsed onto the first matching document in id space and
      # served the identical degenerate page for every guarded term. The
      # sampled hits present in passage-id order, so the page still reads as
      # corpus order; it is just drawn from the whole corpus, announced by
      # the note. A fixture-scale corpus samples exhaustively (the attempt
      # budget dwarfs the posting list), where sample == the full match set.
      def folded_page(variants, filters, limit:, urn:, ubiquity_threshold:)
        index_match = index_match_filter(filters)
        filters = catalog_side_filters(filters)
        ranked = urn ? true : rank?(variants, ubiquity_threshold)
        @rank_note = ranked ? nil : RANK_SKIP_NOTE
        inner_limit = limit * INNER_LIMIT_FACTOR
        hits = if ranked
                 fts_hits_with_literal_fallback(variants, inner_limit: inner_limit, urn: urn,
                                                          ranked: true, index_match: index_match)
               else
                 sampled_hits_with_literal_fallback(variants, inner_limit: inner_limit,
                                                              index_match: index_match)
               end
        return [] if hits.empty?

        ordered_ids = hits.map { |row| row.fetch(:passage_id) }
        rows = catalog_rows(ordered_ids, **filters).to_h { |row| [row.fetch(:passage_id), row] }
        page = ordered_ids.filter_map { |id| rows[id] }.first(limit)
        # A sampled page (guard fired) is cut in DRAW order for unbiasedness,
        # then sorted for presentation — id order reads as corpus order.
        page = page.sort_by { |row| row.fetch(:passage_id) } unless ranked
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

      # The composed `source :` MATCH conjunct(s) for --source/--axis
      # (P81-3) — nil when neither is active or the index predates the
      # source column (catalog-side path, exactly the old behavior).
      # +source+ (one slug) and +sources+ (an axis's member slugs, expanded
      # CLI-side — the axis itself is deliberately NOT in the index: an axis
      # is a registry tag over sources, so it compiles to an OR of source
      # tokens) AND-compose when both are given, exactly as the catalog
      # WHEREs did. An empty +sources+ stays "no filter", never a silent
      # match-nothing (the CatalogJoin contract).
      def index_source_match(source, sources)
        clauses = []
        clauses << source_column_filter([source]) if source
        slugs = Array(sources)
        clauses << source_column_filter(slugs) unless slugs.empty?
        return nil if clauses.empty? || !index_source_column?

        clauses.join(" AND ")
      end

      # One `source :` column filter over +slugs+ — the Indexer's sentinel
      # mint, ORed inside the column so any member slug matches.
      def source_column_filter(slugs)
        tokens = slugs.map { |slug| Store::Indexer.source_token(slug) }
        "source : (#{tokens.map { |token| %("#{token}") }.join(' OR ')})"
      end

      # The AND-composition of every index-side filter conjunct for
      # +filters+ (language + source today), or nil when none is active —
      # what the MATCH composers downstream take alongside the query.
      def index_match_filter(filters)
        conjuncts = [index_language_match(filters[:lang]),
                     index_source_match(filters[:source], filters[:sources])].compact
        conjuncts.empty? ? nil : conjuncts.join(" AND ")
      end

      # +filters+ with every conjunct that rides in the MATCH removed — the
      # catalog-side remainder (what thins windows and arms honesty hints).
      def catalog_side_filters(filters)
        filters = filters.merge(lang: nil) if index_language_match(filters[:lang])
        filters = filters.merge(source: nil, sources: nil) if index_source_match(filters[:source], filters[:sources])
        filters
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

      # Same memoized feature detect for the P81-3 source column.
      def index_source_column?
        return @index_source_column if defined?(@index_source_column)

        @index_source_column = begin
          Store::Indexer.fts_source_column?(@fulltext)
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
        %i[lang license from to place source loans meter meter_pattern lect_pairs
           script within].any? { |key| filters[key] } ||
          (filters[:facets] || {}).any? || Array(filters[:sources]).any?
      end

      # The meter facet's honesty line (the attr_reader note): set only when
      # the filter is active. Probes are bounded by the meter LAYER (10⁵
      # rows, ~40ms live — the CatalogJoin cost note), and the two miss
      # probes run only on an empty page.
      def note_meter(meter, pattern, empty:)
        return unless meter || pattern

        models = @catalog[:enrichments].where(kind: "meter").distinct.select_map(:model).compact.sort
        @meter_note =
          if models.empty?
            "meter filter active, but this catalog holds no meter enrichments — " \
              "the pedecerto/hypotactic syncs produce them"
          elsif empty && meter_enrichments(meter, pattern).empty?
            "#{meter ? "meter '#{meter}'" : "meter pattern '#{pattern}'"} matches no meter " \
              "enrichment — known meters: #{known_meters.join(', ')}"
          else
            "meter: #{models.join('/')} enrichments"
          end
      end

      # The distinct meter values actually held, for the miss note — capped
      # for render honesty, elision marked.
      def known_meters
        values = @catalog[:enrichments].where(kind: "meter")
                                       .distinct.select_map(Sequel.function(:json_extract, :payload_json, "$.meter"))
                                       .compact.reject(&:empty?).sort
        values.size > METER_NOTE_VALUES ? values.first(METER_NOTE_VALUES) + ["…"] : values
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
                                         index_match: nil)
        fts_hits(match_expression(variants), inner_limit: inner_limit, offset: offset, urn: urn,
                                             ranked: ranked, index_match: index_match)
      rescue Sequel::DatabaseError => e
        raise unless e.message.match?(/fts5|unterminated string|no such column/)

        literal = variants.map { |variant| literal_expression(variant) }
        fts_hits(match_expression(literal), inner_limit: inner_limit, offset: offset, urn: urn,
                                            ranked: ranked, index_match: index_match)
      end

      # The --scan posting walk (P75 C-10): pages of (passage_id, rowid) in
      # rowid = corpus order, each intersected with the catalog filters;
      # keyset-paged on the last rowid so no posting is ever re-walked.
      def scan_walk(variants, filters, limit:, scan_page:, scan_ceiling:, index_match:)
        page = []
        after = 0
        walked = 0
        loop do
          hits = scan_posting_page(variants, after_rowid: after, page_size: scan_page,
                                             index_match: index_match)
          break if hits.empty?

          collect_scan_survivors(hits, filters, into: page, limit: limit)
          walked += hits.size
          after = hits.last.fetch(:scan_rowid)
          break if page.size >= limit || hits.size < scan_page

          next unless walked >= scan_ceiling

          @incomplete_hint = "--scan walked the first #{walked} matches in corpus order — " \
                             "deeper matches were not checked (narrow the filters or the term)"
          break
        end
        page.first(limit)
      end

      # Which of one posting page's passages survive the catalog filters,
      # appended in corpus order (the collect_verified shape, with the
      # filters themselves as the verification).
      def collect_scan_survivors(hits, filters, into:, limit:)
        ordered_ids = hits.map { |row| row.fetch(:passage_id) }
        rows = catalog_rows(ordered_ids, **filters).to_h { |row| [row.fetch(:passage_id), row] }
        ordered_ids.each do |id|
          row = rows[id] or next
          into << row
          break if into.size >= limit
        end
      end

      def scan_posting_page(variants, after_rowid:, page_size:, index_match:)
        scan_hits(match_expression(variants), after_rowid: after_rowid, page_size: page_size,
                                              index_match: index_match)
      rescue Sequel::DatabaseError => e
        raise unless e.message.match?(/fts5|unterminated string|no such column/)

        literal = variants.map { |variant| literal_expression(variant) }
        scan_hits(match_expression(literal), after_rowid: after_rowid, page_size: page_size,
                                             index_match: index_match)
      end

      def scan_hits(match, after_rowid:, page_size:, index_match:)
        match = "(#{match}) AND #{index_match}" if index_match
        @fulltext[Store::Indexer::TABLE]
          .where(Sequel.lit("passages_fts MATCH ?", match))
          .where(Sequel.lit("rowid > ?", after_rowid))
          .select(Store::Indexer.fts_passage_id_expression(@fulltext),
                  Sequel.lit("rowid").as(:scan_rowid))
          .order(Sequel.lit("rowid"))
          .limit(page_size)
          .all
      end

      # The sampled guarded window (P42-r3), with the same literal-fallback
      # symmetry as the ranked path.
      def sampled_hits_with_literal_fallback(variants, inner_limit:, index_match:)
        sampled_hits(match_expression(variants), inner_limit: inner_limit, index_match: index_match)
      rescue Sequel::DatabaseError => e
        raise unless e.message.match?(/fts5|unterminated string|no such column/)

        literal = variants.map { |variant| literal_expression(variant) }
        sampled_hits(match_expression(literal), inner_limit: inner_limit, index_match: index_match)
      end

      # Corpus-spread sample of a guarded term's postings — the P41-r2
      # id-probe pattern applied to the FTS posting walk. FTS5 honors rowid
      # range constraints on a MATCH without materializing the posting list,
      # so `MATCH term AND rowid >= anchor LIMIT 1` is one posting seek
      # (measured 2026-07-23: 20 draws in 7ms against the الله list, vs 11.4s
      # to bm25-rank it). Anchors are uniform over the index's rowid space,
      # so a posting is drawn with probability proportional to the gap
      # BEFORE it — the same near-uniform honesty as Random over bulk-loaded
      # shelves — and anchors past the last posting simply miss (bounded by
      # SAMPLE_ATTEMPTS). The final page presents in passage-id order: a stable
      # corpus-order READING of an unbiased corpus-wide draw.
      def sampled_hits(match, inner_limit:, index_match:)
        match = "(#{match}) AND #{index_match}" if index_match
        max_rowid = @fulltext[Store::Indexer::TABLE].max(Sequel.lit("rowid"))
        return [] unless max_rowid

        seen = {}
        (inner_limit * SAMPLE_ATTEMPTS).times do
          break if seen.size >= inner_limit

          row = @fulltext[Store::Indexer::TABLE]
                .where(Sequel.lit("passages_fts MATCH ?", match))
                .where(Sequel.lit("rowid >= ?", @rng.rand(1..max_rowid)))
                .select(Store::Indexer.fts_passage_id_expression(@fulltext))
                .order(Sequel.lit("rowid")).limit(1).first
          seen[row[:passage_id]] ||= row if row
        end
        # DRAW order, not id order: the page assembly takes the first +limit+
        # survivors of the catalog filters, and only an order-free draw keeps
        # that cut unbiased — sorting here would hand the page the lowest-id
        # fraction of the sample, the head-bias this sampler exists to kill.
        # The caller sorts the FINAL page for presentation.
        seen.values
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
      # +index_match+ (P42-3 `language :`, P81-3 `source :`) is the pre-built
      # index-side filter conjunct (or nil); AND-composed around the whole
      # user expression — the user's own syntax stays intact inside its
      # parentheses, on the literal-fallback retry too.
      def fts_hits(match, inner_limit:, offset: 0, urn: nil, ranked: true, index_match: nil)
        match = "(#{match}) AND #{index_match}" if index_match
        dataset = @fulltext[Store::Indexer::TABLE]
                  .where(Sequel.lit("passages_fts MATCH ?", match))
        dataset = fts_urn_scope(dataset, urn) if urn
        dataset
          .select(Store::Indexer.fts_passage_id_expression(@fulltext))
          .order(ranked ? Sequel.lit(RANK_SQL) : :rowid)
          .limit(inner_limit)
          .offset(offset)
          .all
      end

      # The --urn scope against the index (P93-1): the contentless shape
      # stores no urn column, so the urn(s) resolve to catalog passage ids
      # and scope by rowid; a legacy contentful file keeps its stored-column
      # equality. Either way the semantics stay exact-urn.
      def fts_urn_scope(dataset, urn)
        if Store::Indexer.fts_contentless?(@fulltext)
          dataset.where(Sequel.lit("rowid") => @catalog[:passages].where(urn: urn).select_map(:id))
        else
          dataset.where(urn: urn)
        end
      end

      # A hit's snippet is a window of its STORED text (StoredSnippet), never the
      # folded index form. The query's tokens locate the match — its whitespace
      # tokens for --exact (matching exact_glyph_match?), else the FTS terms with
      # phrase quotes dropped and a trailing prefix-* stripped.
      # The value whose folded form the row's text actually carries (first
      # in OSL order) — the honest snippet bracket for #run_sign; falls
      # back to the first value when the match crossed a fold variant no
      # substring probe reproduces.
      def matched_value(row, values)
        language = row.fetch(:language)
        text = Nabu::Normalize.search_form(row.fetch(:text), language: language)
        values.find do |value|
          text.include?(Nabu::Normalize.search_form(value.to_s, language: language))
        end || values.first
      end

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
          license_class: row.fetch(:license_class),
          credit: row.fetch(:credit)
        )
      end

      # -- the Tibetan word-grain post-filter (P54-4) -------------------------
      # WHERE it hooks: the assembled page, after the folded/verified paths
      # and the catalog join, right before Results are built — one seam for
      # both paths, and the ONLY rows ever segmented are the page's own
      # (≤ limit, strictly inside the packet's window bound; the corpus is
      # never touched). A filtered page may therefore come back short of
      # +limit+ — the contract: filtered-out hits are simply absent.
      #
      # HOW a span is located: the same mechanism StoredSnippet uses to
      # bracket a match — fold the stored text with a char-index map
      # (Normalize.fold_with_map; for xct/bod/otb that is the EWTS transcode
      # the index itself was built from), find every occurrence of the
      # query's own search form (search_form under the hit's language — the
      # exact fold the FTS MATCH matched on), and map each span back onto
      # stored glyphs. NOT a raw-substring hunt: the fold is what actually
      # matched, and the map is exact. A hit survives when ANY occurrence
      # aligns; a hit whose tokens only matched scattered (non-adjacent AND
      # terms) has no contiguous span at all and is dropped — word-grain
      # implies the query stands somewhere as a contiguous, word-aligned run.
      def word_grain_page(page, query)
        return degrade_words(WORDS_SCRIPT_NOTE, page) unless query.to_s.match?(TIBETAN_SCRIPT)

        seam = tibetan_words
        return degrade_words(WORDS_MODULE_NOTE, page) unless seam

        @word_grain = true
        page.select { |row| word_grain_hit?(row, query, seam) }
      end

      def degrade_words(note, page)
        @words_note = note
        page
      end

      # Feature-detect + memoize the seam (the define.rb :auto contract):
      # loaded from canonical/nabu-data on first use, nil when not synced.
      def tibetan_words
        return @tibetan_words unless @tibetan_words == :auto

        @tibetan_words = Nabu::TibetanWords.load_default
      end

      # -- P57-4: --lect, the resolution-level filter --------------------------

      # Does the query stand word-aligned somewhere in this hit's stored
      # text? Boundaries are segmented lazily (only when a contiguous folded
      # occurrence exists — for a real hit it almost always does) and once
      # per row.
      def word_grain_hit?(row, query, seam)
        language = row.fetch(:language)
        display = StoredSnippet.normalized_display(row.fetch(:text),
                                                   exempt: Nabu::Normalize.nfc_exempt?(language))
        needle = Nabu::Normalize.search_form(query.to_s, language: language)
        return false if needle.empty?

        folded, map = Nabu::Normalize.fold_with_map(display, language: language)
        boundaries = nil
        from = 0
        while (index = folded.index(needle, from))
          boundaries ||= word_boundaries(seam, display)
          start = map[index]
          finish = StoredSnippet.extend_over_marks(display, map[index + needle.length - 1] + 1)
          return true if word_grain_aligned?(display, boundaries, start, finish)

          from = index + 1
        end
        false
      end

      # The boundary set of a text: every token start and every token end
      # (tokens are exact substrings at their offsets, trailing tsheg kept —
      # the TibetanWords contract).
      def word_boundaries(seam, display)
        seam.segment(display).each_with_object({}) do |token, set|
          set[token.offset] = true
          set[token.offset + token.form.length] = true
        end
      end

      # A span aligns when its start IS a boundary and its end is a boundary
      # — directly, or after skipping a tsheg run: tokens keep their trailing
      # tsheg, so a query that (normally) omits the word's final tsheg ends
      # one tsheg short of the boundary and must still count as the word.
      def word_grain_aligned?(display, boundaries, start, finish)
        return false unless boundaries[start]

        finish += 1 while !boundaries[finish] && display[finish]&.match?(Nabu::TibetanSegmenter::TSHEG)
        boundaries[finish] || false
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
