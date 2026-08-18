# frozen_string_literal: true

# P78-r1 (Q34, owner commission 2026-08-18: every long pass should say
# how long it expects to run): the durable per-stage wall-time record
# the ETA line reads. The P36-0 profiler has measured per-source /
# per-stage rebuild times all along and DISCARDED them ("observability
# only"); this table keeps the latest facts so the next run can say
# "~6m (last run 5m48s over 2,830 rows)".
#
# It belongs in the history LEDGER for the №R-21 reason: operational
# history, not a function of canonical/ — a `nabu rebuild` must never
# wipe the very timings that predict it. Keyed by (kind, scope, stage):
# kind names the operation family ("rebuild", "sync", "drill"), scope
# the source slug or "corpus", stage the profiler's stage name. Each
# run APPENDS (history, the creep-acceptances shape); the LATEST row
# governs the estimate, and +rows+ carries the run's work size so the
# estimate can scale by row-count drift instead of silently aging (the
# era-bound-constants rule). Forward-only, like every migration here.
Sequel.migration do
  change do
    create_table(:stage_timings) do
      primary_key :id
      String :kind, null: false
      String :scope, null: false
      String :stage, null: false
      Float :seconds, null: false
      Integer :rows
      DateTime :finished_at, null: false

      index %i[kind scope stage]
    end
  end
end
