# frozen_string_literal: true

require "fileutils"

module Nabu
  # A per-source acquisition lock guarding the FETCH phase — the window where a
  # sync mutates the canonical tree under canonical/<slug>/ (sweep stale
  # staging, clone into a .partial sibling, rename into place, ff-merge the
  # attic). Scoped to fetch and nothing else (see below).
  #
  # == Why (the glaux races, live incident 2026-07-24)
  #
  # P44-i1 made a single sync ATOMIC against INTERRUPTS (clone into a .partial
  # staging sibling, then one rename), but two nabu processes fetching the SAME
  # source still raced on canonical/<slug> and its .partial staging: one
  # process's stale-staging sweep / rename destroyed the other's in-flight
  # clone, and the failure surfaced only as an opaque `git exit 128`. Atomicity
  # protects against interrupts, NOT against concurrency. This lock adds the
  # missing mutual exclusion.
  #
  # == The lock file location
  #
  # An exclusive flock on canonical/.locks/<slug>.lock — a sibling of the
  # source dirs, deliberately NOT inside canonical/<slug> (which the fetch
  # itself wipes/renames, and which would carry its own lock down with it). The
  # .locks/ dir is not a source slug, so discover/rebuild never walk it.
  #
  # == Fail fast, never queue
  #
  # Acquisition is NON-BLOCKING (LOCK_NB): if another process already holds the
  # lock we raise AlreadyHeld at once — naming the slug and the holder's pid
  # when knowable — rather than blocking in silence. An operator staring at two
  # terminals must learn about the conflict immediately, so they can wait for
  # the running sync or stop it, not watch a second terminal hang.
  #
  # == Lifecycle & crash-safety
  #
  # The lock is held only across the fetch phase: ::hold acquires, yields, then
  # releases by closing the fd (in an ensure, so a raising fetch still frees
  # it). flock is advisory and bound to the OPEN FILE DESCRIPTION — the kernel
  # drops it when the fd closes OR the holding process exits, by ANY means
  # including SIGKILL. So a crashed or kill -9'd holder leaves NO stale lock and
  # needs NO cleanup logic: crash-safety is by construction. The .lock file
  # itself may linger between runs (harmless — it is a pure flock handle whose
  # only content is the last holder's pid for the error message; it is never
  # state a rebuild reads, and db = f(canonical) does not depend on it).
  #
  # == Scope: the FETCH phase ONLY
  #
  # This lock wraps the SyncRunner fetch step and nothing else. --parse-only
  # never enters the fetch phase (Adapter#fetch is not called — no canonical
  # tree mutation) and is therefore NEVER blocked by a held lock; it may reindex
  # concurrently with another process's fetch. `nabu rebuild` re-derives from
  # the already-fetched tree and does not fetch either. Serializing the
  # canonical-tree mutation window is the lock's whole job.
  class FetchLock
    LOCKS_DIRNAME = ".locks"

    # Raised when another process already holds the source's fetch lock. Fails
    # the sync fast (the acquire is non-blocking) so the operator sees the
    # conflict at once rather than watching a second terminal queue silently.
    class AlreadyHeld < Nabu::Error
      # The slug whose lock is held — so callers can report without re-parsing
      # the message.
      attr_reader :slug

      def initialize(slug, holder_pid)
        @slug = slug
        who = holder_pid ? " (pid #{holder_pid})" : ""
        super("another nabu process is syncing #{slug}#{who} — wait for it or stop it")
      end
    end

    # Run the block holding the exclusive fetch lock for +slug+, rooted at
    # +canonical_dir+. Fails fast with AlreadyHeld if the lock is held. Releases
    # on block exit — normal return OR raise — by closing the fd; the kernel
    # also releases on process exit, so a crash needs no cleanup.
    def self.hold(canonical_dir:, slug:, &)
      new(canonical_dir: canonical_dir, slug: slug).hold(&)
    end

    def initialize(canonical_dir:, slug:)
      @canonical_dir = canonical_dir
      @slug = slug
    end

    def hold
      file = acquire!
      begin
        yield
      ensure
        file.flock(File::LOCK_UN)
        file.close
      end
    end

    private

    # Non-blocking exclusive flock. Returns the held file on success; raises
    # AlreadyHeld (reading the current holder's pid best-effort) when another
    # open file description already holds it.
    def acquire!
      FileUtils.mkdir_p(locks_dir)
      # NOT the block form: the fd IS the lock handle and must outlive this
      # method — the lock lives as long as the fd is open (hold's ensure closes
      # it, and the kernel frees it on process exit).
      file = File.open(lock_path, File::RDWR | File::CREAT, 0o644) # rubocop:disable Style/FileOpen
      if file.flock(File::LOCK_EX | File::LOCK_NB)
        stamp_pid(file)
        file
      else
        pid = read_pid(file)
        file.close
        raise AlreadyHeld.new(@slug, pid)
      end
    end

    # Record our pid for the next process's error message. Written under the
    # held lock, so a reader either sees the previous holder's pid or ours,
    # never a torn value that matters (the pid is advisory — "if knowable").
    def stamp_pid(file)
      file.truncate(0)
      file.rewind
      file.write(Process.pid.to_s)
      file.flush
    end

    # The holder's pid from the lock file, nil when absent/unreadable — the
    # error message degrades to "another nabu process" without it.
    def read_pid(file)
      pid = file.read.to_s.strip
      pid.empty? ? nil : pid
    end

    def locks_dir = File.join(@canonical_dir, LOCKS_DIRNAME)

    def lock_path = File.join(locks_dir, "#{@slug}.lock")
  end
end
