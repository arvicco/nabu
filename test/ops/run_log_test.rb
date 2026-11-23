# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nabu/ops/run_log"

# Nabu::Ops::RunLog — a long run's own flushed log: stage opens with their
# estimates, closes with elapsed, throttled document counts, durable notes.
class RunLogTest < Minitest::Test
  L = Nabu::Ops::RunLog

  def setup
    @dir = Dir.mktmpdir("nabu-run-log")
    @now = Time.utc(2026, 11, 23, 0, 0, 0)
  end

  def teardown = FileUtils.rm_rf(@dir)

  def open_log = L.open(kind: "rebuild", now: @now, env: { L::DIR_ENV => @dir }, clock: -> { @now })

  def test_the_log_home_is_the_drill_home_unless_overridden
    assert_equal File.expand_path("~/Library/Logs/nabu"), L.dir(env: {})
    assert_equal @dir, L.dir(env: { L::DIR_ENV => @dir })
  end

  def test_stages_ticks_and_notes_land_flushed_and_stamped
    log = open_log
    assert_equal File.join(@dir, "rebuild-2026-11-23_000000.log"), log.path
    inner_stages = []
    reporter = log.tee(Nabu::ProgressReporter.new(on_stage: ->(label, _eta) { inner_stages << label }))

    log.line("rebuild preflight — read before anything is dropped")
    reporter.stage("pap", eta: Nabu::Eta::Estimate.new(seconds: 600, basis_seconds: 600))
    reporter.load_tick(10, 0)
    @now += 61
    reporter.load_tick(500, 2)
    @now += 5
    reporter.load_tick(900, 2) # inside the minute: not logged
    reporter.note("links: 3 scopes carried")
    reporter.stage("timeline", eta: Nabu::Eta::NONE)
    @now += 30
    log.close

    text = File.read(log.path)
    assert_equal %w[pap timeline], inner_stages, "the command's own sinks still hear every stage"
    assert_equal <<~LOG, text
      2026-11-23 00:00:00Z  rebuild preflight — read before anything is dropped
      2026-11-23 00:00:00Z  stage pap — ~10m (last run 10m)
      2026-11-23 00:01:01Z        pap: 500 docs (2 quarantined)
      2026-11-23 00:01:06Z  note links: 3 scopes carried
      2026-11-23 00:01:06Z  done  pap in 1m06s, 900 docs
      2026-11-23 00:01:06Z  stage timeline — first run — no estimate
      2026-11-23 00:01:36Z  done  timeline in 30s
    LOG
  end

  def test_lines_are_readable_before_close
    log = open_log
    log.line("started")
    assert_match(/started\n\z/, File.read(log.path), "sync: a reader tailing the file sees the line at once")
  ensure
    log&.close
  end
end
