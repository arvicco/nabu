# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "rbconfig"

# Lock-tolerant SQLite (P17-7): journal_mode=WAL + busy_timeout on every
# connect path. File-backed tmp dbs throughout — in-memory databases are
# per-connection and can never contend, so nothing here would prove anything
# against "sqlite::memory:".
class LockToleranceTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("nabu-locks")
    @dbs = []
  end

  def teardown
    @dbs.each(&:disconnect)
    FileUtils.remove_entry(@dir)
  end

  # -- the owner crash, reproduced -----------------------------------------
  # A reader holding an open read transaction while the writer commits.
  # Pre-P17-7 (journal_mode=delete) the writer's COMMIT needed the EXCLUSIVE
  # lock against the reader's SHARED one → SQLite3::BusyException once the
  # busy wait ran out. Under WAL the writer appends and the reader keeps its
  # snapshot; neither waits.
  def test_writer_commits_while_a_reader_holds_an_open_read_transaction
    path = db_path("catalog")
    writer = connect { Nabu::Store.connect(path) }
    writer.create_table(:t) { Integer :n }
    writer[:t].insert(n: 1)

    reader = connect { Nabu::Store.connect(path, readonly: true) }
    reader.transaction do
      assert_equal 1, reader[:t].count # takes the read snapshot
      writer.transaction { writer[:t].insert(n: 2) } # crashed pre-P17-7
      assert_equal 1, reader[:t].count, "the open reader keeps its snapshot"
    end
    assert_equal 2, reader[:t].count, "a fresh read sees the commit"
  end

  # -- busy_timeout, exercised for real ------------------------------------
  # Writer-vs-writer is what the timeout still guards under WAL. Contention
  # must be CROSS-PROCESS (production reality: owner CLI vs agents vs MCP
  # server; and sqlite3's C-level busy handler blocks the GVL, so two writer
  # threads in ONE process would burn the timeout instead of handing over).
  HOLDER = <<~RUBY
    require "sqlite3"
    db = SQLite3::Database.new(ARGV[0])
    db.transaction(:immediate)
    db.execute("INSERT INTO t (n) VALUES (1)")
    puts "held"
    $stdout.flush
    sleep 0.4
    db.commit
  RUBY

  def test_a_writer_waits_out_another_process_transient_write_lock
    path = db_path("contended")
    db = connect { Nabu::Store.connect(path) }
    db.create_table(:t) { Integer :n }
    db.disconnect # no open handle may cross into the child

    holder = IO.popen([RbConfig.ruby, "-e", HOLDER, path])
    assert_equal "held", holder.gets&.strip, "the holder must acquire its write lock first"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    db[:t].insert(n: 2) # raised SQLite3::BusyException without a busy wait
    waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator waited, :>=, 0.1, "the insert must have WAITED out the held lock, not raced it"
    assert_equal 2, db[:t].count
  ensure
    holder&.close
  end

  # -- regression pins: every connect path, readonly and rw -----------------

  def test_busy_timeout_is_set_on_every_connect_path
    each_connect_path do |name, db|
      assert_equal Nabu::Store::BUSY_TIMEOUT_MS,
                   db.fetch("PRAGMA busy_timeout").single_value,
                   "busy_timeout missing on #{name}"
    end
  end

  def test_journal_mode_is_wal_on_every_connect_path
    each_connect_path do |name, db|
      assert_equal "wal", db.fetch("PRAGMA journal_mode").single_value,
                   "journal_mode not wal on #{name}"
    end
  end

  # An existing pre-WAL (rollback-journal) db self-heals on its first
  # read-write connect — the pragma persists in the file, so no migration.
  def test_a_rollback_journal_db_flips_to_wal_on_connect
    path = db_path("legacy")
    legacy = Sequel.connect("sqlite://#{path}")
    legacy.create_table(:t) { Integer :n }
    assert_equal "delete", legacy.fetch("PRAGMA journal_mode").single_value
    legacy.disconnect

    db = connect { Nabu::Store.connect(path) }
    assert_equal "wal", db.fetch("PRAGMA journal_mode").single_value
    db.disconnect

    readonly = connect { Nabu::Store.connect(path, readonly: true) }
    assert_equal "wal", readonly.fetch("PRAGMA journal_mode").single_value, "WAL persists in the file"
  end

  private

  # Every production connect path, rw before readonly so the rw connect
  # creates the file (and flips it to WAL) for the readonly one. Ledger and
  # LinksJournal delegate to Store.connect — pinned here anyway so a future
  # bespoke connect cannot silently drop the policy.
  def each_connect_path
    catalog = db_path("pin-catalog")
    fulltext = db_path("pin-fulltext")
    ledger = db_path("pin-history")
    links = db_path("pin-links")
    {
      "catalog rw" => -> { Nabu::Store.connect(catalog) },
      "catalog readonly" => -> { Nabu::Store.connect(catalog, readonly: true) },
      "fulltext rw" => -> { Nabu::Store.connect_fulltext(fulltext) },
      "fulltext readonly" => -> { Nabu::Store.connect_fulltext(fulltext, readonly: true) },
      "ledger rw" => -> { Nabu::Store::Ledger.connect(ledger) },
      "links rw" => -> { Nabu::Store::LinksJournal.connect(links) },
      "links readonly" => -> { Nabu::Store::LinksJournal.connect(links, readonly: true) }
    }.each { |name, open| yield name, connect(&open) }
  end

  def connect
    db = yield
    @dbs << db
    db
  end

  def db_path(name) = File.join(@dir, "#{name}.sqlite3")
end
