# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Store.assert_writable! (P62 rider — the owner's sync-vs-apply collision):
# a fast BEGIN IMMEDIATE probe on its own throwaway connection, so a write
# command fails in a quarter second with ONE human sentence instead of
# loading for minutes and dying in a BusyException stack when another
# process (a sync, a rebuild, an apply chain) holds the write lock.
class WritableProbeTest < Minitest::Test
  def with_db_path
    Dir.mktmpdir do |dir|
      path = File.join(dir, "catalog.sqlite3")
      db = Nabu::Store.connect(path)
      Nabu::Store.migrate!(db)
      begin
        yield path, db
      ensure
        db.disconnect
      end
    end
  end

  def test_a_free_catalog_probes_clean
    with_db_path do |path, _db|
      assert_nil Nabu::Store.assert_writable!(path), "no writer — the probe passes silently"
    end
  end

  def test_a_write_locked_catalog_raises_one_clean_nabu_error
    with_db_path do |path, db|
      db.run("BEGIN IMMEDIATE")
      begin
        error = assert_raises(Nabu::CatalogBusyError) { Nabu::Store.assert_writable!(path) }
        assert_match(/locked by another process/, error.message)
        assert_match(/wait for it/i, error.message, "the message says what to DO, not just what broke")
        assert_kind_of Nabu::Error, error, "CLI rescues Nabu::Error into a clean one-line exit"
      ensure
        db.run("ROLLBACK")
      end
    end
  end

  def test_the_probe_neither_blocks_nor_holds_the_lock
    with_db_path do |path, db|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Nabu::Store.assert_writable!(path)
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2,
                      "the probe uses its own short timeout, never the 10 s write timeout"
      db.run("BEGIN IMMEDIATE") # the probe released its lock — this must not raise
      db.run("ROLLBACK")
    end
  end

  def test_a_missing_file_is_not_a_busy_error
    assert_nil Nabu::Store.assert_writable!("/nonexistent/dir/catalog.sqlite3"),
               "absence is the caller's concern (open_or_create handles it) — never a busy lie"
  end
end
