# frozen_string_literal: true

require "json"

require_relative "../normalize"
require_relative "range"

module Nabu
  module Query
    # `nabu vocab URN [--limit N]` (P14-3, the dropped P13-7): a lemma
    # frequency profile of ONE document (or a citation range, or a single
    # passage) against the whole gold-lemma corpus — total gold tokens, distinct
    # lemmas, the most DISTINCTIVE vocabulary, and the in-document hapax
    # legomena. Improvements §1.7: "learn these twelve words before reading
    # Odyssey 9", the corpus-linguistics half of the lemma layer.
    #
    # == Gold shelves only, and honest about the ceiling
    #
    # The profile counts tokens that carry a GOLD lemma — the treebank shelves
    # (PROIEL/TOROT/ISWOC, the UD treebanks) and the ORACC cuneiform gold layer,
    # ~8% of the corpus (docs/library.md §6). A document with no gold lemmas
    # (the FTS-only literary corpora: Perseus, First1K, the papyri, ASPR poetry)
    # is NOT an error — it reports plainly that it carries no annotation and
    # names the gold-bearing languages (queried live from the lemma index, so
    # the list never drifts from the data). Since P26-4 a SILVER document
    # (Diorisis) also profiles — labeled, against the gold reference corpus;
    # see "The lemma tier" below. The marquee learner use case (vocab-prep
    # for Homer) works through the silver Diorisis edition where one exists;
    # gold projection stays improvements §3.1.
    #
    # == The distinctiveness metric: log-odds, not a simple ratio (measured)
    #
    # "Distinctive" = over-represented HERE versus the corpus at large. The
    # obvious simple relative-frequency ratio (f_doc/T_doc) / (F_corpus/N_corpus)
    # is unstable for rare lemmas: on Caesar's Gallic War it ranks a lemma
    # attested twice in the document and once elsewhere ABOVE the campaign
    # vocabulary (Gallia, legio, proelium) — the classic small-count blow-up.
    # So the ranking is the log-odds-ratio with an informative Dirichlet prior
    # (Monroe, Colaresi & Quinn 2008, "Fightin' Words"): the prior is the two
    # corpora combined, and the z-score divides the log-odds by its estimated
    # standard deviation, so a rare lemma's large variance pulls its score DOWN
    # without any arbitrary min-count floor. Validated on the live corpus:
    # Caesar → Caesar, hostis, castra, legio, proelium, exercitus; Cicero's
    # De officiis → officium, honestas, decorum, cupiditas, societas — the
    # actual subject vocabulary, function words no longer swamping it.
    #
    # == Cost: plain SELECTs, no new index (the P13-6 precedent)
    #
    # Measured read-only on the live 2.5M-row lemma index: profiling a document
    # is (a) load + JSON-parse its own passages' annotations for exact per-lemma
    # TOKEN counts — bounded to the document, ~30-125ms even for the whole
    # Vulgate NT (11,851 passages); (b) one `COUNT(*)` for the corpus total
    # (~30ms, b-tree count); (c) one indexed `lemma_folded IN (…)` GROUP BY for
    # the distinct lemmas' corpus frequencies (~15-20ms). No profiling query
    # exceeds ~200ms, so — exactly as P13-6 concluded for --morph — a bespoke
    # index would cost a rebuild to beat a sub-200ms post-filter. Only the
    # no-gold path pays a ~0.6s GROUP-BY-language scan, once, to name the
    # gold-bearing languages honestly; the normal path never touches it.
    #
    # == Corpus frequency is passage-frequency (documented approximation)
    #
    # The in-document side uses exact TOKEN counts (the philologically
    # meaningful "occurs 8 times here", and what hapax legomena means). The
    # corpus side uses the lemma index's PASSAGE-frequency — one row per
    # (folded lemma, passage) — because token-level corpus totals are not
    # stored and a per-query corpus census would be the heavy thing P13-6 tells
    # us to avoid. The log-odds estimator is robust to this minor granularity
    # difference; the alternative (passage-frequency on the document side too)
    # would turn "8 occurrences" into "in 6 passages", less intuitive for no gain.
    #
    # == The lemma tier (P26-4, the P26-0 journaled decision): label + gold reference
    #
    # Vocab is a PROFILE surface, so silver (automatic-lemmatization)
    # documents PROFILE — that is the Diorisis value: a frequency profile of
    # Herodotus exists at all only because of the automatic layer — but the
    # profile is LABELED: Profile#lemma_tier carries the tier of the scope's
    # own indexed lemma rows ("silver" → the CLI prints an explicit
    # automatic-lemmatization warning line; "gold" renders exactly as
    # pre-tier; nil = unresolvable, e.g. a stale index, no claim made).
    # The CORPUS REFERENCE side (corpus_frequencies, the corpus total, the
    # gold-bearing-languages listing) stays scoped to GOLD rows: the class
    # has always documented its denominator as "the whole gold-lemma corpus",
    # and a 6-7M-row silver flood would silently redefine every z-score. A
    # silver document is thus profiled AGAINST the verified reference — its
    # own tokens counted exactly, its comparison corpus staying gold — and
    # the in-document/corpus tier split is visible in the label. Pre-tier
    # indexes have no tier column and read all-gold (the borrowed_column?
    # precedent).
    #
    # == Why the distinctive/hapax lists never repeat a row (P18-3)
    #
    # The tally is hash-keyed by folded lemma across the whole scope, so
    # each list carries one row per folded key — repeated spellings MERGE
    # into one count (a second occurrence un-hapaxes the word, never
    # doubles it), and a repeated display string would need one raw
    # spelling folding two ways inside one scope, i.e. a mixed-language
    # document, which no adapter mints.
    #
    # == MCP: CLI-only for v1 (argued, deferred with a re-open condition)
    #
    # The eyeball-ritual `--random` was kept off MCP because it is an operator
    # ritual, not AI-facing. Vocab is genuinely research-facing, so the argument
    # is different — but the verdict is the same, for two concrete reasons.
    # First, an AI client gains little it cannot already assemble from
    # nabu_search --lemma + nabu_define; the value of a ranked vocabulary table
    # is a human scanning it. Second, the 8% gold-lemma ceiling means the tool
    # would answer "no gold lemmas" for the great majority of documents a model
    # might name (Homer, Vergil, the papyri all lack gold lemmas) — a weak
    # conversational primitive that mostly reports absence. Ship the CLI, let
    # the workflow prove itself at the terminal, and expose it over MCP once
    # lemma projection (§3.1) lifts coverage past the ceiling — a clean
    # follow-up, exactly as MorphFacets left the ORACC pos-facet.
    class Vocab
      # Unknown urn (neither a document, a passage, nor a resolvable range).
      # The CLI turns this into a clean stderr line + exit 1.
      class NotFound < Nabu::Error; end

      DEFAULT_LIMIT = 20

      # One distinctive lemma: its first-seen upstream spelling, the exact
      # token count in the document, its corpus passage-frequency, and the
      # log-odds z-score the ranking sorts by.
      Entry = Data.define(:lemma, :doc_count, :corpus_freq, :score)

      # The profile. +kind+ is :document / :range / :passage. +total_tokens+ is
      # the count of tokens bearing a lemma; +distinct_lemmas+ the distinct
      # folded lemmas. +distinctive+ is the top-N Entry list (empty when no
      # lemmas). +hapax+ the raw spellings attested exactly once (full list;
      # +hapax_count+ its size). +gold_languages+ is populated ONLY on the
      # no-lemma path: [[language, gold corpus_row_count], …] descending, so
      # the CLI can point the user at a document that will profile.
      # +lemma_tier+ (P26-4, class note): the tier of the scope's own indexed
      # lemma rows — "gold" | "silver" | nil (unresolvable — no tier claim).
      Profile = Data.define(
        :urn, :kind, :title, :language, :passages, :annotated_passages,
        :total_tokens, :distinct_lemmas, :distinctive, :hapax, :hapax_count,
        :gold_languages, :lemma_tier
      ) do
        def initialize(lemma_tier: nil, **rest) = super
      end

      # A resolved scope: the header (urn/kind/title/language/passage count) and
      # the live passage rows carrying language + annotations_json to tally.
      Scope = Data.define(:urn, :kind, :title, :language, :passage_count, :rows)

      def initialize(catalog:, fulltext:)
        @catalog = catalog
        @fulltext = fulltext
      end

      # Profile +urn+ and return a Profile, or raise NotFound. +limit+ caps both
      # the distinctive list and the hapax spellings the CLI prints.
      def run(urn, limit: DEFAULT_LIMIT)
        scope = resolve(urn) or raise NotFound, "urn not found: #{urn}"

        counts, total_tokens = tally(scope.rows)
        return no_gold_profile(scope) if total_tokens.zero?

        gold_profile(scope, counts, total_tokens, limit: limit)
      end

      private

      # Literal-first, like Show: a real document or passage wins before a range
      # is even attempted (a document urn holding a hyphen is never misparsed).
      def resolve(urn)
        document_scope(urn) || passage_scope(urn) || range_scope(urn)
      end

      def document_scope(urn)
        doc = @catalog[:documents].where(urn: urn).first
        return nil if doc.nil?

        rows = live_passage_rows(document_id: doc.fetch(:id))
        Scope.new(urn: urn, kind: :document, title: doc.fetch(:title),
                  language: doc.fetch(:language), passage_count: rows.size, rows: rows)
      end

      def passage_scope(urn)
        row = @catalog[:passages]
              .join(:documents, id: Sequel[:passages][:document_id])
              .where(Sequel[:passages][:urn] => urn, Sequel[:documents][:withdrawn] => false)
              .select(Sequel[:passages][:urn].as(:urn),
                      Sequel[:passages][:language].as(:language),
                      Sequel[:passages][:annotations_json].as(:annotations_json),
                      Sequel[:passages][:withdrawn].as(:withdrawn),
                      Sequel[:documents][:title].as(:title))
              .first
        return nil if row.nil? || truthy?(row.fetch(:withdrawn))

        Scope.new(urn: urn, kind: :passage, title: row.fetch(:title),
                  language: row.fetch(:language), passage_count: 1, rows: [row])
      end

      def range_scope(urn)
        slice = Range.new(catalog: @catalog).resolve(urn)
        return nil if slice.nil?

        doc = @catalog[:documents].where(id: slice.document_id).first
        rows = live_passage_rows(document_id: slice.document_id,
                                 sequence: slice.start_seq..slice.end_seq)
        Scope.new(urn: urn, kind: :range, title: doc&.fetch(:title),
                  language: doc&.fetch(:language), passage_count: rows.size, rows: rows)
      end

      # Live passages of a document (neither the passage nor its document
      # withdrawn), optionally narrowed to a sequence range, carrying only the
      # language + annotations needed for the tally.
      def live_passage_rows(document_id:, sequence: nil)
        dataset = @catalog[:passages]
                  .join(:documents, id: Sequel[:passages][:document_id])
                  .where(Sequel[:passages][:document_id] => document_id,
                         Sequel[:passages][:withdrawn] => false,
                         Sequel[:documents][:withdrawn] => false)
        dataset = dataset.where(Sequel[:passages][:sequence] => sequence) if sequence
        dataset.select(Sequel[:passages][:urn].as(:urn),
                       Sequel[:passages][:language].as(:language),
                       Sequel[:passages][:annotations_json].as(:annotations_json)).all
      end

      # Tally exact per-lemma TOKEN counts over the scope's passages, folding
      # each lemma the way the index folded it (search_form in the passage's
      # language). Returns [{ folded => { raw:, count: } }, total_tokens]. The
      # cheap '"lemma"' substring probe skips the JSON parse for un-annotated
      # passages (annotations default to "{}"), exactly as the Indexer does.
      def tally(rows)
        counts = {}
        total = 0
        rows.each do |row|
          json = row.fetch(:annotations_json)
          next if json.nil? || !json.include?('"lemma"')

          tokens = JSON.parse(json)["tokens"]
          next unless tokens.is_a?(Array)

          total += tally_tokens(tokens, language: row.fetch(:language), into: counts)
        end
        [counts, total]
      end

      def tally_tokens(tokens, language:, into:)
        added = 0
        tokens.each do |token|
          next unless token.is_a?(Hash)

          lemma = token["lemma"]
          next if lemma.nil? || lemma.empty?

          folded = Nabu::Normalize.search_form(lemma, language: language)
          entry = into[folded] ||= { raw: lemma, count: 0 }
          entry[:count] += 1
          added += 1
        end
        added
      end

      # The full profile for a document that DOES carry lemmas. The
      # comparison corpus is GOLD (class note); the scope's own tier rides
      # the profile as the label.
      def gold_profile(scope, counts, total_tokens, limit:)
        corpus = corpus_frequencies(counts.keys)
        corpus_total = gold_corpus_rows.count.to_f
        distinctive = rank_distinctive(counts, corpus, total_tokens, corpus_total, limit: limit)
        hapax = counts.select { |_, e| e[:count] == 1 }.map { |_, e| e[:raw] }.sort

        Profile.new(
          urn: scope.urn, kind: scope.kind, title: scope.title, language: scope.language,
          passages: scope.passage_count, annotated_passages: annotated_count(scope.rows),
          total_tokens: total_tokens, distinct_lemmas: counts.size,
          distinctive: distinctive, hapax: hapax, hapax_count: hapax.size, gold_languages: nil,
          lemma_tier: scope_tier(scope.rows)
        )
      end

      # GOLD corpus passage-frequency per folded lemma (class note): an
      # indexed lemma_folded IN GROUP BY, batched so a document with
      # thousands of distinct lemmas never overruns SQLite's bound-variable
      # limit. { folded => count }.
      def corpus_frequencies(folded_lemmas)
        out = {}
        folded_lemmas.each_slice(500) do |slice|
          counted = gold_corpus_rows.where(lemma_folded: slice)
                                    .group_and_count(:lemma_folded)
          counted.each { |row| out[row.fetch(:lemma_folded)] = row.fetch(:count) }
        end
        out
      end

      # The gold-tier reference slice (class note; P26-4). A pre-tier index
      # has no tier column — and no silver rows — so the unfiltered dataset
      # is the same gold-only corpus.
      def gold_corpus_rows
        dataset = @fulltext[Store::Indexer::LEMMA_TABLE]
        return dataset unless tier_column?

        dataset.where(tier: Store::Indexer::GOLD_TIER)
      end

      def tier_column?
        return @tier_column unless @tier_column.nil?

        @tier_column = @fulltext[Store::Indexer::LEMMA_TABLE].columns.include?(:tier)
      end

      # The tier of the scope's OWN lemma rows, read from the index by the
      # first annotated passage's urn (tier is per-source, a scope is within
      # one document, so one passage answers for all). nil — no tier claim —
      # when the column predates the tier or the index lacks the passage
      # (stale index): honest unknown, the CLI then labels nothing.
      def scope_tier(rows)
        return nil unless tier_column?

        urn = rows.find do |row|
          (json = row[:annotations_json]) && json.include?('"lemma"')
        end&.fetch(:urn, nil)
        return nil unless urn

        @fulltext[Store::Indexer::LEMMA_TABLE].where(urn: urn).get(:tier)
      end

      # Rank the lemmas by log-odds z-score (see class note), most distinctive
      # first, and take the top +limit+. A lemma the index somehow lacks (its
      # own passages count toward its corpus frequency, so this is only defence)
      # falls back to its document count as its corpus frequency.
      def rank_distinctive(counts, corpus, total_tokens, corpus_total, limit:)
        entries = counts.map do |folded, entry|
          corpus_freq = corpus[folded] || entry[:count]
          score = log_odds_z(doc_count: entry[:count], corpus_freq: corpus_freq,
                             doc_total: total_tokens, corpus_total: corpus_total)
          Entry.new(lemma: entry[:raw], doc_count: entry[:count],
                    corpus_freq: corpus_freq, score: score)
        end
        entries.sort_by { |entry| -entry.score }.first(limit)
      end

      # Log-odds-ratio with an informative Dirichlet prior = the two corpora
      # combined (Monroe et al. 2008). The prior α_w = doc_count + corpus_freq,
      # α0 = doc_total + corpus_total; the z-score divides the log-odds by its
      # estimated sd so rare-lemma variance damps the score. Guards the
      # degenerate zero-variance case (tiny fixtures).
      def log_odds_z(doc_count:, corpus_freq:, doc_total:, corpus_total:)
        prior = doc_count + corpus_freq
        a0 = doc_total + corpus_total
        odds1 = (doc_count + prior).to_f / (doc_total + a0 - doc_count - prior)
        odds2 = (corpus_freq + prior).to_f / (corpus_total + a0 - corpus_freq - prior)
        return 0.0 if odds1 <= 0 || odds2 <= 0

        variance = (1.0 / (doc_count + prior)) + (1.0 / (corpus_freq + prior))
        return 0.0 if variance <= 0

        (Math.log(odds1) - Math.log(odds2)) / Math.sqrt(variance)
      end

      # A document with zero lemma-bearing tokens: name the gold-bearing
      # languages so the user can profile something that works. This is the
      # ONLY path that scans the lemma index by language (~0.6s, measured) —
      # the normal path never does.
      def no_gold_profile(scope)
        Profile.new(
          urn: scope.urn, kind: scope.kind, title: scope.title, language: scope.language,
          passages: scope.passage_count, annotated_passages: 0,
          total_tokens: 0, distinct_lemmas: 0, distinctive: [], hapax: [], hapax_count: 0,
          gold_languages: gold_languages
        )
      end

      # [[language, gold corpus_row_count], …] descending — the GOLD-bearing
      # languages (the listing's own label; tier-scoped since P26-4),
      # straight from the lemma index so the list never drifts.
      def gold_languages
        gold_corpus_rows
          .group_and_count(:language)
          .order(Sequel.desc(:count))
          .map { |row| [row.fetch(:language), row.fetch(:count)] }
      end

      # How many of the scope's passages actually carried a gold lemma (the
      # cheap substring probe, no re-parse) — the honest coverage denominator.
      def annotated_count(rows)
        rows.count { |row| (json = row.fetch(:annotations_json)) && json.include?('"lemma"') }
      end

      def truthy?(value)
        [true, 1].include?(value)
      end
    end
  end
end
