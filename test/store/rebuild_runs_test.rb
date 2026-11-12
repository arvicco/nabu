# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::RebuildRuns — every rebuild (either flavor) is a
  # machine-visible run: a ledger row at START (mode, git sha, planned
  # stages, pid) whose completed_at is the run's LAST act. A killed run
  # leaves its row incomplete, and the readers say so (the 2026-11-09
  # rebuild died in its corpus reindex and left no trace a tool could read).
  class RebuildRunsTest < Minitest::Test
    include StoreTestDB

    RebuildRuns = Nabu::Store::RebuildRuns

    def setup
      @ledger = ledger_test_db
    end

    def dead_pid
      pid = Process.spawn("true")
      Process.wait(pid)
      pid
    end

    def start!(pid: Process.pid, mode: "full")
      RebuildRuns.start!(@ledger, mode: mode, planned_stages: %w[load fts_lemma cjk], git_sha: "abc123",
                                  pid: pid, at: Time.utc(2026, 11, 12, 1, 2, 3))
    end

    def test_start_records_the_run_before_any_work
      id = start!
      row = @ledger[RebuildRuns::TABLE].where(id: id).first
      assert_equal "full", row[:mode]
      assert_equal "abc123", row[:git_sha]
      assert_equal %w[load fts_lemma cjk], JSON.parse(row[:planned_stages])
      assert_equal Process.pid, row[:pid]
      assert_nil row[:completed_at], "incomplete until the run's last act"
    end

    def test_a_completed_run_needs_no_attention
      RebuildRuns.complete!(@ledger, start!)
      assert_nil RebuildRuns.attention(@ledger)
    end

    def test_a_dead_unfinished_run_reads_loudly
      start!(pid: dead_pid)
      line = RebuildRuns.attention(@ledger)
      assert_match(/rebuild \(full\) started 2026-11-12 01:02:03 UTC, never completed — the index may be partial/,
                   line)
    end

    def test_a_live_unfinished_run_reads_as_running_not_as_damage
      start!
      assert_match(/rebuild \(full\) RUNNING since 2026-11-12 01:02:03 UTC \(pid #{Process.pid}\)/,
                   RebuildRuns.attention(@ledger))
    end

    def test_a_failed_run_names_its_error
      RebuildRuns.fail!(@ledger, start!(pid: dead_pid), RuntimeError.new("index boom"))
      assert_match(/never completed \(failed: index boom\)/, RebuildRuns.attention(@ledger))
    end

    def test_only_the_latest_run_speaks
      start!(pid: dead_pid)
      RebuildRuns.complete!(@ledger, start!(mode: "incremental"))
      assert_nil RebuildRuns.attention(@ledger), "a later completed run supersedes the dead one"
    end

    def test_the_planned_stage_set_can_be_narrowed_after_the_sweep
      id = start!(mode: "incremental")
      RebuildRuns.plan!(@ledger, id, %w[replay:alpha index])
      assert_equal %w[replay:alpha index], JSON.parse(@ledger[RebuildRuns::TABLE].where(id: id).get(:planned_stages))
    end

    def test_a_ledger_without_the_table_reads_as_nothing_to_say
      assert_nil RebuildRuns.attention(nil)
      bare = Sequel.sqlite
      assert_nil RebuildRuns.attention(bare)
    ensure
      bare&.disconnect
    end
  end
end
