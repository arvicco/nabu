# frozen_string_literal: true

# The reconstruction crosswalk (P14-1, architecture §12): machine-readable
# descendant edges of the reconstruction shelves (wiktionary-recon —
# Proto-Slavic/PIE/Proto-Germanic). One row per WORDED node of a kaikki
# `descendants` tree, flattened depth-first (seq); replaced wholesale when
# the owning entry is revised (reflexes are part of the entry's content
# hash, exactly like dictionary_citations).
#
# - lang_code: the upstream Wiktionary code VERBATIM ("cu", "zlw-ocs", the
#   lone malformed "ML.") — canonical means canonical.
# - language: the catalog-side tag the crosswalk joins on (cu→chu, la→lat,
#   sa→san, identity for shape-valid codes; NULL = display-only).
# - word/roman: the reflex verbatim (NFC) and its upstream romanization —
#   roman is load-bearing for scripts the catalog's gold lemmas romanize
#   (Gothic 𐌲𐌿𐌸 ↔ gold lemma "guþ").
# - word_folded/roman_folded: conventions-§9 search forms (leading asterisk
#   stripped), the join keys against passage_lemmas.lemma_folded and — for
#   proto-to-proto edges — the other shelves' headword_folded. Resolution
#   happens at QUERY time, never here (the §10/§11 no-stale-links stance).
Sequel.migration do
  change do
    create_table(:dictionary_reflexes) do
      primary_key :id
      foreign_key :dictionary_entry_id, :dictionary_entries, null: false
      Integer :seq, null: false
      String :lang_code, null: false
      String :language
      String :word, null: false
      String :roman
      String :word_folded
      String :roman_folded

      index :dictionary_entry_id
      index %i[language word_folded]
      index %i[language roman_folded]
    end
  end
end
