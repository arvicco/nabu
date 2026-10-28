# frozen_string_literal: true

# Two lanes the person index lacked until a prosopography arrived whose
# persons are DEFINED by their attestations (PNA — Nabu::PnaPersons):
#
# - person_index_texts: a person's texts, in the authority's own order —
#   the publication as the authority cites it (verbatim: "SAA 6 10",
#   "ABL 458") and, when the derivation's crosswalk met a HELD document,
#   that document's urn (NULL = a bare citation the library does not
#   hold). Indexed by urn too, so "who is attested in this text" is one
#   probe.
# - person_index.attributes_json: the authority's own per-person fields
#   the CBDB-born columns have no lane for (PNA: name language, gender,
#   reign-era, profession, place, origin) — a small JSON object, the
#   upstream values verbatim.
#
# Derived wholesale per authority with the slice (Store::PersonIndex
# .derive!); no backfill — empty means "not yet derived".
Sequel.migration do
  change do
    create_table(:person_index_texts) do
      String :authority, null: false
      String :person_id, null: false
      Integer :position, null: false
      String :publication, null: false
      String :urn
      primary_key %i[authority person_id position]
      index :urn
    end

    alter_table(:person_index) do
      add_column :attributes_json, String
    end
  end
end
