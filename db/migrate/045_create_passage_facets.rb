# frozen_string_literal: true

# The passage-grain facet surface: categorical claims upstream makes per
# PASSAGE (a sillok article's subject classes, an ITKC article's genre
# classes, and — the design load — per-passage entity tags: person,
# place and book-title names with authority refs, from corpora carrying
# millions of tags). document_facets cannot hold them: its rows key on
# documents, and a passage claim smeared onto its document would lie
# about which article says what.
#
# Two tables, dictionary-encoded, because the row count is the problem:
#
# - passage_facet_values: one row per DISTINCT (source, facet, value,
#   ref) — the vocabulary. Small: sillok's 899,669 tag pairs fold to 216
#   values. A filter pattern (LIKE/ILIKE) scans THIS table, never the
#   tens of millions of tag rows.
#   * source_id scopes the vocabulary so a source's slice derives
#     wholesale (drop its values + their rows, re-project) without a
#     cross-source orphan sweep.
#   * ref: the authority ref an entity value carries (namespaced,
#     verbatim — the place_ref doctrine), NULL for plain labels.
# - passage_facets: (value_id, passage_id) pairs, WITHOUT ROWID with the
#   pair as primary key — two integers per tag and the filter index IS
#   the table (value_id range → passage ids, sorted). No FK constraints:
#   the table is derived wholesale from rows the builder just read, and
#   an FK on passage_id would make any parent-side delete scan tens of
#   millions of rows.
#
# Rebuild-regenerated (Store::PassageFacetBuilder, from the loaded
# passages' annotations_json — itself f(canonical) — under
# config/facet_map.yml's passage_fields), like document_facets: drop and
# re-project is the lifecycle, so rows carry no bookkeeping columns.
Sequel.migration do
  change do
    create_table(:passage_facet_values) do
      primary_key :id
      foreign_key :source_id, :sources, null: false
      String :facet, null: false
      String :value, null: false
      String :ref

      index :source_id
      index %i[facet value]
    end

    create_table(:passage_facets, without_rowid: true) do
      Integer :value_id, null: false
      Integer :passage_id, null: false
      primary_key %i[value_id passage_id]
    end
  end
end
