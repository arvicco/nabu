# frozen_string_literal: true

module Nabu
  module Store
    # The durable per-stage wall-time record (P78-r1, Q34: every long pass
    # should say how long it expects to run). The P36-0 profiler measured
    # per-source/per-stage rebuild times all along and DISCARDED them
    # ("observability only"); this module keeps the latest facts in the
    # history LEDGER (migration 009 — the №R-21 home: operational history,
    # not f(canonical), and a rebuild must never wipe the very timings that
    # predict it) so the next run can say "~6m (last run 5m48s over N rows)".
    #
    # Keyed (kind, scope, stage): kind names the operation family
    # ("rebuild", "sync", "drill"), scope the source slug or "corpus",
    # stage the profiler's stage name. Append-only history — the LATEST row
    # governs the estimate — and +rows+ carries the run's work size so the
    # ETA renderer (P78-r2) can scale by row-count drift instead of
    # silently aging (the era-bound-constants rule).
    #
    # Reader convention (QuarantineBaseline's): a nil ledger (fresh
    # machine) or a pre-009 ledger (read paths never migrate) reads as "no
    # history — first run, no estimate", and record! silently declines
    # rather than crashing (write paths migrate first, so in practice the
    # table is there).
    module StageTimings
      TABLE = :stage_timings

      module_function

      # Append one stage's wall time. +rows+ is the run's work size for
      # that stage (documents replayed, passages indexed…), nil when the
      # caller has no honest denominator.
      def record!(ledger, kind:, scope:, stage:, seconds:, rows: nil, at: Time.now)
        return unless table?(ledger)

        ledger[TABLE].insert(kind: kind, scope: scope, stage: stage,
                             seconds: seconds, rows: rows, finished_at: at)
      end

      # The governing (latest) row for one (kind, scope, stage) —
      # {seconds:, rows:, finished_at:} — or nil ("first run, no estimate").
      def last(ledger, kind:, scope:, stage:)
        return nil unless table?(ledger)

        ledger[TABLE].where(kind: kind, scope: scope, stage: stage)
                     .order(Sequel.desc(:id))
                     .select(:seconds, :rows, :finished_at)
                     .first
      end

      def table?(ledger)
        !ledger.nil? && ledger.table_exists?(TABLE)
      end
    end
  end
end
