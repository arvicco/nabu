# frozen_string_literal: true

require "fileutils"

require_relative "../../nabu"
require_relative "../duration_format"
require_relative "git_hooks"

module Nabu
  module Ops
    # `rake "db:snapshot[TARGET_DIR]"` — an owner-fired, ONLINE snapshot of
    # every db/*.sqlite3 into TARGET_DIR. The snapshot is a CACHE of
    # derived state (the derivability law: db/ is a pure function of the
    # three permanent folders, and `nabu rebuild` regenerates it); what it
    # buys is the hours a rebuild would cost, never data that exists
    # nowhere else.
    #
    # WAL-SAFE BY CONSTRUCTION — each file goes through Store.vacuum_into!
    # (VACUUM INTO over a read-only connect), never a file copy. The WAL
    # footgun the store's class doc records: `-wal`/`-shm` sidecars sit
    # beside every db while connections are open, the main file alone
    # lacks the frames still in the -wal, and "a main file restored next
    # to an outdated -wal would replay old frames over it" (Nabu::Store,
    # the WAL verdict). VACUUM INTO reads one consistent snapshot through
    # SQLite itself — sidecar frames included — while MCP readers and a
    # sync's writer carry on (WAL readers never block the writer).
    #
    # REFUSALS (Refused, nothing written): a missing or non-writable
    # target; a target that IS the db dir; a target already holding a
    # same-named file (a snapshot never overwrites — pick a fresh dir); a
    # rebuild in progress (the latest ledger rebuild row RUNNING with its
    # pid alive, or a live `nabu rebuild` in the process table — the same
    # probe as the commit hook's mid-rebuild hold, GitHooks): a rebuild
    # drops and recreates these files, so a snapshot mid-run is a
    # snapshot of a half-built index.
    #
    # RESTORE (documented, not automated): with nothing holding db/ open
    # (no sync, MCP server or rebuild — `lsof +D db` is empty), remove each
    # db's file AND its -wal/-shm sidecars (Store.drop_database_files!'s
    # rule: a copied-back main file beside a stale -wal is the trap above),
    # then copy the snapshot files back into db/. The first read-write
    # connect re-arms WAL. Stamp sanity: the derivation stamps live INSIDE
    # the catalog, so a restored catalog carries the stamps of its
    # snapshot moment — any code merged since reads dirty to
    # `nabu rebuild --incremental --dry-run` (the honest answer, never a
    # lie), and any sync landed after the snapshot is simply re-run
    # (`bin/nabu sync <slug> --parse-only`).
    class DbSnapshot
      include Nabu::DurationFormat

      class Refused < Nabu::Error; end

      Entry = Data.define(:name, :bytes, :seconds)
      Result = Data.define(:target, :entries, :seconds) do
        def bytes = entries.sum(&:bytes)
      end

      MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      # The reason a rebuild holds db/, or nil. +ledger+ is the history
      # ledger (nil = none on this box); +ps_output+ the `ps -Ao
      # pid=,command=` text.
      def self.rebuild_in_progress(ledger:, ps_output:)
        line = ledger && Store::RebuildRuns.attention(ledger)
        return line if line&.include?("RUNNING")

        pid, command = GitHooks.rebuild_processes(ps_output).first
        pid && "a rebuild process is running (pid #{pid}: #{command[0, 80]})"
      end

      def initialize(db_dir:, target:, rebuild_check: -> {}, out: $stdout, clock: MONOTONIC)
        @db_dir = db_dir
        @target = target.to_s.strip
        @rebuild_check = rebuild_check
        @out = out
        @clock = clock
      end

      def run!
        files = preflight!
        started = @clock.call
        entries = files.map { |path| snapshot(path) }
        result = Result.new(target: @target, entries: entries, seconds: @clock.call - started)
        @out.puts("SUMMARY db:snapshot — #{entries.size} file(s), #{human(result.bytes)} into #{@target} " \
                  "in #{format_duration(result.seconds)} (a cache of derived state; restore: the task's comment)")
        result
      end

      def self.human(bytes)
        units = %w[B KB MB GB TB]
        value = bytes.to_f
        unit = units.shift
        while value >= 1024 && !units.empty?
          value /= 1024
          unit = units.shift
        end
        unit == "B" ? "#{bytes} B" : format("%<v>.1f %<u>s", v: value, u: unit)
      end

      private

      def human(bytes) = self.class.human(bytes)

      def snapshot(path)
        name = File.basename(path)
        destination = File.join(@target, name)
        started = @clock.call
        Store.vacuum_into!(path, destination)
        entry = Entry.new(name: name, bytes: File.size(destination), seconds: @clock.call - started)
        @out.puts("  #{name}: #{human(entry.bytes)} in #{format_duration(entry.seconds)}")
        entry
      end

      def preflight!
        raise Refused, "name a target directory: rake \"db:snapshot[TARGET_DIR]\"" if @target.empty?
        raise Refused, "target #{@target} does not exist (create it first)" unless File.directory?(@target)
        raise Refused, "target #{@target} is not writable" unless File.writable?(@target)
        raise Refused, "target #{@target} is the db dir itself" if same_dir?(@target, @db_dir)

        files = Dir.glob(File.join(@db_dir, "*.sqlite3"))
        raise Refused, "no *.sqlite3 files in #{@db_dir}" if files.empty?

        clashes = files.map { |path| File.basename(path) }.select { |name| File.exist?(File.join(@target, name)) }
        raise Refused, "target #{@target} already holds #{clashes.join(', ')} — pick a fresh dir" unless clashes.empty?

        reason = @rebuild_check.call
        raise Refused, "a rebuild is in progress — #{reason}" if reason

        files
      end

      def same_dir?(one, two)
        File.realpath(one) == File.realpath(two)
      rescue SystemCallError
        false
      end
    end
  end
end
