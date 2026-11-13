# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::CatalogWriteLock — the catalog write-window lock that makes
# concurrent syncs of DIFFERENT sources queue their catalog/index writes
# instead of dying on SQLite's busy_timeout behind another writer's long
# transaction (the parallel-sync collision, 2026-11-13).
#
# Real concurrency throughout: real flock, real threads (distinct open file
# descriptions contend inside one process), real fork + SIGKILL for the
# crashed-holder case. Only the announce sink is a seam.
class CatalogWriteLockTest < Minitest::Test
  # Writer B queues behind A's window, announces who it waits on, and
  # completes once A releases — against one on-disk catalog.
  def test_second_writer_blocks_until_first_releases_then_completes
    Dir.mktmpdir("nabu-cwl") do |db_dir|
      catalog = Sequel.sqlite(File.join(db_dir, "catalog.sqlite3"))
      catalog.create_table(:rows) { String :who }
      events = Queue.new
      lines = Queue.new
      a_in = Queue.new
      a_go = Queue.new

      writer_a = Thread.new do
        Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "alpha") do
          a_in << :held
          a_go.pop
          catalog[:rows].insert(who: "alpha")
          events << :a_done
        end
      end
      a_in.pop

      writer_b = Thread.new do
        Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "beta", poll: 0.01,
                                    announce: ->(line) { lines << line }) do
          events << :b_in
          catalog[:rows].insert(who: "beta")
        end
      end

      announced = lines.pop # B is queued and said so
      assert_match(/beta waiting on alpha's writer \(pid #{Process.pid}, held \d+s\)/, announced)
      sleep 0.05
      assert events.empty?, "B must not enter the window while A holds it"

      a_go << :go
      [writer_a, writer_b].each { |t| t.join(5) }
      assert_equal %i[a_done b_in], [events.pop, events.pop]
      assert_equal %w[alpha beta], catalog[:rows].map(:who)
    ensure
      catalog&.disconnect
    end
  end

  def test_queued_writer_reannounces_at_the_interval
    Dir.mktmpdir("nabu-cwl") do |db_dir|
      release = Queue.new
      held = Queue.new
      holder = Thread.new do
        Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "alpha") do
          held << true
          release.pop
        end
      end
      held.pop
      lines = Queue.new
      waiter = Thread.new do
        Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "beta", poll: 0.01, announce_every: 0.02,
                                    announce: ->(line) { lines << line }) { :ok }
      end
      3.times { lines.pop }
      release << true
      assert_equal :ok, waiter.value
      holder.join
    end
  end

  # A SIGKILLed holder runs no ensure; the kernel frees the flock, so the
  # next acquire succeeds — no deadlock, no cleanup.
  def test_killed_holder_does_not_deadlock_the_next_writer
    Dir.mktmpdir("nabu-cwl") do |db_dir|
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "alpha") do
          writer.write("locked")
          writer.flush
          sleep 30
        end
      end
      writer.close
      assert_equal "locked", reader.read(6)

      assert_raises(Nabu::CatalogWriteLock::Timeout) do
        Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "beta", poll: 0.01, timeout: 0.05,
                                    announce: ->(_) {}) { flunk "must not enter while held" }
      end

      Process.kill("KILL", pid)
      Process.wait(pid)
      ran = Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "beta", timeout: 1, announce: ->(_) {}) { :ran }
      assert_equal :ran, ran
    end
  end

  def test_reentrant_on_the_same_thread
    Dir.mktmpdir("nabu-cwl") do |db_dir|
      inner = Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "alpha") do
        Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "alpha", timeout: 0.1) { :inner }
      end
      assert_equal :inner, inner
      # fully released afterwards: another thread acquires at once
      assert_equal :next, Thread.new {
        Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "beta", timeout: 0.5) { :next }
      }.value
    end
  end

  def test_release_on_raise_and_handle_release_is_idempotent
    Dir.mktmpdir("nabu-cwl") do |db_dir|
      assert_raises(RuntimeError) { Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "a") { raise "boom" } }
      handle = Nabu::CatalogWriteLock.acquire(db_dir: db_dir, slug: "a", timeout: 0.5)
      handle.release
      handle.release
      other = Thread.new { Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "b", timeout: 0.5) { :ok } }
      assert_equal :ok, other.value
      assert_path_exists File.join(db_dir, Nabu::CatalogWriteLock::FILENAME)
    end
  end

  def test_timeout_env_bounds_the_wait
    Dir.mktmpdir("nabu-cwl") do |db_dir|
      ENV[Nabu::CatalogWriteLock::TIMEOUT_ENV] = "0.05"
      held = Queue.new
      release = Queue.new
      holder = Thread.new do
        Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "a") do
          held << 1
          release.pop
        end
      end
      held.pop
      err = assert_raises(Nabu::CatalogWriteLock::Timeout) do
        Nabu::CatalogWriteLock.hold(db_dir: db_dir, slug: "b", poll: 0.01, announce: ->(_) {}) { :never }
      end
      assert_match(/a's writer/, err.message)
      release << 1
      holder.join
    ensure
      ENV.delete(Nabu::CatalogWriteLock::TIMEOUT_ENV)
    end
  end
end
