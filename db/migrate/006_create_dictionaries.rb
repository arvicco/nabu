# frozen_string_literal: true

# The dictionary shelf (P11-4, architecture §11): LSJ + Lewis & Short as a
# queryable surface. Entries are NOT passages — they get their own tables in
# the CATALOG (they are first-class derived-from-canonical data with the same
# revision/withdraw/idempotency semantics as documents, replayed by `nabu
# rebuild` like everything else here — not drop-and-rebuild index rows, which
# is what fulltext.sqlite3 is for).
#
# - dictionaries: one row per dictionary (lsj, lewis-short), owned by a
#   source (the lexica source carries both). `language` is the OBJECT
#   language of the headwords (grc/lat) — deliberately a column, not an enum:
#   a future Bosworth-Toller row is `ang` with zero schema work.
# - dictionary_entries: keyed by (dictionary_id, entry_id) for upserts and by
#   urn (urn:nabu:dict:<slug>:<entry_id>) for provenance/ledger journaling.
#   headword_folded is the define/gloss lookup key (conventions §9 folding).
# - dictionary_citations: one row per CTS-urn-carrying <bibl>; replaced
#   wholesale when its entry is revised (they are part of the entry's content
#   hash). Resolution to in-catalog passage urns happens at QUERY time.
# - provenance grows a nullable dictionary_entry_id so entry transitions
#   journal exactly like document/passage ones.
Sequel.migration do
  change do
    create_table(:dictionaries) do
      primary_key :id
      foreign_key :source_id, :sources, null: false
      String :slug, null: false
      String :title, null: false
      String :language, null: false

      index :slug, unique: true
      index :source_id
    end

    create_table(:dictionary_entries) do
      primary_key :id
      foreign_key :dictionary_id, :dictionaries, null: false
      String :urn, null: false
      String :entry_id, null: false
      String :key_raw, null: false
      String :headword, null: false
      String :headword_folded, null: false
      String :gloss
      String :body, text: true, null: false
      String :content_sha256, null: false
      Integer :revision, null: false, default: 1
      TrueClass :withdrawn, null: false, default: false

      index %i[dictionary_id entry_id], unique: true
      index :urn, unique: true
      index :headword_folded
    end

    create_table(:dictionary_citations) do
      primary_key :id
      foreign_key :dictionary_entry_id, :dictionary_entries, null: false
      Integer :seq, null: false
      String :urn_raw, null: false
      String :cts_work
      String :citation
      String :label, null: false

      index :dictionary_entry_id
      index :cts_work
    end

    alter_table(:provenance) do
      add_foreign_key :dictionary_entry_id, :dictionary_entries
      add_index :dictionary_entry_id
    end
  end
end
