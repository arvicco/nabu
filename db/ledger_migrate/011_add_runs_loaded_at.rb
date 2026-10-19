# frozen_string_literal: true

# The run row closes at OPERATION end, not load end. A sync keeps working
# after its load commits (the index slice, the catalog-lane refreshes) and a
# rebuild's replays are followed by the corpus stages (timeline, facets, the
# fulltext index, links); a row that read "succeeded" the moment the load
# returned claimed an operation that had not finished — and kept claiming it
# when the process died in a later stage.
#
# loaded_at records the load-stage boundary on its own: the row stays
# "running" past it and only reaches its terminal status (with finished_at)
# when the whole operation ends. A row reading running + loaded_at set +
# finished_at NULL is the signature of a run that died after its load.
# NULL on every pre-existing row (they closed under the old contract).
Sequel.migration do
  change do
    alter_table(:runs) do
      add_column :loaded_at, DateTime, null: true
    end
  end
end
