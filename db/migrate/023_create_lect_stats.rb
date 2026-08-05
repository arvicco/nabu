# frozen_string_literal: true

# The lect census, precomputed (P58 rider, owner ruling: per-stage document
# counts "need to be pre-compiled/memoized at proper time like everything
# else" — the source_stats/P42-0 write-time-census stance). The `language`
# card's stage ladder was aggregating the full lect facet (~492k rows,
# seconds of cold I/O) on every invocation; this table holds the same
# numbers, derived by Store::LectFacets in the same breath that writes the
# facet rows (rebuild, bulk compile, hand ruling) — so reads are indexed
# point lookups and the numbers can never drift from the facet they
# summarize.
#
# Two kinds, one table:
#   kind "lect" — key is a resolved lect id, documents = live documents
#                 whose materialized resolution is exactly that id;
#   kind "bare" — key is a stored language code, documents = live documents
#                 stored under that code with NO facet row (the LectFacets
#                 "no row means identity" invariant, counted).
Sequel.migration do
  change do
    create_table(:lect_stats) do
      primary_key :id
      String :kind, null: false
      String :key, null: false
      Integer :documents, null: false

      index %i[kind key], unique: true
    end
  end
end
