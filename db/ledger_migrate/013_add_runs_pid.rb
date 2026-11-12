# frozen_string_literal: true

# The pid that opened each run row. A row can sit "running" forever after
# its process dies (a kill runs no rescue, by design); with the pid on the
# row, the next status / index doctor read can ask the operating system
# whether that process still exists and close the row "abandoned" honestly,
# instead of waiting out the 48 h age threshold. NULL on every
# pre-existing row — those keep the supersession rule (RunRecorder
# .sweep_dead!). A plain ADD COLUMN: SQLite adds it natively, so the named
# CHECKs migration 012 rebuilt stay intact.
Sequel.migration do
  change do
    alter_table(:runs) do
      add_column :pid, Integer, null: true
    end
  end
end
