# frozen_string_literal: true

require "yaml"
require_relative "trend_rules"

module Nabu
  module Health
    # `nabu health` (bare, local, no network) — the run-history + live-corpus
    # half of source health (the network-facing half is RemoteProbe, P5-3). It
    # returns data; the CLI formats it and owns the exit code. Two independent
    # halves fold into one Report:
    #
    # 1. Per-source run-history trends (TrendRules) read from the runs + documents
    #    tables: quarantine spike, added collapse, withdrawal/retirement creep,
    #    stale source. A source with no runs at all reports :never_synced (info,
    #    not red); a source with runs and no anomalies reports no findings ("ok").
    #
    # 2. Live golden replay — each query in test/golden/golden_queries.yml run
    #    against the LIVE catalog + fulltext index (read-only) via Query::Search.
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

      # corpus: :present | :no_index | :absent
      Report = Data.define(:sources, :golden, :corpus) do
        def any_loud?
          sources.any? { |source| source.findings.any?(&:loud?) } || golden.any?(&:lost?)
        end

        def soft_count = sources.sum { |source| source.findings.count(&:soft?) }
        def loud_count = sources.sum { |s| s.findings.count(&:loud?) } + golden.count(&:lost?)
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

      # +catalog+ / +fulltext+ are Sequel DBs or nil (not built yet). Store models
      # are assumed bound to +catalog+ by the caller (Store.setup!), matching the
      # RemoteProbe convention. +now+ is injected so the stale rule is testable.
      def initialize(registry:, catalog:, fulltext:, golden_queries:, now: Time.now)
        @registry = registry
        @catalog = catalog
        @fulltext = fulltext
        @golden_queries = golden_queries
        @now = now
      end

      def run
        Report.new(sources: check_sources, golden: replay_golden, corpus: corpus_state)
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

      def check_source(entry)
        source = @catalog && Store::Source.first(slug: entry.slug)
        return never_synced(entry.slug) if source.nil?

        runs = successful_runs(source)
        return never_synced(entry.slug) if runs.empty?

        SourceCheck.new(slug: entry.slug, findings: findings_for(entry, source, runs))
      end

      def findings_for(entry, source, runs)
        latest = runs.first
        prior = runs.drop(1).first(TrendRules::SPIKE_WINDOW).map { |run| run[:errored] }
        [
          TrendRules.quarantine_spike(latest_errored: latest[:errored], prior_errored: prior),
          TrendRules.added_collapse(successful_runs: runs),
          TrendRules.withdrawal_creep(shed: shed_count(source), total: total_count(source)),
          stale_finding(entry, source)
        ].compact
      end

      # Only enabled, live-policy sources are held to the cadence; manual/frozen
      # sources are expected to sit still (maintenance §2).
      def stale_finding(entry, source)
        return nil unless entry.enabled && entry.sync_policy == "live"

        TrendRules.stale_source(last_sync_at: source.last_sync_at, now: @now)
      end

      def never_synced(slug)
        SourceCheck.new(
          slug: slug,
          findings: [Finding.new(kind: :never_synced, severity: :info, message: "never synced")]
        )
      end

      # Newest-first, so runs.first is the latest successful run.
      def successful_runs(source)
        Store::Run.where(source_id: source.id, status: "succeeded")
                  .order(Sequel.desc(:id))
                  .select_map(%i[added updated errored])
                  .map { |added, updated, errored| { added: added, updated: updated, errored: errored } }
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
        query = entry["query"]
        expect = entry["expect_urn"]
        return GoldenCheck.new(query: query, expect_urn: expect, status: :skipped) unless urn_in_catalog?(expect)

        urns = search.run(query, lang: entry["lang"]).map(&:urn)
        GoldenCheck.new(query: query, expect_urn: expect, status: urns.include?(expect) ? :found : :lost)
      end

      def urn_in_catalog?(urn)
        !Store::Passage.first(urn: urn).nil?
      end
    end
  end
end
