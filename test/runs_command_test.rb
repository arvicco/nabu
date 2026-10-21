# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `nabu runs close-stale` — closes ledger run rows still "running" past the
# health stale threshold (killed runs nobody noticed) as "abandoned",
# through the RunRecorder gateway. --dry-run lists them and writes nothing.
# Every case runs against a throwaway ledger.
class RunsCommandTest < Minitest::Test
  STALE = Nabu::Health::Invariants::STALE_OPEN_RUN_SECONDS

  def test_dry_run_lists_the_stale_rows_and_writes_nothing
    with_runs_env do |config, ledger|
      seed(ledger)
      out, err, status = with_config(config) { run_cli(%w[runs close-stale --dry-run]) }
      assert_nil status, err
      assert_match(/would close 2 stale run rows/, out)
      assert_match(/dead\s+sync\s+\d{4}-\d{2}-\d{2} \d{2}:\d{2}/, out)
      assert_match(/older\s+rebuild/, out)
      refute_match(/live/, out)
      assert_match(/dry run — nothing written/, out)
      assert_equal 3, ledger[:runs].where(status: "running").count
    end
  end

  # The dry run is the look-before-write: it must not migrate the ledger
  # either (a ledger migrated ahead of an older checkout's migration files
  # refuses that checkout's every later open).
  def test_dry_run_never_migrates_the_ledger
    Dir.mktmpdir("nabu-runs-cli") do |root|
      config = runs_config(root)
      FileUtils.mkdir_p(File.dirname(config.history_path))
      db = Nabu::Store::Ledger.connect(config.history_path)
      require "sequel/extensions/migration"
      Sequel::Migrator.run(db, Nabu::Store::Ledger::MIGRATIONS_DIR, target: 11)
      db[:runs].insert(source_slug: "dead", kind: "sync", started_at: Time.now - STALE - 60, status: "running")
      db.disconnect

      out, err, status = with_config(config) { run_cli(%w[runs close-stale --dry-run]) }
      assert_nil status, err
      assert_match(/would close 1 stale run row\b/, out)
      db = Nabu::Store::Ledger.connect(config.history_path)
      assert_equal 11, db[:schema_info].get(:version)
      db.disconnect
    end
  end

  def test_close_stale_abandons_the_stale_rows_and_names_them
    with_runs_env do |config, ledger|
      seed(ledger)
      out, err, status = with_config(config) { run_cli(%w[runs close-stale]) }
      assert_nil status, err
      assert_match(/closed 2 stale run rows "abandoned"/, out)
      assert_match(/dead\s+sync/, out)
      assert_equal(%w[dead older], ledger[:runs].where(status: "abandoned").select_order_map(:source_slug))
      assert_equal ["live"], ledger[:runs].where(status: "running").select_map(:source_slug)

      out, = with_config(config) { run_cli(%w[runs close-stale]) }
      assert_match(/no stale run rows/, out, "a re-run finds nothing left to close")
    end
  end

  def test_without_a_ledger_it_says_so_and_creates_nothing
    Dir.mktmpdir("nabu-runs-cli") do |root|
      config = runs_config(root)
      out, _err, status = with_config(config) { run_cli(%w[runs close-stale]) }
      assert_nil status
      assert_match(/no ledger/, out)
      refute_path_exists config.history_path
    end
  end

  private

  def seed(ledger)
    now = Time.now
    ledger[:runs].insert(source_slug: "dead", kind: "sync", started_at: now - STALE - 60, status: "running")
    ledger[:runs].insert(source_slug: "older", kind: "rebuild", started_at: now - STALE - 86_400,
                         loaded_at: now - STALE - 80_000, status: "running")
    ledger[:runs].insert(source_slug: "live", kind: "sync", started_at: now - 3_600, status: "running")
    ledger[:runs].insert(source_slug: "done", kind: "sync", started_at: now - STALE - 60,
                         finished_at: now - STALE, status: "succeeded")
  end

  def runs_config(root)
    Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                     local_dir: File.join(root, "local"), sources_path: File.join(root, "config", "sources.yml"),
                     config_path: File.join(root, "config", "nabu.yml"))
  end

  def with_runs_env
    Dir.mktmpdir("nabu-runs-cli") do |root|
      config = runs_config(root)
      ledger = Nabu::Store::Ledger.open!(config.history_path)
      yield config, ledger
    ensure
      ledger&.disconnect
    end
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end
end
