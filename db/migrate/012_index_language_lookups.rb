# frozen_string_literal: true

# P18-4 follow-up (owner: "Retrieval extra-long, probably needs some
# indexing"): `nabu language CODE` computes live relevance counts by
# language column, and every one of its catalog queries was a full table
# scan — dictionary_reflexes by lang_code (1,006,872 rows) and documents
# by language (170,684 rows); measured 11.6 s per card. Two B-tree
# indexes turn the card interactive. (The third scan, passage_lemmas by
# language, lives in the derived fulltext db — its index is created by
# the Indexer, not migrated; see indexer.rb.)
Sequel.migration do
  change do
    alter_table(:dictionary_reflexes) do
      add_index :lang_code
    end
    alter_table(:documents) do
      add_index :language
    end
  end
end
