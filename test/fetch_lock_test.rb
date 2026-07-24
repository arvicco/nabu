# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::FetchLock (P44-i1c) — the per-source fetch lock that makes two nabu
# processes syncing the SAME source fail fast instead of racing on
# canonical/<slug> and its .partial staging (the glaux incident).
#
# Real concurrency: a held lock is proven with a genuine second process
# (Process.fork), synchronized over a pipe. flock is bound to the open file
# description, so the child's exclusive lock excludes the parent's non-blocking
# acquire; and the kernel drops the lock on the holder's death (even SIGKILL),
# which is how release-on-exit is tested WITHOUT any cleanup code running.
class FetchLockTest < Minitest::Test
  # --- held → second acquire fails fast with the named error ---------------

  def test_second_acquire_fails_fast_with_named_error
    Dir.mktmpdir("nabu-lock") do |canonical|
      pid, ready = fork_holder(canonical, "glaux")
      begin
        assert_equal "locked", ready.read(6), "child must acquire the lock first"

        ran = false
        err = assert_raises(Nabu::FetchLock::AlreadyHeld) do
          Nabu::FetchLock.hold(canonical_dir: canonical, slug: "glaux") { ran = true }
        end
        refute ran, "the guarded block must not run when the lock is held"
        assert_equal "glaux", err.slug
        assert_includes err.message, "glaux"
        assert_match(/pid #{pid}\b/, err.message, "names the holder's pid when knowable")
      ensure
        stop_holder(pid)
      end
    end
  end

  # A different slug is a different lock file — never blocked by a held sibling.
  def test_distinct_slugs_do_not_block_each_other
    Dir.mktmpdir("nabu-lock") do |canonical|
      pid, ready = fork_holder(canonical, "glaux")
      begin
        assert_equal "locked", ready.read(6)
        ran = false
        Nabu::FetchLock.hold(canonical_dir: canonical, slug: "lila") { ran = true }
        assert ran, "a different source's lock must be independently acquirable"
      ensure
        stop_holder(pid)
      end
    end
  end

  # --- release on exit (crash-safe by construction) ------------------------

  def test_lock_released_when_holder_process_is_killed
    Dir.mktmpdir("nabu-lock") do |canonical|
      # SIGKILL cannot run the ensure release — only the kernel frees the flock
      # on process death. A fresh acquire afterwards must succeed, proving no
      # stale-lock cleanup is needed.
      pid, ready = fork_holder(canonical, "glaux")
      assert_equal "locked", ready.read(6)
      Process.kill("KILL", pid)
      Process.wait(pid)

      ran = false
      Nabu::FetchLock.hold(canonical_dir: canonical, slug: "glaux") { ran = true }
      assert ran, "kernel released the flock on the holder's death"
    end
  end

  # --- normal release frees the lock for the next in-process acquire --------

  def test_hold_releases_after_the_block_returns
    Dir.mktmpdir("nabu-lock") do |canonical|
      Nabu::FetchLock.hold(canonical_dir: canonical, slug: "glaux") { :done }
      ran = false
      Nabu::FetchLock.hold(canonical_dir: canonical, slug: "glaux") { ran = true }
      assert ran
    end
  end

  # A raising block still releases the lock (ensure), so the source is not
  # wedged after one failed fetch.
  def test_hold_releases_even_when_the_block_raises
    Dir.mktmpdir("nabu-lock") do |canonical|
      assert_raises(RuntimeError) do
        Nabu::FetchLock.hold(canonical_dir: canonical, slug: "glaux") { raise "fetch boom" }
      end
      ran = false
      Nabu::FetchLock.hold(canonical_dir: canonical, slug: "glaux") { ran = true }
      assert ran
    end
  end

  private

  # Fork a child that acquires the fetch lock for +slug+ and holds it until
  # killed, signalling "locked" over a pipe once the lock is in hand. Returns
  # [pid, read_end]; the parent reads "locked" to synchronize, then stops it.
  def fork_holder(canonical, slug)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      Nabu::FetchLock.hold(canonical_dir: canonical, slug: slug) do
        writer.write("locked")
        writer.flush
        sleep 30 # parent kills us out of here
      end
    end
    writer.close
    [pid, reader]
  end

  def stop_holder(pid)
    return unless pid

    begin
      Process.kill("KILL", pid)
    rescue Errno::ESRCH
      # already gone
    end
    begin
      Process.wait(pid)
    rescue Errno::ECHILD
      nil
    end
  end
end
