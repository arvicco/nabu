# frozen_string_literal: true

require "json"
require "time"

module Nabu
  module Store
    # Rebuild runs as machine-visible ledger rows (ledger migration 014).
    #
    # Why: the 2026-11-09 rebuild died inside its corpus reindex after
    # eight hours, and the only traces it left were per-source load rows
    # and an index that looked whole to every reader. The stage timings,
    # held in memory until a successful end, were lost with it. A rebuild
    # now opens its row FIRST (mode, the code revision it runs, the planned
    # stage set, its pid) and stamps completed_at as its LAST act — so an
    # unfinished run is a fact in the ledger, and #attention turns it into
    # the one loud line `nabu status` and `nabu index doctor` print.
    #
    # Only the LATEST run speaks: a later completed run supersedes a dead
    # one (whatever the dead run left partial, the later run re-derived).
    # A row without completed_at reads three ways: its pid alive → still
    # RUNNING (a fact, not damage); a recorded error → failed; otherwise
    # the process died mid-run — "never completed, the index may be
    # partial". The pid probe is local (Nabu::ProcessProbe): the ledger is a
    # per-box file, so a pid always names a process on this box; a
    # recycled pid can only make a dead run read as running (the
    # conservative error, never a false alarm).
    #
    # Reader convention (StageTimings'): a nil or pre-014 ledger has
    # nothing to say, and the writers decline silently there.
    module RebuildRuns
      TABLE = :rebuild_runs

      module_function

      # Open the run's row; returns its id (nil on a pre-014 ledger).
      def start!(ledger, mode:, planned_stages:, git_sha: code_revision, pid: Process.pid, at: Time.now)
        return nil unless table?(ledger)

        ledger[TABLE].insert(mode: mode, started_at: at.utc.iso8601, git_sha: git_sha, pid: pid,
                             planned_stages: JSON.generate(Array(planned_stages)))
      end

      # Narrow the planned set once it is known (the incremental sweep).
      def plan!(ledger, id, planned_stages)
        return if id.nil?

        ledger[TABLE].where(id: id).update(planned_stages: JSON.generate(Array(planned_stages)))
      end

      # The run's LAST act.
      def complete!(ledger, id, at: Time.now)
        return if id.nil?

        ledger[TABLE].where(id: id).update(completed_at: at.utc.iso8601)
      end

      # A raised run: the error on the row, completed_at stays NULL — the
      # run did not complete, and the row must keep saying so.
      def fail!(ledger, id, error)
        return if id.nil?

        ledger[TABLE].where(id: id).update(notes: "failed: #{error.message}")
      end

      # The one line an unfinished latest run earns, or nil. A damage line
      # (died, failed) carries the "⚠ " lead; a live run's line does not.
      def attention(ledger)
        return nil unless table?(ledger)

        row = ledger[TABLE].order(Sequel.desc(:id)).first
        return nil if row.nil? || row[:completed_at]

        started = stamp(row[:started_at])
        if row[:notes].nil? && alive?(row[:pid])
          return "rebuild (#{row[:mode]}) RUNNING since #{started} (pid #{row[:pid]})"
        end

        failed = row[:notes] ? " (#{row[:notes]})" : ""
        "⚠ rebuild (#{row[:mode]}) started #{started}, never completed#{failed} — the index may be partial"
      end

      # The run-health lines `nabu status` and `nabu index doctor` print:
      # the dead-row sweep first (RunRecorder.sweep_dead! — it WRITES: a
      # "running" row whose process is gone closes "abandoned" at this
      # read), then the latest rebuild run's attention line. Empty when
      # there is nothing to say; a nil ledger has nothing to say.
      def health_lines(ledger)
        return [] if ledger.nil?

        closed = RunRecorder.sweep_dead!
        lines = []
        lines << "closed #{closed.size} dead run row(s) \"abandoned\" (their process is gone)" if closed.any?
        lines << attention(ledger)
        lines.compact
      end

      def alive?(pid) = ProcessProbe.alive?(pid)

      def stamp(iso) = Time.iso8601(iso.to_s).utc.strftime("%Y-%m-%d %H:%M:%S UTC")

      # The code revision the run executes (the repository HEAD), nil
      # outside a git checkout. Read once at start, before any work.
      def code_revision
        Shell.run("git", "-C", File.expand_path("../../..", __dir__), "rev-parse", "HEAD").strip
      rescue Shell::Error
        nil
      end

      def table?(ledger)
        !ledger.nil? && ledger.table_exists?(TABLE)
      end
    end
  end
end
