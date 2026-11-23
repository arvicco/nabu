# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "nabu/ops/db_snapshot"

# `rake "db:snapshot[TARGET_DIR]"` — an online, WAL-safe snapshot of every
# db/*.sqlite3 (VACUUM INTO, never a file copy: the store's WAL footgun),
# refusing a bad target and an in-progress rebuild.
class DbSnapshotTest < Minitest::Test
  S = Nabu::Ops::DbSnapshot

  def setup
    @tmp = Dir.mktmpdir("db-snapshot-test")
    @db_dir = File.join(@tmp, "db")
    @target = File.join(@tmp, "snap")
    FileUtils.mkdir_p([@db_dir, @target])
  end

  def teardown
    @writer&.disconnect
    FileUtils.rm_rf(@tmp)
  end

  # A WAL-mode db with a writer still connected: rows live in the -wal.
  def live_wal_db(name, rows:)
    @writer = Nabu::Store.connect(File.join(@db_dir, name))
    @writer.create_table(:t) { Integer :x }
    rows.times { |i| @writer[:t].insert(x: i) }
    @writer
  end

  def snapshot(target: @target, rebuild_check: -> {}, out: StringIO.new)
    S.new(db_dir: @db_dir, target: target, rebuild_check: rebuild_check, out: out).run!
  end

  def test_snapshots_every_db_file_consistently_while_a_writer_holds_the_wal
    live_wal_db("catalog.sqlite3", rows: 50)
    assert File.exist?(File.join(@db_dir, "catalog.sqlite3-wal")), "the rows sit in a live -wal"
    other = Nabu::Store.connect(File.join(@db_dir, "fulltext.sqlite3"))
    other.create_table(:u) { String :y }
    other[:u].insert(y: "a")
    other.disconnect

    out = StringIO.new
    result = snapshot(out: out)

    assert_equal %w[catalog.sqlite3 fulltext.sqlite3], result.entries.map(&:name)
    copy = Sequel.connect("sqlite://#{File.join(@target, 'catalog.sqlite3')}", readonly: true)
    assert_equal 50, copy[:t].count, "the snapshot carries the frames still in the -wal"
    assert_equal "ok", copy.fetch("PRAGMA integrity_check").single_value
    copy.disconnect
    refute File.exist?(File.join(@target, "catalog.sqlite3-wal")), "no sidecar travels with a snapshot"
    assert_match(/^  catalog\.sqlite3: \d+(\.\d)? [KM]?B in \d/, out.string)
    assert_match(/^SUMMARY db:snapshot — 2 file\(s\), .+ into #{Regexp.escape(@target)} in .+cache of derived state/,
                 out.string)
    assert_equal result.entries.sum(&:bytes), result.bytes
  end

  def test_refuses_a_missing_target
    live_wal_db("catalog.sqlite3", rows: 1)
    error = assert_raises(S::Refused) { snapshot(target: File.join(@tmp, "nope")) }
    assert_match(/does not exist/, error.message)
    assert_raises(S::Refused) { snapshot(target: "") }
  end

  def test_refuses_a_non_writable_target
    live_wal_db("catalog.sqlite3", rows: 1)
    File.chmod(0o500, @target)
    error = assert_raises(S::Refused) { snapshot }
    assert_match(/not writable/, error.message)
  ensure
    File.chmod(0o700, @target)
  end

  def test_refuses_the_db_dir_itself_and_an_occupied_target
    live_wal_db("catalog.sqlite3", rows: 1)
    assert_raises(S::Refused) { snapshot(target: @db_dir) }
    File.write(File.join(@target, "catalog.sqlite3"), "old")
    error = assert_raises(S::Refused) { snapshot }
    assert_match(/already holds catalog\.sqlite3/, error.message)
    assert_equal "old", File.read(File.join(@target, "catalog.sqlite3")), "a snapshot never overwrites"
  end

  def test_refuses_during_a_rebuild_and_writes_nothing
    live_wal_db("catalog.sqlite3", rows: 1)
    error = assert_raises(S::Refused) { snapshot(rebuild_check: -> { "rebuild (full) RUNNING since x (pid 9)" }) }
    assert_match(/rebuild is in progress — rebuild \(full\) RUNNING/, error.message)
    assert_empty Dir.children(@target)
  end

  def test_the_rebuild_probe_reads_the_process_table
    ps = "  123 ruby bin/nabu rebuild --incremental\n  124 ruby bin/nabu rebuild --dry-run\n"
    assert_match(/pid 123/, S.rebuild_in_progress(ledger: nil, ps_output: ps))
    assert_nil S.rebuild_in_progress(ledger: nil, ps_output: "  124 ruby bin/nabu rebuild --dry-run\n")
  end

  def test_human_sizes
    assert_equal "512 B", S.human(512)
    assert_equal "1.5 KB", S.human(1536)
    assert_equal "2.0 GB", S.human(2 * (1024**3))
  end
end
