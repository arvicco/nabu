# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::IndexWatcher — index writers supervise themselves from a SEPARATE
# process (the incrementality review, R6): an in-process watchdog cannot
# fire while the GVL is held through one sqlite3_step, so the watcher is a
# forked subprocess sampling the writer (process state + heartbeat-file
# tick age). Stalled ticks earn a heartbeat line; the deadline kills the
# writer and runs the hygiene an ensure-block cannot.
class IndexWatcherTest < Minitest::Test
  Watcher = Nabu::IndexWatcher
  Indexer = Nabu::Store::Indexer
  Intents = Nabu::Store::EngineIntents

  def setup
    @dir = Dir.mktmpdir("nabu-watcher")
    @fulltext_path = File.join(@dir, "fulltext.sqlite3")
    @heartbeat = File.join(@dir, "writer.heartbeat")
    @log = File.join(@dir, "watcher.log")
  end

  def teardown
    [@writer, @watcher_pid].compact.each do |pid|
      Process.kill(:KILL, pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
    FileUtils.rm_rf(@dir)
  end

  # -- fork hygiene ----------------------------------------------------------

  # The sqlite3 gem (2.10.x) warns in every forked child about writable
  # handles the fork inherited, then discards them. The watcher's fork is
  # deliberate and touches no inherited connection by construction, so the
  # warning is noise on every supervised sync a user runs — suppressed for
  # this fork alone (the parse-pool precedent).
  def test_the_watcher_fork_stays_silent_about_inherited_sqlite_handles
    skip "sqlite3 gem without fork safety" unless defined?(SQLite3::ForkSafety)

    held = SQLite3::Database.new(File.join(@dir, "held-writable.sqlite3"))
    w = watcher(writer_pid: Process.pid, deadline: 30)
    _out, err = capture_subprocess_io do
      @watcher_pid = w.start!
      w.stop!
      @watcher_pid = nil
    end
    refute_match(/inherited from a forked process/, err,
                 "the watcher child uses no inherited connection — the gem's fork warning must not reach the user")
  ensure
    held&.close
  end

  # -- deadline arithmetic --------------------------------------------------

  def test_the_deadline_is_twice_the_ledger_estimate
    assert_equal 2 * 3_600, Watcher.deadline_for(estimate: 3_600)
  end

  def test_the_deadline_never_falls_below_the_floor
    assert_equal Watcher::MIN_DEADLINE_SECONDS, Watcher.deadline_for(estimate: 30)
  end

  def test_no_estimate_means_no_deadline_only_heartbeats
    assert_nil Watcher.deadline_for(estimate: nil)
    assert_nil Watcher.deadline_for(estimate: 0)
  end

  def test_the_flag_overrides_the_estimate_and_zero_disables_the_kill
    assert_equal 600, Watcher.deadline_for(estimate: 3_600, override_minutes: 10)
    assert_nil Watcher.deadline_for(estimate: 3_600, override_minutes: 0)
  end

  def test_an_unarmed_default_ignores_the_estimate_but_obeys_the_flag
    assert_nil Watcher.deadline_for(estimate: 3_600, arm_default: false)
    assert_equal 600, Watcher.deadline_for(estimate: 3_600, override_minutes: 10, arm_default: false)
  end

  def test_the_unarmed_default_announces_itself_as_a_policy_not_a_gap
    line = Watcher.arming_line(deadline: nil, estimate: 3_600, kill_default: false)
    assert_match(/heartbeats only — this command arms no kill by default/, line)
    assert_match(/--deadline MINUTES arms one/, line)
  end

  def test_the_estimate_sums_each_stages_latest_ledger_row
    ledger = Nabu::Store::Ledger.open!(File.join(@dir, "history.sqlite3"))
    Nabu::Store::StageTimings.record!(ledger, kind: "sync", scope: "pap", stage: "index_slice", seconds: 100)
    Nabu::Store::StageTimings.record!(ledger, kind: "sync", scope: "pap", stage: "index_slice", seconds: 40)
    Nabu::Store::StageTimings.record!(ledger, kind: "sync", scope: "pap", stage: "fts_merge", seconds: 20)
    Nabu::Store::StageTimings.record!(ledger, kind: "sync", scope: "other", stage: "index_slice", seconds: 999)

    assert_in_delta 60.0, Watcher.ledger_estimate(ledger, kind: "sync", scopes: %w[pap])
    assert_nil Watcher.ledger_estimate(ledger, kind: "sync", scopes: %w[nobody])
  ensure
    ledger&.disconnect
  end

  # -- the heartbeat tee ------------------------------------------------------

  def test_the_tee_writes_every_progress_event_to_the_heartbeat_file
    seen = []
    inner = Nabu::ProgressReporter.new(on_stage: ->(label, _eta) { seen << label })
    teed = Watcher.tee(inner, Watcher::Heartbeat.new(@heartbeat, min_interval: 0))
    teed.stage("index slice: pap")
    teed.load_tick(2_000, 0)

    assert_equal ["index slice: pap"], seen, "the CLI's own sink still fires"
    assert_match(/load_tick 2000/, File.read(@heartbeat))
  end

  # -- the watcher against a fake writer --------------------------------------

  # A writer that never ticks and ignores SIGTERM — the GVL-held statement's
  # signature: only SIGKILL ends it.
  def spawn_stuck_writer
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      trap("TERM") { nil }
      writer.puts "ready"
      writer.close
      sleep 60
      exit!(0)
    end
    writer.close
    reader.gets
    reader.close
    pid
  end

  def watcher(writer_pid:, deadline:, slug: nil)
    File.write(@heartbeat, "stage index slice: pap\n")
    Watcher.new(writer_pid: writer_pid, heartbeat_path: @heartbeat, fulltext_path: @fulltext_path,
                label: "index refresh pap", deadline: deadline, slug: slug, log_path: @log,
                sample_seconds: 0.05, stall_seconds: 0.2, heartbeat_every: 0.2, kill_grace: 0.3)
  end

  # The fulltext a killed bulk write leaves: a journaled intent under the
  # writer's pid, deletemerge=0 applied, the slice marked finished by an
  # earlier run (the hygiene must re-open it as pending).
  def seed_killed_bulk_state(writer_pid)
    db = Nabu::Store.connect_fulltext(@fulltext_path)
    db.run(Indexer::CREATE_TABLE)
    Intents.journal!(db, table: Indexer::TABLE, restore: Indexer::DEFAULT_MERGE_SETTINGS, pid: writer_pid)
    Indexer.apply_merge_settings(db, Indexer::TABLE, Indexer::BULK_MERGE_SETTINGS)
    Indexer.mark_slice_pending!(db, "pap")
    Indexer.mark_slice_finished!(db, "pap")
    db.disconnect
  end

  def test_the_deadline_kills_a_stuck_writer_and_runs_the_hygiene
    @writer = spawn_stuck_writer
    seed_killed_bulk_state(@writer)
    @watcher_pid = watcher(writer_pid: @writer, deadline: 0.6, slug: "pap").start!
    Process.wait(@watcher_pid)
    _, status = Process.wait2(@writer)
    @writer = nil
    @watcher_pid = nil

    assert_equal Signal.list.fetch("KILL"), status.termsig, "TERM was ignored, so the watcher escalated to KILL"
    log = File.read(@log)
    assert_match(/no progress tick for .* fts5 merge suspected/, log, "the stall earned a heartbeat line first")
    assert_match(/deadline .* passed — killing the writer \(pid #{status.pid}\)/, log)
    assert_match(/hygiene: engine config restored, WAL truncated, slice pap left pending/, log)

    db = Nabu::Store.connect_fulltext(@fulltext_path, readonly: true)
    assert_equal 10, db[:passages_fts_config].where(k: "deletemerge").get(:v), "deletemerge restored"
    assert_empty db[Intents::TABLE].all
    assert Indexer.slice_pending?(db, "pap"), "the killed slice reads pending — the next sync heals it"
    db.disconnect
    refute File.exist?("#{@fulltext_path}-wal") && File.size("#{@fulltext_path}-wal").positive?,
           "the WAL was truncated"
  end

  def test_a_stopped_watcher_leaves_the_writer_and_the_index_alone
    @writer = spawn_stuck_writer
    seed_killed_bulk_state(@writer)
    w = watcher(writer_pid: @writer, deadline: 30)
    @watcher_pid = w.start!
    w.stop!
    @watcher_pid = nil

    assert Watcher.alive?(@writer), "a clean stop never touches the writer"
    db = Nabu::Store.connect_fulltext(@fulltext_path, readonly: true)
    assert_equal 0, db[:passages_fts_config].where(k: "deletemerge").get(:v), "no hygiene on a clean stop"
    db.disconnect
  end

  def test_supervise_runs_the_block_under_a_watcher_and_stops_it
    beat = nil
    result = Watcher.supervise(label: "index refresh pap", fulltext_path: @fulltext_path,
                               heartbeat_path: @heartbeat, deadline: nil, log_path: @log) do |hook|
      hook.call(Nabu::ProgressReporter.new).stage("index slice: pap")
      beat = File.read(@heartbeat)
      :done
    end

    assert_equal :done, result
    assert_match(/stage index slice: pap/, beat, "the tee fed the heartbeat while the block ran")
    refute File.exist?(@heartbeat), "a clean finish removes the heartbeat file"
    refute File.exist?(@log), "a clean stop says nothing"
  end

  def test_a_writer_that_dies_on_its_own_still_gets_the_hygiene
    @writer = fork do
      sleep 0.3
      exit!(1)
    end
    seed_killed_bulk_state(@writer)
    @watcher_pid = watcher(writer_pid: @writer, deadline: nil, slug: "pap").start!
    Process.wait(@writer)
    @writer = nil
    Process.wait(@watcher_pid)
    @watcher_pid = nil

    assert_match(/writer \(pid \d+\) died without a clean finish/, File.read(@log))
    db = Nabu::Store.connect_fulltext(@fulltext_path, readonly: true)
    assert_equal 10, db[:passages_fts_config].where(k: "deletemerge").get(:v)
    db.disconnect
  end
end
