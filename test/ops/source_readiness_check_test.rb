# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nabu/ops/source_readiness_check"

# The registered-never-synced probe: a source registered in sources.yml
# whose first sync never ran is invisible to every board (the run ledger
# is the only place a sync leaves a mark), so a build-complete module
# can hang unattended until someone happens to ask. The probe diffs the
# registry against the ledger and fails BY NAME on any source with zero
# runs once its grace window (from the adopted date) has passed.
class SourceReadinessCheckTest < Minitest::Test
  def with_setup(sources_yaml:, runs: [], today: Date.new(2026, 11, 17))
    Dir.mktmpdir do |dir|
      sources_path = File.join(dir, "sources.yml")
      File.write(sources_path, sources_yaml)
      ledger_path = File.join(dir, "history.sqlite3")
      db = Sequel.connect("sqlite://#{ledger_path}")
      db.create_table(:runs) do
        primary_key :id
        String :source_slug
        String :status
      end
      runs.each { |slug| db[:runs].insert(source_slug: slug, status: "ok") }
      db.disconnect
      yield Nabu::Ops::SourceReadinessCheck.new(
        sources_path: sources_path, ledger_path: ledger_path, today: today
      )
    end
  end

  SOURCES = <<~YAML
    fresh-module:
      adapter: Nabu::Adapters::X
      adopted: "2026-11-14"
    stale-module:
      adapter: Nabu::Adapters::Y
      adopted: "2026-10-27"
    synced-module:
      adapter: Nabu::Adapters::Z
      adopted: "2026-09-01"
  YAML

  def test_a_source_with_zero_runs_past_the_grace_window_fails_by_name
    with_setup(sources_yaml: SOURCES, runs: %w[synced-module]) do |check|
      report = check.run
      refute report.skipped
      assert_equal 1, report.findings.size
      assert_match(/stale-module/, report.findings.first)
      assert_match(/zero runs/, report.findings.first)
      refute report.clean?
    end
  end

  def test_the_grace_window_shields_a_freshly_adopted_source
    with_setup(sources_yaml: SOURCES, runs: %w[synced-module stale-module]) do |check|
      report = check.run
      assert report.clean?, "fresh-module is 3 days old — inside the 7-day grace"
    end
  end

  def test_one_run_of_any_kind_satisfies_the_probe
    with_setup(sources_yaml: SOURCES, runs: %w[synced-module stale-module fresh-module]) do |check|
      assert check.run.clean?
    end
  end

  def test_a_missing_ledger_is_an_announced_skip_never_a_failure
    Dir.mktmpdir do |dir|
      sources_path = File.join(dir, "sources.yml")
      File.write(sources_path, SOURCES)
      check = Nabu::Ops::SourceReadinessCheck.new(
        sources_path: sources_path, ledger_path: File.join(dir, "absent.sqlite3"),
        today: Date.new(2026, 11, 17)
      )
      report = check.run
      assert report.skipped, "a public clone carries no ledger — the probe skips cleanly"
      assert report.clean?
    end
  end

  def test_an_entry_without_an_adopted_date_is_graceless
    yaml = "dateless-module:\n  adapter: Nabu::Adapters::X\n"
    with_setup(sources_yaml: yaml) do |check|
      report = check.run
      assert_equal 1, report.findings.size
      assert_match(/dateless-module/, report.findings.first)
    end
  end
end
