# frozen_string_literal: true

module Nabu
  # The lazy, memoizing, read-only connection opener (P8-2 origin, Q65
  # extraction): resolves one database slot per call for long-lived
  # servers (`nabu mcp`). On every call: absent file → nil (the caller
  # renders its "no corpus" state); present file → an open handle,
  # cached across calls so a long session does not churn descriptors;
  # identity change (a rebuild deletes + recreates the file → new
  # inode) → the stale handle is disconnected and a fresh one opened.
  #
  # == The idle gap (Q65 — the P93 first-rebuild disk incident)
  #
  # Per-call re-stat is enough for DATA freshness, but an IDLE session
  # makes no calls — its cached handle held the deleted pre-rebuild
  # catalog's 118 GB on disk for days (`lsof +L1`, link-count 0).
  # vacate_stale! is the other half: disconnect a handle whose file
  # identity changed WITHOUT reopening (reopen stays lazy, on the next
  # real call), and ::watch runs that sweep on a timer so the disk
  # frees within the interval of a rebuild, tool calls or none.
  class ReadonlyOpener
    # Seconds between watchdog sweeps — frees a rebuilt file's disk
    # within about a minute on an idle server.
    # const: sweep cadence, not a corpus claim
    WATCH_INTERVAL = 60

    def initialize(path, &open)
      @path = path
      @open = open
      @handle = nil
      @identity = nil
      @mutex = Mutex.new
    end

    # The per-call resolve (the MCP::Tools slot contract via #to_proc).
    def call
      @mutex.synchronize do
        current = file_identity
        if current.nil?
          drop
        elsif current != @identity
          drop
          @handle = @open.call
          @identity = current
        end
        @handle
      end
    end

    # Disconnect a stale handle without reopening — the idle server's
    # disk release. A healthy handle (identity unchanged) is untouched.
    def vacate_stale!
      @mutex.synchronize do
        drop if file_identity != @identity
      end
    end

    # MCP::Tools resolves Proc slots per tool call (an explicit Proc
    # check there — Sequel::Database has its own #call).
    def to_proc
      -> { call }
    end

    # The watchdog: one daemon thread sweeping every opener each
    # +interval+ seconds. Returns the thread (callers own its lifetime;
    # the mcp entrypoint lets it die with the process).
    def self.watch(openers, interval: WATCH_INTERVAL)
      thread = Thread.new do
        loop do
          sleep interval
          openers.each(&:vacate_stale!)
        end
      end
      thread.abort_on_exception = false
      thread
    end

    private

    def drop
      @handle&.disconnect
      @handle = nil
      @identity = nil
    end

    # (device, inode) — a file replaced in place (delete + recreate)
    # changes inode, which is how a rebuild is noticed. nil when absent.
    def file_identity
      return nil unless File.exist?(@path)

      stat = File.stat(@path)
      [stat.dev, stat.ino]
    end
  end
end
