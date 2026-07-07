# frozen_string_literal: true

require "test_helper"

# LocalCheck (P5-5): run-history trends + live golden replay, in-memory. Seeds
# sources/runs/documents directly and, for the golden half, builds a tiny real
# indexed corpus so Query::Search runs against it exactly as production does.
class LocalCheckTest < Minitest::Test
  include StoreTestDB

  def setup
    @ledger = ledger_test_db
    @db = store_test_db
    @now = Time.utc(2026, 7, 4)
  end

  # -- run-history trends --------------------------------------------------

  def test_never_synced_source_is_informational_not_red
    seed_source(slug: "quiet", enabled: true)
    report = check(registry_of(["quiet", { enabled: true }]))
    findings = report.sources.first.findings

    assert_equal :never_synced, findings.first.kind
    refute report.any_loud?
  end

  def test_healthy_source_has_no_findings
    source = seed_source(slug: "ok", enabled: true)
    3.times { seed_run(source, added: 4, updated: 1, errored: 0, finished_at: @now - 86_400) }
    seed_docs(source, live: 20)

    report = check(registry_of(["ok", { enabled: true }]))
    assert_empty report.sources.first.findings
    refute report.any_loud?
  end

  def test_quarantine_spike_is_a_loud_finding_and_sets_exit
    source = seed_source(slug: "spiky", enabled: true)
    seed_run(source, added: 5, updated: 0, errored: 1)
    seed_run(source, added: 5, updated: 0, errored: 2)
    seed_run(source, added: 5, updated: 0, errored: 80) # latest: huge jump

    report = check(registry_of(["spiky", { enabled: true }]))
    kinds = report.sources.first.findings.map(&:kind)
    assert_includes kinds, :quarantine_spike
    assert report.any_loud?, "a quarantine spike must fail the health check"
  end

  # 0→1 quarantine across otherwise-clean runs must NOT flag.
  def test_no_spike_on_a_single_stray_quarantine
    source = seed_source(slug: "calm", enabled: true)
    seed_run(source, added: 3, updated: 0, errored: 0)
    seed_run(source, added: 3, updated: 0, errored: 0)
    seed_run(source, added: 3, updated: 0, errored: 1)

    report = check(registry_of(["calm", { enabled: true }]))
    refute report.any_loud?
    refute_includes report.sources.first.findings.map(&:kind), :quarantine_spike
  end

  def test_added_collapse_is_a_soft_warning
    source = seed_source(slug: "dead", enabled: true)
    seed_run(source, added: 9, updated: 2, errored: 0) # historically active
    seed_run(source, added: 0, updated: 0, errored: 0)
    seed_run(source, added: 0, updated: 0, errored: 0)
    seed_run(source, added: 0, updated: 0, errored: 0)

    report = check(registry_of(["dead", { enabled: true }]))
    findings = report.sources.first.findings
    assert_includes findings.map(&:kind), :added_collapse
    refute report.any_loud?, "added collapse is soft — exit 0"
    assert_operator report.soft_count, :>=, 1
  end

  def test_withdrawal_creep_soft_then_loud
    soft = seed_source(slug: "shedding", enabled: true)
    seed_run(soft, added: 100, updated: 0, errored: 0)
    seed_docs(soft, live: 90, withdrawn: 10) # 10% → soft
    soft_report = check(registry_of(["shedding", { enabled: true }]))
    soft_finding = soft_report.sources.first.findings.find { |f| f.kind == :withdrawal_creep }
    assert soft_finding.soft?
    refute soft_report.any_loud?

    @db[:documents].where(source_id: soft.id).delete
    seed_docs(soft, live: 80, retired: 20) # 20% (retired counts) → loud
    loud_report = check(registry_of(["shedding", { enabled: true }]))
    loud_finding = loud_report.sources.first.findings.find { |f| f.kind == :withdrawal_creep }
    assert loud_finding.loud?
    assert loud_report.any_loud?
  end

  def test_stale_enabled_live_source_is_flagged
    source = seed_source(slug: "old", enabled: true)
    seed_run(source, added: 5, updated: 0, errored: 0, finished_at: @now - (30 * 86_400))
    seed_docs(source, live: 5)

    report = check(registry_of(["old", { enabled: true, sync_policy: "live" }]))
    assert_includes report.sources.first.findings.map(&:kind), :stale
    refute report.any_loud?
  end

  # A manual/frozen source is expected to sit still — never "stale".
  def test_manual_source_not_flagged_stale
    source = seed_source(slug: "manual", enabled: true)
    seed_run(source, added: 5, updated: 0, errored: 0, finished_at: @now - (400 * 86_400))
    seed_docs(source, live: 5)

    report = check(registry_of(["manual", { enabled: true, sync_policy: "manual" }]))
    refute_includes report.sources.first.findings.map(&:kind), :stale
  end

  # P7-1: a fresh machine has no ledger at all — every source degrades to the
  # honest informational "never synced", never an error, never loud.
  def test_missing_ledger_reads_as_no_history
    seed_source(slug: "quiet", enabled: true)
    report = check(registry_of(["quiet", { enabled: true }]), ledger: nil)

    finding = report.sources.first.findings.first
    assert_equal :never_synced, finding.kind
    assert_match(/no run history/, finding.message)
    refute report.any_loud?
  end

  # P7-1: rebuild replays are recorded kind=rebuild and excluded from trends —
  # a replay re-adds the whole corpus, which must not read as sync history.
  def test_rebuild_runs_do_not_feed_trends
    source = seed_source(slug: "rebuilt", enabled: true)
    # Only rebuild-kind history: trend-wise this source was never synced.
    seed_run(source, added: 60_000, updated: 0, errored: 90, kind: "rebuild")
    report = check(registry_of(["rebuilt", { enabled: true }]))
    assert_equal :never_synced, report.sources.first.findings.first.kind

    # A giant rebuild between two modest syncs neither spikes nor collapses.
    seed_run(source, added: 5, updated: 0, errored: 1)
    seed_run(source, added: 60_000, updated: 0, errored: 90, kind: "rebuild")
    seed_run(source, added: 4, updated: 1, errored: 0, finished_at: @now - 86_400)
    report = check(registry_of(["rebuilt", { enabled: true }]))
    assert_empty report.sources.first.findings
  end

  # -- live golden replay --------------------------------------------------

  def test_golden_all_found_is_clean
    urn = build_indexed_passage(text: "μῆνιν")
    report = check(registry_of, fulltext: @fulltext,
                                golden: [{ "query" => "μηνιν", "expect_urn" => urn }])

    assert_equal :present, report.corpus
    assert_equal :found, report.golden.first.status
    refute report.any_loud?
  end

  # The doc is in the catalog but dropped from the index ⇒ search misses ⇒ lost.
  def test_golden_lost_when_indexed_doc_disappears_is_red
    urn = build_indexed_passage(text: "μῆνιν")
    Nabu::Store::Document.first(urn: "urn:test:doc").update(withdrawn: true)
    Nabu::Store::Indexer.rebuild!(catalog: @db, fulltext: @fulltext)

    report = check(registry_of, fulltext: @fulltext,
                                golden: [{ "query" => "μηνιν", "expect_urn" => urn }])
    assert_equal :lost, report.golden.first.status
    assert report.any_loud?, "a lost golden query fails the health check"
  end

  # A urn whose source was never synced into this corpus is skipped, not lost.
  def test_golden_skipped_when_expected_urn_absent_from_catalog
    build_indexed_passage(text: "μῆνιν")
    report = check(registry_of, fulltext: @fulltext,
                                golden: [{ "query" => "anything", "expect_urn" => "urn:not:in:catalog:1" }])

    assert_equal :skipped, report.golden.first.status
    refute report.any_loud?
  end

  # -- lemma goldens (P7-5): entries with a `lemma` key replay via LemmaSearch

  def test_lemma_golden_found_through_the_lemma_index
    urn = build_indexed_passage(text: "σὺ δὲ εἶπας",
                                annotations: { "tokens" => [{ "lemma" => "λέγω", "form" => "εἶπας" }] })
    report = check(registry_of, fulltext: @fulltext,
                                golden: [{ "lemma" => "λέγω", "lang" => "grc", "expect_urn" => urn }])

    golden_check = report.golden.first
    assert_equal :found, golden_check.status
    assert_equal "lemma:λέγω", golden_check.query, "the report labels the entry as a lemma probe"
    refute report.any_loud?
  end

  # The passage is in the catalog but its annotations carry no such lemma —
  # the exact loader/indexer regression a lemma golden exists to catch.
  def test_lemma_golden_lost_when_the_lemma_is_not_findable_is_red
    urn = build_indexed_passage(text: "σὺ δὲ εἶπας") # no annotations
    report = check(registry_of, fulltext: @fulltext,
                                golden: [{ "lemma" => "λέγω", "lang" => "grc", "expect_urn" => urn }])

    assert_equal :lost, report.golden.first.status
    assert report.any_loud?
  end

  # A live fulltext file that predates P7-5 has no lemma table yet: the lemma
  # golden is skipped (informational), not a crash and not a loss.
  def test_lemma_golden_skipped_when_the_lemma_table_is_absent
    urn = build_indexed_passage(text: "σὺ δὲ εἶπας",
                                annotations: { "tokens" => [{ "lemma" => "λέγω", "form" => "εἶπας" }] })
    @fulltext.drop_table(Nabu::Store::Indexer::LEMMA_TABLE)
    report = check(registry_of, fulltext: @fulltext,
                                golden: [{ "lemma" => "λέγω", "lang" => "grc", "expect_urn" => urn }])

    assert_equal :skipped, report.golden.first.status
    refute report.any_loud?
  end

  def test_no_corpus_reports_absent_and_skips_replay
    report = Nabu::Health::LocalCheck.new(
      registry: registry_of, catalog: nil, fulltext: nil, ledger: nil,
      golden_queries: [{ "query" => "x", "expect_urn" => "y" }]
    ).run
    assert_equal :absent, report.corpus
    assert_empty report.golden
    refute report.any_loud?
  end

  def test_catalog_without_index_reports_no_index
    seed_source(slug: "s", enabled: true)
    report = Nabu::Health::LocalCheck.new(
      registry: registry_of(["s", { enabled: true }]), catalog: @db, fulltext: nil, ledger: @ledger,
      golden_queries: [{ "query" => "x", "expect_urn" => "y" }]
    ).run
    assert_equal :no_index, report.corpus
    assert_empty report.golden
  end

  def test_golden_queries_loads_the_repo_file
    queries = Nabu::Health::LocalCheck.golden_queries
    assert_operator queries.size, :>=, 6
    # Every entry pins an expected urn and probes via EITHER an FTS query or a
    # lemma (P7-5) — never neither, never both.
    assert(queries.all? { |entry| entry.key?("expect_urn") })
    assert(queries.all? { |entry| entry.key?("query") ^ entry.key?("lemma") })
  end

  private

  def check(registry, fulltext: nil, golden: [], ledger: @ledger)
    Nabu::Health::LocalCheck.new(
      registry: registry, catalog: @db, fulltext: fulltext, ledger: ledger,
      golden_queries: golden, now: @now
    ).run
  end

  # Registry over [slug, enabled:, sync_policy:] tuples; adapter class is never
  # resolved by LocalCheck (it reads only slug/enabled/sync_policy).
  def registry_of(*specs)
    entries = specs.map do |slug, opts|
      opts ||= {}
      Nabu::SourceRegistry::Entry.new(
        slug: slug, adapter_class_name: "TestAdapter",
        enabled: opts.fetch(:enabled, true), sync_policy: opts.fetch(:sync_policy, "live")
      )
    end
    Nabu::SourceRegistry.new(entries)
  end

  def seed_source(slug:, enabled:, last_sync_at: nil)
    Nabu::Store::Source.create(
      slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "open",
      enabled: enabled, last_sync_at: last_sync_at
    )
  end

  # Runs live in the history ledger, slug-keyed (P7-1). +finished_at+ drives
  # the stale rule (it reads the latest successful sync's timestamp).
  def seed_run(source, added:, updated:, errored:, status: "succeeded", kind: "sync", finished_at: @now)
    Nabu::Store::Run.create(
      source_slug: source.slug, kind: kind, started_at: finished_at, finished_at: finished_at,
      added: added, updated: updated, errored: errored, status: status
    )
  end

  def seed_docs(source, live: 0, withdrawn: 0, retired: 0)
    make_docs(source, live, withdrawn: false, retired: false)
    make_docs(source, withdrawn, withdrawn: true, retired: false)
    make_docs(source, retired, withdrawn: false, retired: true)
  end

  def make_docs(source, count, withdrawn:, retired:)
    count.times do
      @seq = (@seq || 0) + 1
      Nabu::Store::Document.create(
        source_id: source.id, urn: "urn:test:#{source.slug}:#{@seq}", content_sha256: "x",
        withdrawn: withdrawn, retired_upstream: retired
      )
    end
  end

  # Build one live, indexed passage; returns its urn. Sets @fulltext.
  # +annotations+ (a Hash) rides along as annotations_json so the lemma index
  # (P7-5) gets rows too.
  def build_indexed_passage(text:, annotations: nil)
    source = seed_source(slug: "corpus", enabled: true)
    doc = Nabu::Store::Document.create(
      source_id: source.id, urn: "urn:test:doc", content_sha256: "x"
    )
    passage = Nabu::Store::Passage.create(
      document_id: doc.id, urn: "urn:test:doc:1", sequence: 0, language: "grc",
      # text_normalized carries the boundary-minted search form (P6-4), as a
      # real corpus row would.
      text: text, text_normalized: Nabu::Normalize.search_form(text, language: "grc"),
      annotations_json: annotations ? JSON.generate(annotations) : "{}",
      content_sha256: "x"
    )
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: @db, fulltext: @fulltext)
    passage.urn
  end
end
