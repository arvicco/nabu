# frozen_string_literal: true

# P99-3 (№R-63): the kind axis' precompiled census — per (source, head)
# distinct-document counts written by Store::KindBuilder in the same
# pass that mints the kind facet rows, so `nabu kind census` reads a
# few hundred rows instead of grouping millions (the desk-commands
# law: cards touch only precompiled data). A NULL head is the
# per-source distinct-document total (multi-label documents counted
# once). Derived: drop-and-reproject with the kind rows themselves.
Sequel.migration do
  change do
    create_table(:kind_stats) do
      foreign_key :source_id, :sources, null: false
      String :head
      Integer :documents, null: false
      index %i[source_id head]
    end
  end
end
