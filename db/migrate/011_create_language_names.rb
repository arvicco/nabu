# frozen_string_literal: true

# P18-4: the DERIVED language-name census. kaikki's descendants data carries
# a human `lang` name on every node next to the `lang_code` the crosswalk
# stores ("zle-ort" · "Old Ruthenian") — until now the parser dropped it, so
# `etym` renders raw codes no humanist can read. One row per
# (dictionary, lang_code, name) with its occurrence count over the WORDED
# nodes of that dictionary's descendants trees, written by DictionaryLoader
# wholesale per reflex-bearing dictionary (the reflexes lifecycle), a pure
# function of canonical/ — a rebuild or parse-only resync regenerates it.
#
# The census is stored RAW (canonical means canonical): upstream noise like
# "Cyrillic script" wrapper nodes and "unknown" stays in the table; the read
# side (Nabu::Languages) applies the plausibility filter and takes the mode,
# so a rule change never needs a reparse. Names are deliberately NOT stored
# per reflex row (a 787-name function duplicated across a million rows) and
# NOT part of the entry ContentHash (display metadata, not content identity —
# no revision storm on the next full load).
Sequel.migration do
  change do
    create_table(:language_names) do
      primary_key :id
      foreign_key :dictionary_id, :dictionaries, null: false
      String :lang_code, null: false
      String :name, null: false
      Integer :occurrences, null: false

      index :dictionary_id
      index :lang_code
    end
  end
end
