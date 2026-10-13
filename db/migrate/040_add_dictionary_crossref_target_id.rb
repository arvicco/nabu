# frozen_string_literal: true

# P124-3: id-keyed cross-references. Some dictionaries point at another
# entry by its UPSTREAM ID rather than its headword (the AED's
# <xr type="root"><ref target="tla866216"/></xr> — the TLA lemma id, no
# surface form at all). target_id carries that id; when set, the loader's
# resolution pass matches it against dictionary_entries.entry_id (unique
# per dictionary, migration 006) instead of folding a headword, and
# target_folded stays NULL. Additive and nullable: every headword-keyed
# row of migration 039 is untouched.
Sequel.migration do
  change do
    alter_table(:dictionary_crossrefs) do
      add_column :target_id, String
    end
  end
end
