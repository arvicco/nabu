# frozen_string_literal: true

# Widen the runs status CHECK with "abandoned": the terminal status
# `nabu runs close-stale` writes on a row its process never closed (killed,
# crashed, slept through), so the row stops reading "running" forever and
# the health stale-open-runs finding stops counting it — while staying
# distinguishable from a run that genuinely failed or was aborted.
#
# SQLite has no ALTER DROP CONSTRAINT, and Sequel's emulation (recreate the
# table from the parsed schema) keeps only the constraint the same
# alter_table call adds — every OTHER named CHECK is lost (verified: the
# 003-style drop/add silently dropped runs_kind_valid, and re-adding it in
# turn dropped runs_status_valid). So the table is rebuilt explicitly: a
# new table with the full 001 + 011 shape and BOTH checks, the rows copied
# id-for-id, the old table dropped, the new one renamed, the indexes
# re-declared. Nothing references runs by foreign key.
Sequel.migration do
  run_kinds = %w[sync rebuild].freeze
  columns = %i[id source_slug kind started_at finished_at added updated withdrawn_count
               errored status notes loaded_at].freeze

  rebuild = Kernel.lambda do |db, statuses| # the DSL is a BasicObject: no bare lambda
    db.create_table(:runs_rebuilt) do
      primary_key :id
      String :source_slug, null: false
      String :kind, null: false, default: "sync"
      DateTime :started_at, null: false
      DateTime :finished_at
      Integer :added, null: false, default: 0
      Integer :updated, null: false, default: 0
      Integer :withdrawn_count, null: false, default: 0
      Integer :errored, null: false, default: 0
      String :status, null: false, default: "running"
      String :notes, text: true
      DateTime :loaded_at, null: true

      constraint(:runs_status_valid, status: statuses)
      constraint(:runs_kind_valid, kind: run_kinds)
    end
    db[:runs_rebuilt].import(columns, db[:runs].select(*columns).order(:id))
    db.drop_table(:runs)
    db.rename_table(:runs_rebuilt, :runs)
    db.add_index(:runs, :source_slug)
    db.add_index(:runs, %i[source_slug kind])
  end

  up do
    rebuild.call(self, %w[running succeeded failed aborted abandoned])
  end

  # Down refuses nothing silently: an "abandoned" row cannot satisfy the
  # legacy check, so the copy raises rather than rewriting history.
  down do
    rebuild.call(self, %w[running succeeded failed aborted])
  end
end
