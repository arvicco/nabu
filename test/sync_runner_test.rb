# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# SyncRunner (P2-4). No network anywhere: the test adapters are in-memory (they
# touch no files), returning a FetchReport from #fetch and counting the calls,
# so the withdrawal circuit breaker, parse-only, and --all policy filtering can
# all be exercised deterministically against a fresh in-memory catalog.
class SyncRunnerTest < Minitest::Test
  include StoreTestDB

  # --- test adapters ------------------------------------------------------

  # discover yields refs whose id IS the document urn — the identity Perseus has
  # and the breaker relies on — so (existing urns − discovered ids) is a real
  # withdrawal prediction. Class-level state (urns/counter/sha) so the registry's
  # no-arg construction can reach it.
  class BreakerAdapter < Nabu::Adapter
    class << self
      attr_accessor :urns, :fetch_count, :fetch_sha, :fetch_error

      def reset!(urns: [])
        self.urns = urns
        self.fetch_count = 0
        self.fetch_sha = "sha-1"
        self.fetch_error = false
      end
    end

    MANIFEST = Nabu::SourceManifest.new(
      id: "breaker", name: "Breaker", license: "CC0 1.0", license_class: "open",
      upstream_url: "https://example.invalid/breaker", parser_family: "plaintext"
    )
    def self.manifest = MANIFEST

    def fetch(_workdir, **)
      self.class.fetch_count += 1
      raise Nabu::FetchError, "boom" if self.class.fetch_error

      Nabu::FetchReport.new(sha: self.class.fetch_sha, fetched_at: Time.now, notes: nil)
    end

    def discover(workdir)
      return enum_for(:discover, workdir) unless block_given?

      self.class.urns.each do |urn|
        yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: urn, path: File.join(workdir, "x"))
      end
    end

    def parse(ref)
      doc = Nabu::Document.new(urn: ref.id, language: "grc", title: "t", canonical_path: ref.path)
      doc << Nabu::Passage.new(urn: "#{ref.id}:1", language: "grc", text: "α", text_normalized: "α", sequence: 0)
      doc
    end
  end

  # A one-document source with a per-subclass fetch counter, for --all policy
  # filtering. Each subclass names its own slug and gets its own @fetches.
  class CountingSource < Nabu::Adapter
    def self.slug = raise(NotImplementedError)
    def self.fetches = @fetches ||= 0
    def self.reset! = @fetches = 0
    def self.bump! = @fetches = fetches + 1

    def self.manifest
      Nabu::SourceManifest.new(
        id: slug, name: slug, license: "CC0 1.0", license_class: "open",
        upstream_url: "https://example.invalid/#{slug}", parser_family: "plaintext"
      )
    end

    def fetch(_workdir, **)
      self.class.bump!
      Nabu::FetchReport.new(sha: "sha-#{self.class.slug}", fetched_at: Time.now, notes: nil)
    end

    def discover(workdir)
      return enum_for(:discover, workdir) unless block_given?

      yield Nabu::DocumentRef.new(source_id: self.class.slug, id: "urn:test:#{self.class.slug}:1",
                                  path: File.join(workdir, "x"))
    end

    def parse(ref)
      doc = Nabu::Document.new(urn: ref.id, language: "grc", title: "t", canonical_path: ref.path)
      doc << Nabu::Passage.new(urn: "#{ref.id}:1", language: "grc", text: "α", text_normalized: "α", sequence: 0)
      doc
    end
  end

  # Quarantines every discovered ref (parse always raises ParseError), so a sync
  # yields a high errored count with 0 added — used to trip the inline P5-5
  # quarantine-spike warning against a seeded low-errored history.
  class SpikeAdapter < Nabu::Adapter
    MANIFEST = Nabu::SourceManifest.new(
      id: "spike", name: "Spike", license: "CC0 1.0", license_class: "open",
      upstream_url: "https://example.invalid/spike", parser_family: "plaintext"
    )
    def self.manifest = MANIFEST

    def fetch(_workdir, **) = Nabu::FetchReport.new(sha: "s", fetched_at: Time.now, notes: nil)

    def discover(workdir)
      return enum_for(:discover, workdir) unless block_given?

      90.times do |i|
        yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "urn:spike:#{i}", path: File.join(workdir, "x"))
      end
    end

    def parse(_ref) = raise(Nabu::ParseError, "bad")
  end

  # A multi-repo source (UD shape): fetch returns a FetchReport whose +repos+
  # maps each upstream repo_url to its HEAD sha, so update_source_state pins one
  # ledger pin per repo. Class-level +repos+ so a re-sync can drop a repo
  # (stale-pin removal) or advance a sha. discover yields one doc so the load
  # path runs.
  class MultiRepoAdapter < Nabu::Adapter
    class << self
      attr_accessor :repos

      def reset!(repos: {})
        self.repos = repos
      end
    end

    MANIFEST = Nabu::SourceManifest.new(
      id: "multi", name: "Multi", license: "CC0 1.0", license_class: "open",
      upstream_url: "https://github.com/acme", parser_family: "plaintext"
    )
    def self.manifest = MANIFEST

    def fetch(_workdir, **)
      Nabu::FetchReport.new(sha: self.class.repos.values.last, fetched_at: Time.now,
                            notes: nil, repos: self.class.repos)
    end

    def discover(workdir)
      return enum_for(:discover, workdir) unless block_given?

      yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "urn:multi:1", path: File.join(workdir, "x"))
    end

    def parse(ref)
      doc = Nabu::Document.new(urn: ref.id, language: "grc", title: "t", canonical_path: ref.path)
      doc << Nabu::Passage.new(urn: "#{ref.id}:1", language: "grc", text: "α", text_normalized: "α", sequence: 0)
      doc
    end
  end

  # P19-4: a reference_edges? source — one document whose metadata carries
  # related: targets (one urn, one language code); a sync must refresh
  # kind=reference edges into the links journal via LibraryReferences.
  class ReferenceAdapter < Nabu::Adapter
    MANIFEST = Nabu::SourceManifest.new(
      id: "refsrc", name: "RefSrc", license: "per-item manifest", license_class: "research_private",
      upstream_url: "canonical/refsrc (local)", parser_family: "plaintext"
    )
    def self.manifest = MANIFEST
    def self.reference_edges? = true

    def fetch(_workdir, **) = Nabu::FetchReport.new(sha: "s", fetched_at: Time.now, notes: nil)

    def discover(workdir)
      return enum_for(:discover, workdir) unless block_given?

      yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "urn:nabu:refsrc:c:article",
                                  path: File.join(workdir, "x"))
    end

    def parse(ref)
      doc = Nabu::Document.new(
        urn: ref.id, language: "und", title: "Article", canonical_path: ref.path,
        metadata: { "kind" => "article", "collection" => "c",
                    "related" => ["urn:nabu:ccmh:mar:mt", "chu"] }
      )
      doc << Nabu::Passage.new(urn: "#{ref.id}:1", language: "und", text: "t", sequence: 1)
      doc
    end
  end

  # P26-5 Part A: an index-inert local shelf — its content kind mints neither
  # passages nor dictionary entries, so its sync must perform NO index work.
  # discover yields nothing (the loaders take an empty batch); one subclass
  # per inert kind so the routing is pinned for all three.
  class InertShelf < Nabu::Adapter
    def self.slug = raise(NotImplementedError)
    def self.kind = raise(NotImplementedError)
    def self.content_kind = kind

    def self.manifest
      Nabu::SourceManifest.new(
        id: slug, name: slug, license: "Owner-authored (local shelf)", license_class: "open",
        upstream_url: "canonical/#{slug} (local)", parser_family: "plaintext"
      )
    end

    def fetch(_workdir, **) = Nabu::FetchReport.new(sha: "s", fetched_at: Time.now, notes: nil)

    def discover(workdir)
      return enum_for(:discover, workdir) unless block_given?

      self
    end

    def parse(_ref) = raise(NotImplementedError)
  end

  class NotesShelf < InertShelf
    def self.slug = "notes-shelf"
    def self.kind = :notes
  end

  class LanguageShelfSrc < InertShelf
    def self.slug = "language-shelf"
    def self.kind = :language
  end

  class SourceShelfSrc < InertShelf
    def self.slug = "source-shelf"
    def self.kind = :source
  end

  class LiveEnabled  < CountingSource; def self.slug = "live-enabled";  end
  class LiveDisabled < CountingSource; def self.slug = "live-disabled"; end
  class ManualSrc    < CountingSource; def self.slug = "manual-src";    end
  class FrozenSrc    < CountingSource; def self.slug = "frozen-src";    end
  class OkLive       < CountingSource; def self.slug = "ok-live";       end

  class FailingLive < CountingSource
    def self.slug = "failing-live"
    def fetch(_workdir, **) = raise(Nabu::FetchError, "down")
  end

  def setup
    @ledger = ledger_test_db
    @db = store_test_db
    @root = Dir.mktmpdir("nabu-sync")
    @canonical = File.join(@root, "canonical")
    FileUtils.mkdir_p(@canonical)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # --- circuit breaker ----------------------------------------------------

  def test_breaker_aborts_before_loading_and_force_overrides
    urns = (1..5).map { |i| "urn:cts:test:w#{i}" }
    BreakerAdapter.reset!(urns: urns)
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))

    first = runner.sync("breaker")
    refute first.aborted?
    assert_equal 5, first.load_report.added
    assert_equal 5, live_docs

    # Re-sync where discover yields only 2 of 5 → would withdraw 3 (60% > 20%).
    BreakerAdapter.urns = urns.first(2)
    aborted = runner.sync("breaker")
    assert aborted.aborted?
    assert_equal 5, aborted.breaker.existing_count
    assert_equal 3, aborted.breaker.would_withdraw_count
    assert_equal 5, live_docs, "a tripped breaker withdraws nothing"
    assert_equal "aborted", last_run_status

    # --force proceeds: 3 withdrawn, run succeeded.
    forced = runner.sync("breaker", force: true)
    refute forced.aborted?
    assert_equal 3, forced.load_report.withdrawn
    assert_equal 2, live_docs
    assert_equal "succeeded", last_run_status
  end

  def test_exactly_at_threshold_does_not_trip
    urns = (1..5).map { |i| "urn:cts:test:w#{i}" }
    BreakerAdapter.reset!(urns: urns)
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))
    runner.sync("breaker")

    # discover yields 4 of 5 → would withdraw exactly 1 (= 20%); strict > → no trip.
    BreakerAdapter.urns = urns.first(4)
    outcome = runner.sync("breaker")
    refute outcome.aborted?
    assert_equal 1, outcome.load_report.withdrawn
    assert_equal 4, live_docs
    assert_equal "succeeded", last_run_status
  end

  # --- post-load ANALYZE (P42-4) ------------------------------------------

  # The trigger is the changed-row count (added + updated + withdrawn) against
  # ANALYZE_MIN_CHANGED_ROWS, strict >. A skip-run (nothing changed, only
  # skipped) is never bulk — the waste case the threshold exists to avoid.
  def test_bulk_load_predicate_fires_above_threshold_only
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))
    n = Nabu::SyncRunner::ANALYZE_MIN_CHANGED_ROWS

    assert runner.send(:bulk_load?, load_report(added: n + 1)), "> threshold is bulk"
    assert runner.send(:bulk_load?, load_report(updated: n, withdrawn: 1)), "u + w count too"
    refute runner.send(:bulk_load?, load_report(added: n)), "= threshold is not bulk (strict >)"
    refute runner.send(:bulk_load?, load_report(added: 5, skipped: 9_999_999)),
           "a skip-run (only skipped) never analyzes"
    refute runner.send(:bulk_load?, nil), "no load report → not bulk"
  end

  # A small real sync is far below the bulk floor, so it refreshes no planner
  # stats and the report line stays silent (analyzed nil).
  def test_sub_threshold_sync_skips_analyze_silently
    BreakerAdapter.reset!(urns: (1..5).map { |i| "urn:cts:test:w#{i}" })
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))

    outcome = runner.sync("breaker")
    refute outcome.aborted?
    assert_equal 5, outcome.load_report.added
    assert_nil outcome.analyzed, "a 5-row load is far below the bulk threshold — no ANALYZE"
    refute @db.table_exists?(:sqlite_stat1), "no ANALYZE ran, so no planner stats were written"
  end

  # A bulk load ANALYZEs the catalog AND the fulltext index (a passage source
  # is not index-inert). A 10k-row fixture is impractical, so the bulk verdict
  # is forced here — the threshold logic itself is pinned above.
  def test_bulk_passage_sync_analyzes_catalog_and_index
    BreakerAdapter.reset!(urns: (1..5).map { |i| "urn:cts:test:w#{i}" })
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))

    force_bulk!(runner)
    outcome = runner.sync("breaker")
    refute_nil outcome.analyzed, "a bulk load refreshes planner stats"
    assert_equal "catalog + index", outcome.analyzed.scope
    assert_operator outcome.analyzed.seconds, :>=, 0.0
    assert @db.table_exists?(:sqlite_stat1), "the catalog was ANALYZEd (legal on in-memory)"
    ft = Nabu::Store.connect_fulltext(config.fulltext_path)
    assert ft.table_exists?(:sqlite_stat1), "the fulltext index was ANALYZEd too"
  ensure
    ft&.disconnect
  end

  # An index-inert grain touches no index, so a bulk inert load ANALYZEs the
  # catalog ONLY — and creates no fulltext file to analyze.
  def test_bulk_inert_sync_analyzes_catalog_only
    runner = make_runner(registry(entry(NotesShelf.slug, NotesShelf, enabled: true, kind: "shelf")))

    force_bulk!(runner)
    outcome = runner.sync(NotesShelf.slug)
    assert_equal "catalog", outcome.analyzed.scope
    refute File.exist?(config.fulltext_path), "an inert sync creates no fulltext file to analyze"
  end

  def load_report(added: 0, updated: 0, withdrawn: 0, skipped: 0, errored: 0)
    Nabu::Store::LoadReport.new(added: added, updated: updated, withdrawn: withdrawn,
                                skipped: skipped, errored: errored)
  end

  # Force the bulk-load verdict on ONE runner instance (no minitest/mock in
  # this suite — a singleton override, the fold-file diversion pattern): a
  # real 10k-row fixture is impractical, and the threshold logic itself is
  # pinned by test_bulk_load_predicate_fires_above_threshold_only.
  def force_bulk!(runner)
    def runner.bulk_load?(_load_report) = true
  end

  # --- parse-only ---------------------------------------------------------

  def test_parse_only_never_fetches
    BreakerAdapter.reset!(urns: %w[urn:cts:test:w1 urn:cts:test:w2])
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))

    outcome = runner.sync("breaker", parse_only: true)
    assert_equal 0, BreakerAdapter.fetch_count, "parse-only must never fetch"
    assert_nil outcome.fetch_report
    assert_equal 2, outcome.load_report.added
  end

  def test_parse_only_keeps_prior_last_sync_sha
    BreakerAdapter.reset!(urns: %w[urn:cts:test:w1])
    BreakerAdapter.fetch_sha = "sha-abc"
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))

    runner.sync("breaker") # real fetch pins sha-abc
    assert_equal "sha-abc", source_row("breaker").last_sync_sha
    assert_equal 1, BreakerAdapter.fetch_count

    BreakerAdapter.fetch_sha = "sha-xyz" # would change the pin if fetched
    runner.sync("breaker", parse_only: true)
    assert_equal 1, BreakerAdapter.fetch_count, "parse-only must not fetch"
    assert_equal "sha-abc", source_row("breaker").last_sync_sha, "parse-only keeps the prior sha"
  end

  # --- success bookkeeping ------------------------------------------------

  def test_success_updates_last_sync_at_and_sha
    BreakerAdapter.reset!(urns: %w[urn:cts:test:w1])
    BreakerAdapter.fetch_sha = "sha-head"
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))

    runner.sync("breaker")
    row = source_row("breaker")
    refute_nil row.last_sync_at
    assert_equal "sha-head", row.last_sync_sha
    assert_equal "succeeded", last_run_status
  end

  # --- per-repo pins in the history ledger (P6-3, moved by P7-1) ----------

  def test_multi_repo_sync_records_a_ledger_pin_per_repo
    MultiRepoAdapter.reset!(repos: {
                              "https://github.com/acme/one" => "sha-one",
                              "https://github.com/acme/two" => "sha-two"
                            })
    runner = make_runner(registry(entry("multi", MultiRepoAdapter, enabled: true)))
    runner.sync("multi")

    assert_equal({ "https://github.com/acme/one" => "sha-one",
                   "https://github.com/acme/two" => "sha-two" }, ledger_pins("multi"))
  end

  def test_resync_upserts_shas_and_removes_stale_pins
    source = "multi"
    MultiRepoAdapter.reset!(repos: {
                              "https://github.com/acme/one" => "sha-one",
                              "https://github.com/acme/two" => "sha-two"
                            })
    runner = make_runner(registry(entry(source, MultiRepoAdapter, enabled: true)))
    runner.sync(source)

    # A probe recorded a license baseline on the "one" pin; a sync must not wipe it.
    Nabu::Store::Pin.first(repo_url: "https://github.com/acme/one")
                    .update(license_baseline_sha256: "baseline-one")

    # Next manifest advances "one" and drops "two" entirely.
    MultiRepoAdapter.repos = { "https://github.com/acme/one" => "sha-one-v2" }
    runner.sync(source)

    assert_equal({ "https://github.com/acme/one" => "sha-one-v2" }, ledger_pins(source),
                 "the vanished repo's stale pin must be removed")
    kept = Nabu::Store::Pin.first(repo_url: "https://github.com/acme/one")
    assert_equal "baseline-one", kept.license_baseline_sha256, "upsert must preserve the license baseline"
  end

  # P7-1: single-repo sources pin their one declared repo in the ledger too
  # (pre-P7-1 they pinned only sources.last_sync_sha, which rebuild wiped).
  def test_single_repo_sync_pins_its_declared_repo
    BreakerAdapter.reset!(urns: %w[urn:cts:test:w1])
    BreakerAdapter.fetch_sha = "sha-head"
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))
    runner.sync("breaker")

    assert_equal({ "https://example.invalid/breaker" => "sha-head" }, ledger_pins("breaker"),
                 "the pin is keyed by the same url the remote probe ls-remotes")
  end

  def test_parse_only_leaves_ledger_pins_untouched
    BreakerAdapter.reset!(urns: %w[urn:cts:test:w1])
    BreakerAdapter.fetch_sha = "sha-abc"
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))
    runner.sync("breaker")
    assert_equal({ "https://example.invalid/breaker" => "sha-abc" }, ledger_pins("breaker"))

    BreakerAdapter.fetch_sha = "sha-xyz"
    runner.sync("breaker", parse_only: true)
    assert_equal({ "https://example.invalid/breaker" => "sha-abc" }, ledger_pins("breaker"),
                 "no fetch, no re-pin")
  end

  # --- errors -------------------------------------------------------------

  def test_unknown_slug_raises_validation_error
    error = assert_raises(Nabu::ValidationError) { make_runner(registry).sync("nope") }
    assert_match(/unknown source/i, error.message)
  end

  def test_fetch_error_propagates_and_records_failed_run
    BreakerAdapter.reset!(urns: %w[urn:cts:test:w1])
    BreakerAdapter.fetch_error = true
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))

    assert_raises(Nabu::FetchError) { runner.sync("breaker") }
    assert_equal "failed", last_run_status
    assert_equal 0, live_docs, "a failed fetch loads nothing"
  end

  # --- fulltext auto-indexing (P4-1) --------------------------------------

  # A successful sync reindexes the corpus into the fulltext db: the passages
  # just loaded are findable via FTS5 MATCH, and the count rides in the Outcome.
  def test_sync_populates_the_fulltext_index
    BreakerAdapter.reset!(urns: %w[urn:cts:test:w1 urn:cts:test:w2])
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))

    outcome = runner.sync("breaker")
    assert_equal 2, outcome.indexed, "the Outcome carries the indexed count"

    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    assert_equal 2, fulltext[:passages_fts].count
    hits = fulltext[:passages_fts].where(Sequel.lit("passages_fts MATCH ?", "α")).all
    assert_equal 2, hits.size, "the loaded passages are searchable"
  ensure
    fulltext&.disconnect
  end

  # --parse-only still reindexes (content may have changed).
  def test_parse_only_sync_reindexes
    BreakerAdapter.reset!(urns: %w[urn:cts:test:w1])
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))

    outcome = runner.sync("breaker", parse_only: true)
    assert_equal 1, outcome.indexed

    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    assert_equal 1, fulltext[:passages_fts].count
  ensure
    fulltext&.disconnect
  end

  # A tripped breaker loads nothing and its Outcome has no index count.
  def test_aborted_sync_reports_no_index_count
    urns = (1..5).map { |i| "urn:cts:test:w#{i}" }
    BreakerAdapter.reset!(urns: urns)
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))
    runner.sync("breaker")

    BreakerAdapter.urns = urns.first(2) # would withdraw 3 of 5 → trips
    aborted = runner.sync("breaker")
    assert aborted.aborted?
    assert_nil aborted.indexed
  end

  # --- incremental per-source indexing (P26-5) -----------------------------

  # Every Indexer entry point a sync could reach — the inert-sync spy pins
  # them ALL. (Minitest 6 ships no stub/mock, so the spy is a hand-rolled
  # singleton-method swap, restored in ensure.)
  INDEXER_ENTRY_POINTS = [
    [Nabu::Store::Indexer, :rebuild!],
    [Nabu::Store::Indexer, :refresh_source!],
    [Nabu::Store::Indexer, :rebuild_trigram!],
    [Nabu::Store::AlignmentIndexer, :rebuild!],
    [Nabu::Store::ReflexRootsIndexer, :rebuild!]
  ].freeze

  def forbidding_index_work
    originals = INDEXER_ENTRY_POINTS.map do |mod, name|
      original = mod.method(name)
      mod.define_singleton_method(name) do |*_args, **_kwargs|
        raise "#{mod}.#{name} invoked — index work is forbidden for an index-inert sync"
      end
      [mod, name, original]
    end
    yield
  ensure
    originals&.each { |mod, name, original| mod.define_singleton_method(name, original) }
  end

  # Part A: an index-inert grain's sync must never invoke ANY Indexer entry
  # point — the spy raises on every one of them — and reports indexed: nil
  # (the CLI omits the fragment). No fulltext file may even be created.
  def test_index_inert_shelf_syncs_perform_no_index_work
    [NotesShelf, LanguageShelfSrc, SourceShelfSrc].each do |klass|
      runner = make_runner(registry(entry(klass.slug, klass, enabled: true, kind: "shelf")))
      outcome = forbidding_index_work { runner.sync(klass.slug) }
      refute outcome.aborted?
      assert_nil outcome.indexed, "#{klass.slug}: an inert sync carries no index count"
      refute File.exist?(config.fulltext_path), "#{klass.slug}: no fulltext file may be created"
    end
  end

  # Part B honesty: the Outcome's indexed count is the SOURCE's live passage
  # count, never the corpus total — and the sync refreshes only its own slice.
  def test_sync_indexed_count_is_the_sources_not_the_corpus_total
    BreakerAdapter.reset!(urns: %w[urn:cts:test:w1 urn:cts:test:w2])
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))
    runner.sync("breaker")

    # Another source's rows land in the catalog between syncs (they enter the
    # index at THEIR OWN sync or at `nabu rebuild` — not at breaker's).
    other = Nabu::Store::Source.create(slug: "other", name: "O", adapter_class: "X", license_class: "open")
    doc = Nabu::Store::Document.create(source_id: other.id, urn: "urn:o:1", title: "t", language: "grc",
                                       content_sha256: "x", revision: 1, withdrawn: false)
    Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:o:1:1", sequence: 0, language: "grc",
                                text: "β", text_normalized: "β", content_sha256: "x", revision: 1,
                                withdrawn: false)

    outcome = runner.sync("breaker")
    assert_equal 2, outcome.indexed, "the count is breaker's own live passages, not the corpus total"
  end

  # The withdrawn-document pin: a doc withdrawn upstream LEAVES the index at
  # the source's next sync (the incremental refresh deletes its rows).
  def test_withdrawn_document_leaves_the_index_at_its_next_sync
    urns = (1..5).map { |i| "urn:cts:test:w#{i}" }
    BreakerAdapter.reset!(urns: urns)
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))
    runner.sync("breaker")

    BreakerAdapter.urns = urns.first(4) # exactly at the 20% threshold — no trip
    outcome = runner.sync("breaker")
    assert_equal 1, outcome.load_report.withdrawn
    assert_equal 4, outcome.indexed

    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    assert_equal urns.first(4).map { |urn| "#{urn}:1" }.sort,
                 fulltext[:passages_fts].select_map(:urn).sort,
                 "the withdrawn document's passage must leave the index"
  ensure
    fulltext&.disconnect
  end

  # --- inline deviation warnings (P5-5, delta-aware since P18-7) ------------

  # A sync whose errored count moved off the recorded ledger baseline emits one
  # LOUD delta warning — advisory: the sync still succeeds.
  def test_sync_emits_quarantine_delta_warning_when_off_baseline
    seed_baseline("spiky", baseline: 2, anchor: 2)
    FileUtils.mkdir_p(File.join(@canonical, "spiky"))
    runner = make_runner(registry(entry("spiky", SpikeAdapter, enabled: true)))

    outcome = runner.sync("spiky", parse_only: true)
    refute outcome.aborted?, "an advisory warning must never fail the sync"
    assert_equal 90, outcome.load_report.errored
    finding = outcome.warnings.find { |w| w.kind == :quarantine_delta }
    assert finding, "expected a quarantine delta warning"
    assert_predicate finding, :loud?
    assert_match(/90 errored vs baseline 2 \(\+88\)/, finding.message)
    assert_equal "succeeded", last_run_status
  end

  # The standing-quarantine case (papyri's audited 9,312): errored equals the
  # recorded baseline → SILENT, no warning at all.
  def test_sync_is_silent_when_errored_matches_the_baseline
    seed_baseline("spiky", baseline: 90, anchor: 90)
    FileUtils.mkdir_p(File.join(@canonical, "spiky"))
    runner = make_runner(registry(entry("spiky", SpikeAdapter, enabled: true)))

    outcome = runner.sync("spiky", parse_only: true)
    assert_equal 90, outcome.load_report.errored
    assert_empty outcome.warnings
  end

  # First ok run with quarantines and no baseline yet (pre-005 history): the
  # switchover is announced once (soft), never a phantom "regression".
  def test_first_sync_with_quarantines_announces_the_baseline_recording
    FileUtils.mkdir_p(File.join(@canonical, "spiky"))
    runner = make_runner(registry(entry("spiky", SpikeAdapter, enabled: true)))

    outcome = runner.sync("spiky", parse_only: true)
    finding = outcome.warnings.fetch(0)
    assert_equal :quarantine_baseline_recorded, finding.kind
    refute_predicate finding, :loud?
  end

  # Every ok run records/advances the baseline in the LEDGER (it must survive
  # rebuilds); the anchor is the low-water mark and never advances upward.
  def test_ok_sync_records_and_advances_the_quarantine_baseline
    FileUtils.mkdir_p(File.join(@canonical, "spiky"))
    runner = make_runner(registry(entry("spiky", SpikeAdapter, enabled: true)))

    runner.sync("spiky", parse_only: true) # errored 90
    row = @ledger[:quarantine_baselines].where(source_slug: "spiky").first
    assert_equal 90, row[:baseline]
    assert_equal 90, row[:anchor]

    seed_baseline("other", baseline: 5, anchor: 3) # untouched control
    runner.sync("spiky", parse_only: true) # errored 90 again — steady state
    row = @ledger[:quarantine_baselines].where(source_slug: "spiky").first
    assert_equal 90, row[:baseline]
    assert_equal 90, row[:anchor]
    assert_equal 1, @ledger[:quarantine_baselines].where(source_slug: "spiky").count, "upsert, not append"
  end

  # A clean sync against no history carries no warnings.
  def test_clean_sync_has_no_warnings
    BreakerAdapter.reset!(urns: %w[urn:cts:test:w1 urn:cts:test:w2])
    runner = make_runner(registry(entry("breaker", BreakerAdapter, enabled: true)))
    assert_empty runner.sync("breaker").warnings
  end

  # --- dictionary-shaped sources (P11-4) ------------------------------------

  def test_dictionary_source_routes_to_the_dictionary_loader
    FileUtils.cp_r(Nabu::TestSupport.fixtures("lexica"), File.join(@canonical, "lexica"))
    reg = registry(entry("lexica", Nabu::Adapters::Lexica, enabled: true, sync_policy: "manual"))

    outcome = make_runner(reg).sync("lexica", parse_only: true)

    refute outcome.aborted?
    assert_equal 8, outcome.load_report.added # entry-grained counts
    assert_equal "succeeded", last_run_status
    assert_equal 0, Nabu::Store::Document.count, "a dictionary source must create no documents"
    assert_equal 8, Nabu::Store::DictionaryEntry.count
    assert_empty outcome.warnings
    assert_equal 0, outcome.indexed,
                 "a dictionary source indexes no passages (its index work is the reflex closure)"
  end

  # --- sync_all policy filtering ------------------------------------------

  def test_sync_all_runs_only_enabled_auto_sources
    [LiveEnabled, LiveDisabled, ManualSrc, FrozenSrc].each(&:reset!)
    reg = registry(
      entry("auto-enabled",  LiveEnabled,  enabled: true,  sync_policy: "auto"),
      entry("auto-disabled", LiveDisabled, enabled: false, sync_policy: "auto"),
      entry("manual-src",    ManualSrc,    enabled: true,  sync_policy: "manual"),
      entry("frozen-src",    FrozenSrc,    enabled: true,  sync_policy: "frozen"),
      # P39-0: an auto-cadence SHELF/MODULE is still excluded — only kind: source sweeps.
      entry("auto-shelf",    ManualSrc,    enabled: true,  sync_policy: "auto", kind: "shelf")
    )

    results = make_runner(reg).sync_all
    assert_equal %w[auto-enabled], results.keys
    assert_equal 1, LiveEnabled.fetches
    assert_equal 0, LiveDisabled.fetches, "disabled source skipped in --all"
    assert_equal 0, ManualSrc.fetches,    "manual policy (and the shelf) excluded from --all"
    assert_equal 0, FrozenSrc.fetches,    "frozen policy excluded from --all"
  end

  def test_sync_all_isolates_one_sources_failure
    [FailingLive, OkLive].each(&:reset!)
    reg = registry(
      entry("failing-live", FailingLive, enabled: true, sync_policy: "auto"),
      entry("ok-live",      OkLive,      enabled: true, sync_policy: "auto")
    )

    results = make_runner(reg).sync_all
    assert_kind_of Nabu::FetchError, results["failing-live"]
    assert_kind_of Nabu::SyncRunner::Outcome, results["ok-live"]
    refute results["ok-live"].aborted?
    assert_equal 1, OkLive.fetches, "one source's failure must not stop the others"
  end

  # --- grant gate in --all (P42-r1) ---------------------------------------

  def test_sync_all_skips_a_grant_required_source_without_acknowledgment
    [LiveEnabled, OkLive].each(&:reset!)
    reg = registry(
      entry("granted-src", LiveEnabled, enabled: true, sync_policy: "auto", grant_required: true),
      entry("ok-live",     OkLive,      enabled: true, sync_policy: "auto")
    )

    results = make_runner(reg).sync_all
    assert_instance_of Nabu::SyncRunner::GrantRequired, results["granted-src"]
    assert_equal "granted-src", results["granted-src"].slug
    assert_equal 0, LiveEnabled.fetches, "a grant-blocked source is never fetched mid-batch"
    assert_kind_of Nabu::SyncRunner::Outcome, results["ok-live"], "the batch runs the others"
  end

  def test_sync_all_runs_a_grant_source_once_acknowledged
    LiveEnabled.reset!
    Nabu::GrantGate.new(ledger: @ledger).record!(slug: "granted-src", terms: "t", how: "flag")
    reg = registry(entry("granted-src", LiveEnabled, enabled: true, sync_policy: "auto", grant_required: true))

    results = make_runner(reg).sync_all
    assert_kind_of Nabu::SyncRunner::Outcome, results["granted-src"]
    assert_equal 1, LiveEnabled.fetches, "an acknowledged grant source syncs normally"
  end

  # --- reference edges (P19-4) ---------------------------------------------

  def test_sync_refreshes_reference_edges_for_a_reference_edges_source
    BreakerAdapter.reset!(urns: ["urn:cts:test:w1"])
    runner = make_runner(registry(entry("refsrc", ReferenceAdapter, enabled: true, sync_policy: "manual"),
                                  entry("breaker", BreakerAdapter, enabled: true)))

    outcome = runner.sync("refsrc")
    refute outcome.aborted?
    refute_nil outcome.references, "a reference_edges? source reports its refresh"
    assert_equal 1, outcome.references.edges_written
    assert_equal 1, outcome.references.skipped_codes, "the language code stays metadata"

    journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
    begin
      edge = journal[:links].first
      assert_equal %w[urn:nabu:refsrc:c:article urn:nabu:ccmh:mar:mt reference],
                   [edge[:from_urn], edge[:to_urn], edge[:kind]]
      assert_equal "manifest refsrc/c/manifest.yml", edge[:detail]
    ensure
      journal.disconnect
    end

    # A rerun supersedes rather than duplicates; an ordinary source stays nil.
    resync = runner.sync("refsrc")
    assert_equal 1, resync.references.superseded_runs
    assert_nil runner.sync("breaker").references
  end

  # --- helpers ------------------------------------------------------------

  private

  def make_runner(reg)
    Nabu::SyncRunner.new(config: config, registry: reg, db: @db, ledger: @ledger)
  end

  def config
    Nabu::Config.new(canonical_dir: @canonical, db_dir: @root, sources_path: "(n/a)", config_path: "(test)")
  end

  def registry(*entries)
    Nabu::SourceRegistry.new(entries)
  end

  def entry(slug, klass, enabled:, sync_policy: "auto", kind: "source", grant_required: false)
    Nabu::SourceRegistry::Entry.new(
      slug: slug, adapter_class_name: klass.name, enabled: enabled, sync_policy: sync_policy, kind: kind,
      grant_required: grant_required, grant: (grant_required ? sample_grant : nil)
    )
  end

  def sample_grant
    Nabu::SourceRegistry::Grant.new(
      grantor: "G. Starostin", date: "2026-07-15", terms: "any use, per-base attribution required",
      thread: "№1", request_hint: "ask George Starostin"
    )
  end

  def source_row(slug) = Nabu::Store::Source.first(slug: slug)

  # Ledger pins for +slug+ (P7-1: pins live in the history ledger, slug-keyed).
  def ledger_pins(slug)
    Nabu::Store::Pin.where(source_slug: slug).select_hash(:repo_url, :last_sync_sha)
  end

  def live_docs = Nabu::Store::Document.where(withdrawn: false).count

  def last_run_status = Nabu::Store::Run.order(:id).last&.status

  def seed_baseline(slug, baseline:, anchor:)
    @ledger[:quarantine_baselines].insert(
      source_slug: slug, baseline: baseline, anchor: anchor, recorded_at: Time.now
    )
  end
end
