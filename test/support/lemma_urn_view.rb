# frozen_string_literal: true

# The lemma table keys passages by catalog id only (fts_lemma v2 — no
# stored urn). Adapter tests that pin WHICH passage a lemma row belongs to
# read it by urn; this view joins each row to its passage urn through the
# catalog (the two-step id join — no ATTACH) into a scratch in-memory
# table, so those assertions keep their urn-shaped dataset reads verbatim.
module LemmaUrnView
  module_function

  def of(fulltext, catalog)
    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE].all
    urns = catalog[:passages].where(id: rows.map { |row| row.fetch(:passage_id) }.uniq).select_hash(:id, :urn)
    view = Sequel.sqlite
    view.create_table(:passage_lemmas) do
      String :lemma_folded
      String :lemma_raw
      Integer :passage_id
      String :urn
      String :language
      String :surface_forms
      String :tier
    end
    view[:passage_lemmas].multi_insert(rows.map { |row| row.merge(urn: urns[row.fetch(:passage_id)]) })
    view[:passage_lemmas]
  end
end
