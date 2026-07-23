# frozen_string_literal: true

require "yaml"
require_relative "trend_rules"
require_relative "invariants"

module Nabu
  module Health
    # `nabu health` (bare, local, no network) — the run-history + live-corpus
    # half of source health (the network-facing half is RemoteProbe, P5-3). It
    # returns data; the CLI formats it and owns the exit code. Two independent
    # halves fold into one Report:
    #
    # 1. Per-source run-history trends (TrendRules) read from the history
    #    LEDGER's runs (slug-keyed, kind=sync only — rebuild replays re-add the
    #    whole corpus and would poison every baseline) plus the catalog's
    #    document counts: quarantine spike, added collapse, withdrawal/
    #    retirement creep, stale source. Because the ledger survives `nabu
    #    rebuild` (P7-1), trends read continuously across rebuild boundaries.
    #    A source with no ledger runs — including the fresh-machine case of no
    #    ledger at all — reports :never_synced (info, not red); a source with
    #    runs and no anomalies reports no findings ("ok"). Staleness is judged
    #    from the latest successful sync run's finished_at (ledger truth), not
    #    the catalog's resettable last_sync_at column.
    #
    # 2. Live golden replay — each query in test/golden/golden_queries.yml run
    #    against the LIVE catalog + fulltext index (read-only) via Query::Search
    #    (entries with a `lemma` key replay via Query::LemmaSearch instead —
    #    same loader/indexer-regression rationale, P7-5; when the fulltext file
    #    predates the lemma table those entries are SKIPPED, informational,
    #    like any other not-here-yet corpus state).
    #
    #    Skip rule: the golden queries pin SPECIFIC passage urns (real, trimmed
    #    upstream urns — the fixtures are real bytes). A live corpus only contains
    #    the sources actually synced into it, so a query whose expected urn is not
    #    present in the catalog at all cannot have been "lost" — the document was
    #    simply never loaded here. Those are SKIPPED (informational). Only when
    #    the expected passage IS in the catalog but Search fails to return it is
    #    the query LOST (:loud) — that is the real loader/normalizer/indexer
    #    regression the golden suite exists to catch. This per-urn presence test
    #    is more precise than a source-slug map and needs no urn-scheme coupling.
    #
    # No catalog on disk → corpus :absent (informational "no corpus" note, golden
    # replay skipped, exit 0). Catalog but no fulltext index → corpus :no_index
    # (same informational stance — search cannot run without the index).
    class LocalCheck
      # Where the golden queries live. Prod referencing test/ is deliberate: the
      # golden set is the canonical smoke suite (maintenance §6), and replaying it
      # against the LIVE corpus is exactly the point of P5-5.
      GOLDEN_QUERIES_PATH = File.expand_path("../../../test/golden/golden_queries.yml", __dir__)

      # corpus: :present | :no_index | :absent. +global+ (P18-7) carries the
      # library-wide invariant findings (pending migrations); it defaults empty
      # so every pre-P18-7 construction stays valid.
      Report = Data.define(:sources, :golden, :corpus, :global) do
        def initialize(sources:, golden:, corpus:, global: [])
          super
        end

        def any_loud?
          sources.any? { |source| source.findings.any?(&:loud?) } ||
            golden.any?(&:lost?) || global.any?(&:loud?)
        end

        def soft_count = sources.sum { |source| source.findings.count(&:soft?) } + global.count(&:soft?)
        def loud_count = sources.sum { |s| s.findings.count(&:loud?) } + golden.count(&:lost?) + global.count(&:loud?)
      end

      # findings empty ⇒ healthy ("ok"); otherwise one or more Findings.
      SourceCheck = Data.define(:slug, :findings)

      # status: :found | :lost | :skipped
      GoldenCheck = Data.define(:query, :expect_urn, :status) do
        def lost? = status == :lost
      end

      # Load the golden query list (array of hashes) from +path+; empty when the
      # file is absent so a stripped deployment degrades to trends-only.
      def self.golden_queries(path = GOLDEN_QUERIES_PATH)
        File.exist?(path) ? (YAML.safe_load_file(path) || []) : []
      end

      # +catalog+ / +fulltext+ / +ledger+ are Sequel DBs or nil (not built
      # yet). Store models are assumed bound to +catalog+ (Store.setup!) and
      # ledger models to +ledger+ (Ledger.setup!) by the caller, matching the
      # RemoteProbe convention. +now+ is injected so the stale rule is testable.
      # +canonical_dir+ (P19-1) reaches the invariants' local-shelf checks
      # (dossier files vs derived records, pinned files vs the tree); nil
      # skips them honestly.
      def initialize(registry:, catalog:, fulltext:, ledger:, golden_queries:, now: Time.now, canonical_dir: nil)
        @registry = registry
        @catalog = catalog
        @fulltext = fulltext
        @ledger = ledger
        @golden_queries = golden_queries
        @now = now
        # The P18-7 mechanical invariants ride the same handles; their findings
        # fold into each SourceCheck (plus the Report's global slot), so a green
        # library prints exactly what it printed before — nothing new.
        @invariants = Invariants.new(registry: registry, catalog: catalog, fulltext: fulltext,
                                     ledger: ledger, canonical_dir: canonical_dir, now: now)
      end

      def run
        Report.new(sources: check_sources, golden: replay_golden, corpus: corpus_state,
                   global: @invariants.global)
      end

      private

      def corpus_state
        return :absent unless @catalog
        return :no_index unless @fulltext

        :present
      end

      def check_sources
        @registry.each_source.map { |entry| check_source(entry) }
      end

      # Invariant findings (P18-7) come first — a FAILED last run outranks any
      # trend. A source with no successful sync runs keeps the informational
      # never-synced note, but only when the invariants found nothing (a failed
      # first sync is "last run FAILED", not "never synced").
      def check_source(entry)
        invariant_findings = @invariants.for_source(entry)
        runs = successful_sync_runs(entry.slug)
        if runs.empty?
          return SourceCheck.new(slug: entry.slug, findings: invariant_findings) unless invariant_findings.empty?

          return never_synced(entry.slug)
        end

        SourceCheck.new(slug: entry.slug, findings: invariant_findings + findings_for(entry, runs))
      end

      def findings_for(entry, runs)
        latest = runs.first
        prior = runs.drop(1).first(TrendRules::SPIKE_WINDOW).map { |run| run[:errored] }
        [
          TrendRules.quarantine_spike(latest_errored: latest[:errored], prior_errored: prior),
          TrendRules.added_collapse(successful_runs: runs),
          creep_finding(entry),
          stale_finding(entry, latest[:finished_at])
        ].compact
      end

      # Cumulative shed needs the catalog's document counts; without a catalog
      # (or before this source's first load) there is nothing to measure.
      def creep_finding(entry)
        source = @catalog && Store::Source.first(slug: entry.slug)
        return nil if source.nil?

        TrendRules.withdrawal_creep(shed: shed_count(source), total: total_count(source))
      end

      # Only enabled, auto-cadence sources are held to the cadence; manual/frozen
      # sources are expected to sit still (P39-0, maintenance §2). +finished_at+
      # is the latest successful SYNC run's timestamp from the ledger — unlike
      # sources.last_sync_at it survives rebuilds, so a rebuild neither hides
      # nor causes staleness.
      def stale_finding(entry, finished_at)
        return nil unless entry.enabled && entry.sync_policy == "auto"

        TrendRules.stale_source(last_sync_at: finished_at, now: @now)
      end

      def never_synced(slug)
        SourceCheck.new(
          slug: slug,
          findings: [Finding.new(kind: :never_synced, severity: :info, message: "never synced (no run history)")]
        )
      end

      # Newest-first, so runs.first is the latest successful sync run. Ledger
      # absent (fresh machine) → empty history, honestly. kind=rebuild rows are
      # excluded: a replay's added=everything is not a sync trend.
      def successful_sync_runs(slug)
        return [] unless @ledger

        Store::Run.where(source_slug: slug, kind: "sync", status: "succeeded")
                  .order(Sequel.desc(:id))
                  .select_map(%i[added updated errored finished_at])
                  .map do |added, updated, errored, finished_at|
                    { added: added, updated: updated, errored: errored, finished_at: finished_at }
                  end
      end

      def total_count(source)
        Store::Document.where(source_id: source.id).count
      end

      # withdrawn (absent from canonical) OR retired_upstream (attic-kept but
      # upstream-scrapped) — both count as content the source is shedding.
      def shed_count(source)
        Store::Document.where(source_id: source.id)
                       .where(Sequel.|({ withdrawn: true }, { retired_upstream: true }))
                       .count
      end

      def replay_golden
        return [] unless corpus_state == :present

        search = Query::Search.new(catalog: @catalog, fulltext: @fulltext)
        @golden_queries.map { |entry| replay_one(entry, search) }
      end

      def replay_one(entry, search)
        query = entry["query"] || "lemma:#{entry['lemma']}"
        expect = entry["expect_urn"]
        return GoldenCheck.new(query: query, expect_urn: expect, status: :skipped) unless replayable?(entry, expect)

        # urn-targeted: "is the expected passage findable by this query" must
        # not depend on where it RANKS — in a million-passage corpus a golden
        # passage can be legitimately outranked by hundreds of denser matches
        # (Αἴλιος taught us this live).
        found = if entry["lemma"]
                  !lemma_search.run(entry["lemma"], lang: entry["lang"], urn: expect, limit: 1).empty?
                else
                  !search.run(entry["query"], lang: entry["lang"], urn: expect, limit: 1).empty?
                end
        GoldenCheck.new(query: query, expect_urn: expect, status: found ? :found : :lost)
      end

      # Skip when the expected passage was never loaded here (class note), or —
      # for lemma entries — when the fulltext file predates the lemma table.
      def replayable?(entry, expect)
        return false unless urn_in_catalog?(expect)
        return @fulltext.table_exists?(Store::Indexer::LEMMA_TABLE) if entry["lemma"]

        true
      end

      def lemma_search
        @lemma_search ||= Query::LemmaSearch.new(catalog: @catalog, fulltext: @fulltext)
      end

      def urn_in_catalog?(urn)
        !Store::Passage.first(urn: urn).nil?
      end
    end
  end
end
