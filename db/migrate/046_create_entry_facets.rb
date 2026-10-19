# frozen_string_literal: true

# The dictionary-entry grain of the facet surface (the migration 045 mold):
# categorical claims upstream makes per ENTRY — JMdict's domain / usage /
# dialect labels and loanword donor codes, WOLD's semantic fields, TLS's
# word→concept assignments — had nowhere to land: document_facets and the
# passage facet tables key on documents and passages, and a dictionary
# entry is neither.
#
# - dictionary_entries.annotations_json: the entry's annotations as the
#   adapter emitted them (canonical JSON, the passages.annotations_json
#   contract), NULL when the entry carries none — the common case on the
#   million-entry shelves, so the column costs nothing there and the
#   builder's probe is a plain IS NOT NULL. Content: the entry's sha
#   covers it (appended only when present), so the column moves with the
#   entry's revision, never on its own.
# - entry_facet_values: one row per DISTINCT (source, facet, value, ref) —
#   the vocabulary a filter pattern scans (JMdict's 34k domain tags fold
#   to ~100 values). source_id scopes it so a source's slice derives
#   wholesale; ref is an optional authority/id ref (the TLS concept uuid),
#   NULL for plain labels.
# - entry_facets: (value_id, entry_id) pairs, WITHOUT ROWID with the pair
#   as primary key — the filter index IS the table. No FK constraints (the
#   045 reasoning: the table is derived wholesale from rows the builder
#   just read).
#
# Rebuild-regenerated (Store::EntryFacetBuilder, from the loaded entries'
# annotations_json — itself f(canonical) — under config/facet_map.yml's
# entry_fields): drop and re-project is the lifecycle.
Sequel.migration do
  change do
    alter_table(:dictionary_entries) do
      add_column :annotations_json, String, text: true
    end

    create_table(:entry_facet_values) do
      primary_key :id
      foreign_key :source_id, :sources, null: false
      String :facet, null: false
      String :value, null: false
      String :ref

      index :source_id
      index %i[facet value]
    end

    create_table(:entry_facets, without_rowid: true) do
      Integer :value_id, null: false
      Integer :entry_id, null: false
      primary_key %i[value_id entry_id]
    end
  end
end
