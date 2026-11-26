# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require "nabu/ops/trickle"

# Sync admission during a rebuild: the rebuild does not hold the catalog
# write window for its whole run, so a sync started mid-rebuild would load
# into the half-built catalog. A catalog-writing sync (any flavour,
# --parse-only included) started while a rebuild runs REFUSES at once —
# one line naming the running rebuild, non-zero exit, no wait. The detector
# is the existing one (Ops::DbSnapshot.rebuild_in_progress: the ledger's
# rebuild row RUNNING with its pid alive, or a live `nabu rebuild` in the
# process table). The process table arrives through the suite's injected
# seam (test/support/cli_rebuild_preflight_seams.rb), never the box's real
# one; the ledger half is a throwaway ledger here.
class CLISyncRebuildAdmissionTest < Minitest::Test
  def test_a_sync_refuses_while_the_ledger_shows_a_running_rebuild
    with_sync_env do |config|
      running_rebuild_row(config)

      out, err, status = with_config(config) { run_cli(%w[sync corpus --parse-only]) }

      assert_equal 1, status
      line = err.lines.grep(/sync refused/).first
      assert_match(/rebuild \(full\) RUNNING since .* \(pid #{Process.pid}\)/, line)
      refute_match(/added/, out, "nothing loaded")
      refute File.exist?(config.catalog_path), "the refusal touches no catalog"
    end
  end

  def test_a_sync_refuses_while_the_process_table_shows_a_rebuild
    with_sync_env do |config|
      with_process_table("  4242 ruby bin/nabu rebuild --incremental\n") do
        _out, err, status = with_config(config) { run_cli(%w[sync corpus --parse-only]) }

        assert_equal 1, status
        assert_match(%r{sync refused — a rebuild process is running \(pid 4242: ruby bin/nabu rebuild}, err)
      end
    end
  end

  def test_a_sync_proceeds_when_no_rebuild_runs
    with_sync_env do |config|
      completed_rebuild_row(config)

      out, err, status = with_config(config) { run_cli(%w[sync corpus --parse-only]) }

      assert_nil status, err
      assert_match(/\+2 added/, out)
    end
  end

  # The trickle runner only writes canonical/ (through the engine's fetch
  # arm) and never consults the sync admission: it starts beside a running
  # rebuild exactly as before.
  def test_the_trickle_runner_starts_beside_a_running_rebuild
    with_sync_env do |config|
      running_rebuild_row(config)
      paths = Nabu::Ops::Trickle::Paths.new(dir: File.join(config.local_dir, "trickle"), slug: "corpus")
      control = Nabu::Ops::Trickle::Control.new(paths: paths, canonical_dir: config.canonical_dir,
                                                alive: ->(_pid) { true }, spawner: ->(**) { 777 },
                                                out: StringIO.new, sleeper: ->(_) {})

      assert_equal 777, control.start!(engines: { "books" => trickle_engine(config) }, settle: 0)
    end
  end

  private

  def run_cli(argv)
    status = nil
    out, err = capture_io do
      Nabu::CLI.start(argv)
    rescue SystemExit => e
      status = e.status
    end
    [out, err, status]
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def with_process_table(text)
    original = Nabu::CLI.rebuild_preflight_seams
    Nabu::CLI.rebuild_preflight_seams = original.merge(ps_output: -> { text })
    yield
  ensure
    Nabu::CLI.rebuild_preflight_seams = original
  end

  # One TestAdapter source "corpus" (two documents) with canonical data.
  def with_sync_env
    Dir.mktmpdir("nabu-cli-admission") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "one.txt"), "Iliad\nμῆνιν\nἄειδε\n")
      File.write(File.join(corpus, "two.txt"), "Odyssey\nἄνδρα\n")
      sources = File.join(root, "sources.yml")
      File.write(sources, "corpus:\n  adapter: TestAdapter\n  wired: true\n  sync_policy: auto\n")
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: File.join(root, "config", "nabu.yml")
      )
    end
  end

  def with_ledger(config)
    FileUtils.mkdir_p(File.dirname(config.history_path))
    ledger = Nabu::Store::Ledger.connect(config.history_path)
    Nabu::Store::Ledger.migrate!(ledger)
    yield ledger
  ensure
    ledger&.disconnect
  end

  # A rebuild row with no completed_at whose pid is alive (this process).
  def running_rebuild_row(config)
    with_ledger(config) do |ledger|
      Nabu::Store::RebuildRuns.start!(ledger, mode: "full", planned_stages: [], git_sha: nil, pid: Process.pid)
    end
  end

  def completed_rebuild_row(config)
    with_ledger(config) do |ledger|
      id = Nabu::Store::RebuildRuns.start!(ledger, mode: "full", planned_stages: [], git_sha: nil,
                                                   pid: Process.pid)
      Nabu::Store::RebuildRuns.complete!(ledger, id)
    end
  end

  def trickle_engine(config)
    schedule = Nabu::PacedCrawl::Schedule.new(cadence: :per_phase, slices_per_phase: 1, stop_after_zero_slices: 1)
    spec = Nabu::PacedCrawl::Spec.new(name: "books", ledger_file: ".admission.json",
                                      classes: { denied: "denied", empty: "empty", timeout: "timeout" },
                                      delay: 0.01, slice: 1, schedule: schedule)
    Nabu::PacedCrawl::Engine.new(spec: spec, dir: File.join(config.canonical_dir, "corpus"),
                                 universe: -> { %w[a] }, held: ->(_) { false },
                                 fetch_one: ->(_) { raise "never fetched in this test" }, sleeper: ->(_) {})
  end
end
