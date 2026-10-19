# frozen_string_literal: true

# Retire the single-column passages(document_id) index (created by 001).
# The unique (document_id, sequence) index — kept: it enforces passage
# identity — has document_id as its left prefix, so it already serves
# every `document_id = ?` / `IN (…)` probe and every documents→passages
# join; EXPLAIN QUERY PLAN against the live statistics shows each
# consumer switching to it (several as a COVERING index), none scanning.
# The redundant B-tree cost ~1.4 GB on disk, one more structure maintained
# per passage insert, and one more bulk CREATE INDEX pass per rebuild.
#
# if_exists: a rebuild that died between Store.drop_deferred_indexes! and
# its recreate leaves the catalog without this index, and the migration
# must still apply there. The down arm restores the 001 shape.
Sequel.migration do
  up do
    alter_table(:passages) do
      drop_index :document_id, if_exists: true
    end
  end

  down do
    alter_table(:passages) do
      add_index :document_id
    end
  end
end
