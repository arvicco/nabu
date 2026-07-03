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

  # --- sync_all policy filtering ------------------------------------------

  def test_sync_all_runs_only_enabled_live_sources
    [LiveEnabled, LiveDisabled, ManualSrc, FrozenSrc].each(&:reset!)
    reg = registry(
      entry("live-enabled",  LiveEnabled,  enabled: true,  sync_policy: "live"),
      entry("live-disabled", LiveDisabled, enabled: false, sync_policy: "live"),
      entry("manual-src",    ManualSrc,    enabled: true,  sync_policy: "manual"),
      entry("frozen-src",    FrozenSrc,    enabled: true,  sync_policy: "frozen")
    )

    results = make_runner(reg).sync_all
    assert_equal %w[live-enabled], results.keys
    assert_equal 1, LiveEnabled.fetches
    assert_equal 0, LiveDisabled.fetches, "disabled source skipped in --all"
    assert_equal 0, ManualSrc.fetches,    "manual policy excluded from --all"
    assert_equal 0, FrozenSrc.fetches,    "frozen policy excluded from --all"
  end

  def test_sync_all_isolates_one_sources_failure
    [FailingLive, OkLive].each(&:reset!)
    reg = registry(
      entry("failing-live", FailingLive, enabled: true, sync_policy: "live"),
      entry("ok-live",      OkLive,      enabled: true, sync_policy: "live")
    )

    results = make_runner(reg).sync_all
    assert_kind_of Nabu::FetchError, results["failing-live"]
    assert_kind_of Nabu::SyncRunner::Outcome, results["ok-live"]
    refute results["ok-live"].aborted?
    assert_equal 1, OkLive.fetches, "one source's failure must not stop the others"
  end

  # --- helpers ------------------------------------------------------------

  private

  def make_runner(reg)
    Nabu::SyncRunner.new(config: config, registry: reg, db: @db)
  end

  def config
    Nabu::Config.new(canonical_dir: @canonical, db_dir: @root, sources_path: "(n/a)", config_path: "(test)")
  end

  def registry(*entries)
    Nabu::SourceRegistry.new(entries)
  end

  def entry(slug, klass, enabled:, sync_policy: "live")
    Nabu::SourceRegistry::Entry.new(
      slug: slug, adapter_class_name: klass.name, enabled: enabled, sync_policy: sync_policy
    )
  end

  def source_row(slug) = Nabu::Store::Source.first(slug: slug)

  def live_docs = Nabu::Store::Document.where(withdrawn: false).count

  def last_run_status = Nabu::Store::Run.order(:id).last&.status
end
