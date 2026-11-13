# frozen_string_literal: true

require "fileutils"

module Nabu
  # The CATALOG WRITE WINDOW lock — a process-level mutual exclusion around
  # the stretch of a sync (or an `index refresh`) that writes the catalog and
  # the fulltext index: the load, the post-load index slice and lane
  # refreshes. Fetch and parse-free work outside that window stay fully
  # parallel; only the writers queue. Sibling of FetchLock in style and
  # mechanics (flock on a pure handle file).
  #
  # == Why (the parallel-sync collision, 2026-11-13)
  #
  # Two syncs of DIFFERENT sources ran concurrently by design; one source's
  # FTS shadow build died with "catalog.sqlite3 is locked by another process"
  # while the other's load held a long transaction. Under WAL, SQLite's
  # busy_timeout (Store::BUSY_TIMEOUT_MS) is the only writer-vs-writer
  # arbitration, and a writer that waits out another's LONG transaction dies
  # with a BusyException, taking its whole sync down. Parallel syncs across
  # sources are the standard shape now, so the writers queue here instead —
  # at the application level, before either opens its transaction. The
  # busy_timeout stays untouched as the inner backstop.
  #
  # == Queue, never fail (the inverse of FetchLock)
  #
  # FetchLock fails fast because two fetches of the SAME source are an
  # operator mistake. Two writers of different sources are the designed
  # shape, so acquisition BLOCKS: a poll loop on a non-blocking flock that,
  # while waiting, announces who holds the window ("catalog write window:
  # waiting on <slug>'s writer (pid N, held Ns)") at a sane interval — a
  # queued writer is visible, never mysterious. No timeout by default;
  # NABU_CATALOG_LOCK_TIMEOUT_S (seconds) bounds the wait when set (raising
  # Timeout), which tests and unattended tooling may use.
  #
  # == Crash-safety by construction
  #
  # flock is bound to the open file description: the kernel drops it when the
  # fd closes OR the holder dies by any means, SIGKILL included. A crashed
  # holder therefore never deadlocks the queue and needs no cleanup — which is
  # why this is flock and not a sentinel file. The holder's "slug pid
  # started-at" content written into the file is COSMETIC ONLY (it names the
  # holder in the waiting line); a stale value left by a dead holder is never
  # read as lock state.
  #
  # == Location
  #
  # db/catalog.write-lock, beside the catalog it guards. db/ is derived, and
  # so is this handle file: a rebuild may drop it and the next writer
  # recreates it.
  #
  # == Re-entrancy
  #
  # flock contends between DIFFERENT open file descriptions even inside one
  # process, so a nested acquire on the same thread would self-deadlock. The
  # lock is re-entrant per thread (a depth count keyed by the lock path);
  # distinct threads contend like distinct processes.
  class CatalogWriteLock
    FILENAME = "catalog.write-lock"
    # const: poll period of the blocking acquire (seconds) — short against
    # any real load window, long enough to cost nothing while queued
    POLL_S = 0.25
    # const: how often a queued writer re-announces its wait (seconds); the
    # first contention announces at once
    ANNOUNCE_EVERY_S = 30
    TIMEOUT_ENV = "NABU_CATALOG_LOCK_TIMEOUT_S"

    # Raised only when a wait bound is configured (TIMEOUT_ENV or timeout:)
    # and runs out — the default is to queue indefinitely.
    class Timeout < Nabu::Error; end

    # A held window; #release frees it (idempotent).
    class Handle
      def initialize(lock, file)
        @lock = lock
        @file = file
      end

      def release
        return if @released

        @released = true
        @lock.send(:release_file, @file)
      end
    end

    # Run the block inside the catalog write window for +slug+ (the lock file
    # under +db_dir+), queueing behind any current holder.
    def self.hold(db_dir:, slug:, announce: nil, **, &)
      new(db_dir: db_dir, slug: slug, announce: announce, **).hold(&)
    end

    # Acquire without a block (the sync path spans two blocks); the caller
    # releases the returned Handle in an ensure.
    def self.acquire(db_dir:, slug:, announce: nil, **)
      new(db_dir: db_dir, slug: slug, announce: announce, **).acquire
    end

    def initialize(db_dir:, slug:, announce: nil, poll: POLL_S, announce_every: ANNOUNCE_EVERY_S,
                   timeout: env_timeout, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @db_dir = db_dir
      @slug = slug
      @announce = announce || ->(line) { warn(line) }
      @poll = poll
      @announce_every = announce_every
      @timeout = timeout
      @clock = clock
    end

    def hold
      handle = acquire
      begin
        yield
      ensure
        handle.release
      end
    end

    def acquire
      depths = (Thread.current[:nabu_catalog_write_windows] ||= Hash.new(0))
      if depths[lock_path].positive?
        depths[lock_path] += 1
        return Handle.new(self, nil)
      end

      file = wait_for_lock
      depths[lock_path] = 1
      Handle.new(self, file)
    end

    def lock_path = File.join(@db_dir, FILENAME)

    private

    def wait_for_lock
      FileUtils.mkdir_p(@db_dir)
      # NOT the block form: the fd IS the lock handle and must outlive this
      # method (released by Handle#release, or by the kernel on exit).
      file = File.open(lock_path, File::RDWR | File::CREAT, 0o644) # rubocop:disable Style/FileOpen
      started = @clock.call
      last_announce = nil
      until file.flock(File::LOCK_EX | File::LOCK_NB)
        now = @clock.call
        if @timeout && now - started >= @timeout
          file.close
          raise Timeout, "catalog write window: gave up after #{@timeout}s waiting on #{holder_phrase}"
        end
        if last_announce.nil? || now - last_announce >= @announce_every
          @announce.call("catalog write window: #{@slug} waiting on #{holder_phrase}")
          last_announce = now
        end
        sleep @poll
      end
      # A wait that was announced announces its end too: the operator sees
      # the queue drain, and the index watcher's paused deadline clock
      # (which reads the waiting line in the heartbeat) resumes at once.
      unless last_announce.nil?
        @announce.call("catalog write window: #{@slug} acquired after #{(@clock.call - started).round}s")
      end
      stamp(file)
      file
    end

    def release_file(file)
      depths = Thread.current[:nabu_catalog_write_windows]
      depths[lock_path] -= 1 if depths && depths[lock_path].positive?
      return if file.nil? # a re-entrant inner handle — the outer one owns the fd

      file.flock(File::LOCK_UN)
      file.close
    end

    # Record "slug pid epoch" for a queued writer's announcement. Cosmetic:
    # read back only to name the holder, never as lock state.
    def stamp(file)
      file.truncate(0)
      file.rewind
      file.write("#{@slug} #{Process.pid} #{Time.now.to_i}")
      file.flush
    end

    # "<slug>'s writer (pid N, held Ns)" from the holder's stamp, degrading to
    # "another writer" when the stamp is absent or unreadable.
    def holder_phrase
      slug, pid, since = File.read(lock_path).to_s.split
      return "another writer" if slug.nil? || pid.nil?

      held = since ? ", held #{[Time.now.to_i - since.to_i, 0].max}s" : ""
      "#{slug}'s writer (pid #{pid}#{held})"
    rescue SystemCallError
      "another writer"
    end

    def env_timeout
      value = ENV.fetch(TIMEOUT_ENV, nil)
      value.nil? || value.strip.empty? ? nil : Float(value)
    end
  end
end
