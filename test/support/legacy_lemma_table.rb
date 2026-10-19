# frozen_string_literal: true

# The pre-narrowing passage_lemmas shape (fts_lemma stage "v1"): every row
# carried its passage URN beside the passage id, and the urn — not the
# passage id — was the B-tree key of the passage-keyed lookups. An index
# built by that code stays on disk until the next full rebuild, so every
# consumer must keep answering against it; tests downgrade a freshly built
# table into that shape with this helper.
module LegacyLemmaTable
  module_function

  # Rebuild +fulltext+'s lemma table in the v1 shape in place: same rows,
  # urn column filled from +catalog+, urn index instead of passage_id.
  def widen!(fulltext, catalog)
    table = Nabu::Store::Indexer::LEMMA_TABLE
    rows = fulltext[table].all
    urns = catalog[:passages].where(id: rows.map { |row| row.fetch(:passage_id) }.uniq).select_hash(:id, :urn)
    fulltext.drop_table(table)
    fulltext.create_table(table) do
      String :lemma_folded, null: false
      String :lemma_raw, null: false
      Integer :passage_id, null: false
      String :urn, null: false
      String :language, null: false
      String :surface_forms, null: false
      String :tier, null: false
    end
    fulltext[table].multi_insert(rows.map { |row| row.merge(urn: urns.fetch(row.fetch(:passage_id))) })
    fulltext.add_index(table, :lemma_folded)
    fulltext.add_index(table, :urn)
    fulltext.add_index(table, :language)
    fulltext
  end
end
