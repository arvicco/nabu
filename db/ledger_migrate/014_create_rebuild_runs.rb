# frozen_string_literal: true

# One row per rebuild run, either flavor (Store::RebuildRuns). The per-source
# `runs` rows a rebuild opens describe its REPLAYS; nothing recorded the
# run itself — so the 2026-11-09 rebuild that died in its corpus reindex
# left per-source load rows and no trace that the run as a whole never
# finished. The row is written at START (mode, code revision, the planned
# stage set, the pid) and completed_at is stamped as the run's LAST act:
# a row without it is a run that never completed, readable by status and
# the index doctor. +notes+ carries a raised run's error. Operational
# history, so it lives in the ledger, which no rebuild ever drops. The two
# instants are ISO-8601 UTC strings (the slice_refreshes precedent): the
# lines that read them back print UTC, whatever the box's zone.
Sequel.migration do
  change do
    create_table(:rebuild_runs) do
      primary_key :id
      String :mode, null: false
      String :started_at, null: false
      String :completed_at
      String :git_sha
      String :planned_stages, text: true
      Integer :pid
      String :notes, text: true

      index :started_at
    end
  end
end
