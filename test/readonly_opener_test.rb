# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::ReadonlyOpener (Q65, the P93 disk incident's systemic fix): the
# lazy memoizing read-only opener extracted from the CLI's mcp plumbing,
# plus the piece the incident showed was missing — vacate_stale!, so an
# IDLE long-lived server releases a rebuilt file's disk (a deleted inode
# held open pins its bytes) without waiting for its next tool call.
class ReadonlyOpenerTest < Minitest::Test
  # A fake connection that records disconnects (the Sequel contract) and
  # HOLDS AN OPEN FD on its file — faithful to the incident (the stale
  # connection's descriptor is what pinned the deleted catalog), and
  # load-bearing on Linux: a freed inode is recycled by the very next
  # create, so without a holder the delete+recreate in these tests can
  # mint the SAME (dev, ino) and the identity check honestly sees no
  # change (caught by CI 2026-09-03; APFS mints monotonically and hid it).
  FakeDb = Struct.new(:path, :io, :disconnected) do
    def disconnect
      io.close unless io.closed?
      self.disconnected = true
    end
  end

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "catalog.sqlite3")
    @opened = []
  end

  def teardown
    @opened.each { |db| db.io.close unless db.io.closed? }
    FileUtils.remove_entry(@dir)
  end

  def opener
    @opener ||= Nabu::ReadonlyOpener.new(@path) do
      FakeDb.new(@path, File.open(@path, "r"), false).tap { |db| @opened << db }
    end
  end

  def test_absent_file_resolves_nil_and_opens_nothing
    assert_nil opener.call
    assert_empty @opened
  end

  def test_present_file_opens_once_and_memoizes
    File.write(@path, "db")
    first = opener.call
    second = opener.call
    assert_same first, second, "a healthy handle is cached across calls"
    assert_equal 1, @opened.size
  end

  def test_a_rebuild_reconnects_on_the_next_call
    File.write(@path, "db")
    stale = opener.call
    File.delete(@path)
    File.write(@path, "rebuilt") # delete + recreate = new inode
    fresh = opener.call
    refute_same stale, fresh, "an inode change must reopen"
    assert stale.disconnected, "the stale handle is disconnected, not leaked"
  end

  def test_deletion_resolves_nil_and_disconnects
    File.write(@path, "db")
    handle = opener.call
    File.delete(@path)
    assert_nil opener.call
    assert handle.disconnected
  end

  def test_vacate_stale_releases_a_rebuilt_file_without_a_call
    File.write(@path, "db")
    stale = opener.call
    File.delete(@path)
    File.write(@path, "rebuilt")
    opener.vacate_stale!
    assert stale.disconnected,
           "the incident: an idle server held the deleted 118 GB catalog — vacate must " \
           "disconnect without waiting for the next tool call"
    assert_equal 1, @opened.size, "vacate never eagerly reopens — reopen stays lazy"
    fresh = opener.call
    refute_same stale, fresh
  end

  def test_vacate_stale_leaves_a_healthy_handle_alone
    File.write(@path, "db")
    handle = opener.call
    opener.vacate_stale!
    refute handle.disconnected
    assert_same handle, opener.call
  end

  def test_to_proc_serves_the_tools_slot_contract
    File.write(@path, "db")
    slot = opener.to_proc
    assert_instance_of Proc, slot, "MCP::Tools resolves Proc slots per tool call"
    assert_same opener.call, slot.call
  end

  def test_watch_vacates_periodically
    File.write(@path, "db")
    stale = opener.call
    File.delete(@path)
    thread = Nabu::ReadonlyOpener.watch([opener], interval: 0.02)
    deadline = Time.now + 2
    sleep 0.02 until stale.disconnected || Time.now > deadline
    assert stale.disconnected, "the watchdog vacates an idle opener's stale handle"
  ensure
    thread&.kill
    thread&.join
  end
end
