# frozen_string_literal: true

# P106-1 (№R-69 generalization 2): the dictionary-group census — one row
# per dictionary written by Store::DictionaryStats: the shipped language
# code, the lect node it resolves to through the nabu-lects codemap
# (per-source overrides included; NULL when the registry knows no such
# node — the censused-UNRESOLVED posture), and the live entry count.
# `define`'s header, the language cards and the site desks read these
# few hundred rows instead of scanning millions of entries (the
# desk-commands law). Derived: drop-and-reproject at rebuild, per source
# after a dictionary-bearing sync.
Sequel.migration do
  change do
    create_table(:dictionary_stats) do
      foreign_key :dictionary_id, :dictionaries, null: false
      String :slug, null: false
      foreign_key :source_id, :sources, null: false
      String :language, null: false
      String :lect
      Integer :entries, null: false
      index :dictionary_id, unique: true
      index :lect
    end
  end
end
