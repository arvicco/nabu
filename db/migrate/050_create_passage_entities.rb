# frozen_string_literal: true

# The inline-entity index: the "entities" passage annotation the EpiDoc,
# Coptic Scriptorium and DHARMA parsers mine (persons, places and
# upstream's other typed names marked INSIDE the passage text — persName,
# placeName, name, entity spans) made searchable. Until now the records
# sat in passages.annotations_json with no reader: a lookup by name would
# have to JSON-parse every annotated passage, which the desk law forbids.
#
# Two tables, dictionary-encoded (the passage_facets mold, migration 045):
#
# - passage_entity_names: one row per DISTINCT (source, type, text,
#   identity, key, ref, subtype) record — the vocabulary. Every column is
#   the adapter's record VERBATIM (type is upstream's: person, place,
#   ethnic, abstract …; NULL where the record carried none), plus
#   search_key: the folded (case + combining marks) text, identity, key
#   and ref joined by U+001F, so a name lookup is one LIKE over this small
#   table with the query folded the same way — both sides meet.
# - passage_entities: (name_id, passage_id) pairs, WITHOUT ROWID with the
#   pair as primary key — the name_id range IS the passage list. No FK
#   constraints: derived wholesale from rows the builder just read.
#
# Rebuild-regenerated (Store::EntityIndex, from the loaded passages'
# annotations_json — itself f(canonical) — over the sources
# config/entity_index.yml lists): drop and re-project is the lifecycle.
Sequel.migration do
  change do
    create_table(:passage_entity_names) do
      primary_key :id
      foreign_key :source_id, :sources, null: false
      String :type
      String :text
      String :identity
      String :key
      String :ref
      String :subtype
      String :search_key, null: false

      index :source_id
      index :type
    end

    create_table(:passage_entities, without_rowid: true) do
      Integer :name_id, null: false
      Integer :passage_id, null: false
      primary_key %i[name_id passage_id]
    end
  end
end
