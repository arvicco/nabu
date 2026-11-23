# frozen_string_literal: true

# The lanes-ran marker. A sync's catalog lanes (facets, kinds, entities,
# the metadata timeline rows) project AFTER its load commits; a process
# that dies in between leaves the load landed and the lanes dark. The ore
# probes (date bounds / facet metadata with no lane rows) only see that
# when the documents carry such ore — a source without it read "no ore"
# instead of "lanes never ran". lanes_at is stamped on the run row the
# moment the sync's lane step returns (and on a rebuild's replay rows
# once its corpus lane stages ran), so "a row-moving load with no lane
# stamp at or after it" is the honest dark verdict (RunRecorder
# .lanes_pending?).
#
# Backfill: a row that closed "succeeded" with loaded_at set closed at
# OPERATION end (migration 011), after its lanes — so a completed
# row-moving load is stamped at its finished_at. Dead rows, no-op and
# fetch-only rows, and pre-011 rows stay NULL (nothing honest to claim).
# A plain ADD COLUMN: the named CHECKs migration 012 rebuilt stay intact.
Sequel.migration do
  up do
    alter_table(:runs) do
      add_column :lanes_at, DateTime, null: true
    end
    from(:runs).where(status: "succeeded").exclude(loaded_at: nil)
               .exclude((Sequel[:added] + Sequel[:updated]) => 0)
               .update(lanes_at: :finished_at)
  end

  down do
    alter_table(:runs) do
      drop_column :lanes_at
    end
  end
end
