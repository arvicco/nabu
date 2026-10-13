# frozen_string_literal: true

# P123-1: entry↔entry cross-references — the "v. μῦθος" / "cf. 丸・まる・1" /
# synonym pointers a dictionary entry makes to ANOTHER headword of the
# SAME dictionary. Machine-readable upstream markup only (LSJ <xr>,
# JMdict <xref>/<ant>, kaikki synonyms/antonyms/related) — prose "cf."
# mentions are not extracted.
#
# - dictionary_entry_id: the FROM entry; seq keeps entry order.
# - kind: the dictionary's own pointer class, normalized to a small
#   vocabulary (see / equals / variant / false-reading / gloss / like /
#   synonym / antonym / related).
# - label: the pointer verbatim as the dictionary prints it ("v. μῦθος").
# - target / target_folded: the pointed-at headword as displayed, and its
#   conventions-§9 search form in the dictionary's language — the
#   resolution key against dictionary_entries.headword_folded.
# - to_entry_id: the resolved TO entry — set by the loader's resolution
#   pass after each load of the owning source, ONLY when exactly one live
#   entry of the same dictionary carries target_folded (an ambiguous
#   homograph pointer stays NULL: resolve-or-verbatim, never a guess).
#
# Replaced wholesale with the entry's citations/reflexes when the entry is
# revised (crossrefs are part of the entry's content hash). Derived: the
# whole table re-mints on rebuild.
Sequel.migration do
  change do
    create_table(:dictionary_crossrefs) do
      primary_key :id
      foreign_key :dictionary_entry_id, :dictionary_entries, null: false
      Integer :seq, null: false
      String :kind, null: false
      String :label, null: false
      String :target, null: false
      String :target_folded
      foreign_key :to_entry_id, :dictionary_entries

      index :dictionary_entry_id
      index :to_entry_id
    end

    alter_table(:dictionary_entries) do
      add_index %i[dictionary_id headword_folded], name: :dictionary_entries_dict_folded
    end
  end
end
