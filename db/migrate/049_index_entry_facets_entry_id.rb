# frozen_string_literal: true

# The reverse probe of the dictionary-entry facet pairs (migration 046):
# entry_facets' primary key (value_id, entry_id) answers the FILTER
# direction (`define --facet`: value ids → entries), but the define card's
# "which facets does THIS entry carry" read starts from entry_id — without
# this index that is a full scan of the pair table, which the desk-commands
# rule forbids. A plain non-unique secondary index on a derived table: the
# EntryFacetBuilder lifecycle (drop + re-project per source) is unchanged,
# and a catalog that has not applied this migration simply reports the
# card's facets as not indexed (Query::Define), never scans.
Sequel.migration do
  change do
    alter_table(:entry_facets) do
      add_index :entry_id
    end
  end
end
