# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class CLITest < Minitest::Test
  # Run the Thor CLI in-process (never shell out to bin/nabu). Returns the
  # captured [stdout, stderr, exit_status]. exit_status is nil when the CLI
  # returned normally without calling exit.
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

  def test_version_prints_version_to_stdout
    out, _err, status = run_cli(["version"])
    assert_equal "#{Nabu::VERSION}\n", out
    assert_nil status, "version should not signal failure"
  end

  def test_help_lists_all_commands
    out, _err, _status = run_cli(["help"])
    %w[version sync status rebuild search show].each do |command|
      assert_match(/\b#{command}\b/, out, "help output should list #{command}")
    end
  end

  def test_exit_on_failure_is_enabled
    assert Nabu::CLI.exit_on_failure?
  end

  # Every remaining stub subcommand must announce it is not implemented and
  # fail (exit 1). (sync is implemented as of P2-4.)
  %w[search show].each do |command|
    define_method(:"test_#{command}_stub_is_not_implemented") do
      _out, err, status = run_cli([command])
      assert_equal 1, status, "#{command} should exit with status 1"
      assert_match(/not implemented/i, err, "#{command} should report not implemented on stderr")
    end
  end

  # status is implemented (P1-6). Against an empty registry with no catalog db,
  # it reports "no sources" and exits cleanly (0). (The shipped sources.yml now
  # registers perseus-greek, so this behaviour is tested against an isolated
  # empty registry rather than the real config.)
  def test_status_reports_no_sources_and_succeeds
    with_empty_registry_env do |config|
      out, _err, status = with_config(config) { run_cli(["status"]) }
      assert_nil status, "status should not signal failure with an empty registry"
      assert_match(/no sources registered/i, out)
    end
  end

  # rebuild against an empty registry: nothing to replay, clean exit (0).
  def test_rebuild_empty_registry_says_nothing_to_rebuild
    with_empty_registry_env do |config|
      out, _err, status = with_config(config) { run_cli(["rebuild"]) }
      assert_nil status, "rebuild should not signal failure with an empty registry"
      assert_match(/nothing to rebuild/i, out)
    end
  end

  def test_rebuild_dry_run_lists_plan_and_changes_nothing
    with_rebuild_env do |config|
      out, _err, status = with_config(config) { run_cli(%w[rebuild --dry-run]) }

      assert_nil status
      assert_match(/dry run/i, out)
      assert_match(/replay\s+corpus/, out)
      refute File.exist?(config.catalog_path), "dry run must not build the db"
    end
  end

  def test_rebuild_runs_and_reports_counts
    with_rebuild_env do |config|
      out, _err, status = with_config(config) { run_cli(%w[rebuild]) }

      assert_nil status
      assert_match(/Dropped catalog db/, out)
      assert_match(/corpus.*\+2 added/, out)
      assert_match(/TOTAL.*\+2 added/, out)
      assert File.exist?(config.catalog_path), "a real run builds the db"
    end
  end

  # -- sync (P2-4) ---------------------------------------------------------

  def test_sync_without_slug_or_all_fails
    with_empty_registry_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[sync]) }
      assert_equal 1, status
      assert_match(/slug or --all/i, err)
    end
  end

  def test_sync_unknown_slug_fails
    with_empty_registry_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[sync nope]) }
      assert_equal 1, status
      assert_match(/unknown source/i, err)
    end
  end

  # --parse-only skips fetch, so TestAdapter (whose #fetch is unimplemented)
  # loads straight off the canonical dir and the counts are reported.
  def test_sync_parse_only_loads_and_reports_counts
    with_sync_env(enabled: true) do |config|
      out, _err, status = with_config(config) { run_cli(%w[sync corpus --parse-only]) }
      assert_nil status
      assert_match(/corpus\s+parse-only/, out)
      assert_match(/\+2 added/, out)
    end
  end

  # Explicit beats config: a disabled source named by slug still syncs, with a
  # printed note.
  def test_sync_disabled_source_by_slug_prints_note_and_runs
    with_sync_env(enabled: false) do |config|
      out, _err, status = with_config(config) { run_cli(%w[sync corpus --parse-only]) }
      assert_nil status
      assert_match(/disabled; syncing anyway/i, out)
      assert_match(/\+2 added/, out)
    end
  end

  private

  # One TestAdapter source "corpus" (two documents) with canonical data; the
  # caller stubs Config.load with the yielded config. +enabled+ seeds the row.
  def with_sync_env(enabled:)
    Dir.mktmpdir("nabu-cli-sync") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "one.txt"), "Iliad\nμῆνιν\nἄειδε\n")
      File.write(File.join(corpus, "two.txt"), "Odyssey\nἄνδρα\n")
      sources = File.join(root, "sources.yml")
      File.write(sources, "corpus:\n  adapter: TestAdapter\n  enabled: #{enabled}\n  sync_policy: live\n")
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
    end
  end

  # Minitest 6 dropped Minitest::Mock (and it is outside the dependency budget),
  # so pin Config.load to +config+ by swapping the singleton method, restoring
  # the original afterward.
  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  # Build a throwaway config with an empty (comments-only) registry and no
  # catalog db, and yield it.
  def with_empty_registry_env
    Dir.mktmpdir("nabu-cli-empty") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "# no sources registered\n")
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
    end
  end

  # Build a throwaway config with one replayable TestAdapter source ("corpus",
  # two documents) and yield it; the caller stubs Config.load with it.
  def with_rebuild_env
    Dir.mktmpdir("nabu-cli-rebuild") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "one.txt"), "Iliad\nμῆνιν\nἄειδε\n")
      File.write(File.join(corpus, "two.txt"), "Odyssey\nἄνδρα\n")
      sources = File.join(root, "sources.yml")
      File.write(sources, "corpus:\n  adapter: TestAdapter\n  enabled: true\n")
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
    end
  end
end
