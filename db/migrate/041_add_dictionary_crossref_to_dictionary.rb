# frozen_string_literal: true

# P124-3: cross-DICTIONARY pointers. The OSHB LexicalIndex <xref> names
# the same lexeme in OTHER dictionaries (bdb="b.cw.aa", twot="278").
# to_dictionary carries the target dictionary's slug; NULL keeps the
# P123-1 default (the pointer's own dictionary). The loader resolves such
# a pointer by target_id within the named dictionary when the catalog
# holds it (BDB: yes, same source) and leaves it NULL when it does not
# (TWOT) — rendered verbatim. Additive and nullable.
Sequel.migration do
  change do
    alter_table(:dictionary_crossrefs) do
      add_column :to_dictionary, String
    end
  end
end
