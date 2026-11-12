# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Store
  # Nabu::Store::EngineIntents — the engine-config intent journal. Bulk
  # merge settings are persisted fts5 config: a writer killed between
  # applying deletemerge=0 and its ensure-restore leaves the index never
  # merging its tombstones (it happened twice on this box). The intent is
  # journaled BEFORE the settings apply, and the next read-write connect
  # replays the restore for any journaled writer whose process is gone.
  class EngineIntentsTest < Minitest::Test
    Intents = Nabu::Store::EngineIntents
    Indexer = Nabu::Store::Indexer

    def setup
      @dir = Dir.mktmpdir("nabu-intents")
      @path = File.join(@dir, "fulltext.sqlite3")
      db = Nabu::Store.connect_fulltext(@path)
      db.run(Indexer::CREATE_TABLE)
      db.disconnect
    end

    def teardown
      FileUtils.rm_rf(@dir)
    end

    def dead_pid
      pid = Process.spawn("true")
      Process.wait(pid)
      pid
    end

    def deletemerge(db)
      db[:passages_fts_config].where(k: "deletemerge").get(:v)
    end

    # What a killed bulk write leaves behind: the intent journaled under
    # the writer's pid, the bulk setting applied, no restore ever run.
    def leave_a_killed_bulk_write(pid:)
      db = Nabu::Store.connect_fulltext(@path)
      Intents.journal!(db, table: Indexer::TABLE, restore: Indexer::DEFAULT_MERGE_SETTINGS, pid: pid)
      Indexer.apply_merge_settings(db, Indexer::TABLE, Indexer::BULK_MERGE_SETTINGS)
      assert_equal 0, deletemerge(db)
      db.disconnect
    end

    def test_the_next_read_write_connect_replays_a_dead_writers_restore
      leave_a_killed_bulk_write(pid: dead_pid)

      db = Nabu::Store.connect_fulltext(@path)
      assert_equal 10, deletemerge(db), "the journaled restore replayed on connect"
      assert_empty db[Intents::TABLE].all, "a replayed intent leaves the journal"
    ensure
      db&.disconnect
    end

    def test_a_live_writers_intent_is_left_alone
      leave_a_killed_bulk_write(pid: Process.pid)

      db = Nabu::Store.connect_fulltext(@path)
      assert_equal 0, deletemerge(db), "a writer still running keeps its bulk settings"
      assert_equal 1, db[Intents::TABLE].count
    ensure
      db&.disconnect
    end

    def test_a_read_only_connect_never_replays
      leave_a_killed_bulk_write(pid: dead_pid)

      db = Nabu::Store.connect_fulltext(@path, readonly: true)
      assert_equal 0, deletemerge(db)
      assert_equal 1, db[Intents::TABLE].count
    ensure
      db&.disconnect
    end

    def test_the_bulk_write_mode_journals_before_applying_and_clears_after
      db = Nabu::Store.connect_fulltext(@path)
      seen = nil
      Indexer.with_bulk_write_mode(db, [Indexer::TABLE]) do
        seen = db[Intents::TABLE].select_map(:fts_table)
        assert_equal 0, deletemerge(db)
      end
      assert_equal %w[passages_fts], seen, "journaled for the length of the bulk window"
      assert_empty db[Intents::TABLE].all, "cleared once the ensure restored the defaults"
      assert_equal 10, deletemerge(db)
    ensure
      db&.disconnect
    end

    # The real kill: a child process journals, applies, and dies by
    # SIGKILL inside the bulk window — no ensure arm runs at all.
    def test_a_sigkilled_bulk_window_is_restored_by_the_next_connect
      pid = fork do
        child = Nabu::Store.connect_fulltext(@path)
        Indexer.with_bulk_write_mode(child, [Indexer::TABLE]) { Process.kill(:KILL, Process.pid) }
      end
      Process.wait(pid)

      db = Nabu::Store.connect_fulltext(@path)
      assert_equal 10, deletemerge(db)
      assert_empty db[Intents::TABLE].all
    ensure
      db&.disconnect
    end
  end
end
