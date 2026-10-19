# frozen_string_literal: true

# Etymology mining on the reflex table — three additive, nullable columns
# (NULL = "not stated", the shape every pre-existing row keeps):
#
# - relation: the typed edge a parser states, closed vocabulary
#   (Nabu::DictionaryReflex::RELATIONS). The ETYMON relations —
#   inherited / derived / borrowed / learned-borrowing, the kaikki
#   etymology templates — point UP: the named word is the OWNING entry's
#   own ancestor or donor, the reverse of a descendants-tree row, so the
#   descent walks (etym, the reflex-roots closure, the reflex-chains
#   export) skip them (Store::DictionaryReflex.descent). "cognate" (the
#   Lewis & Short cognate chains) is direction-free and walks like the
#   MW cognate rows always have.
# - attested: the verbatim first-attestation date upstream prints for the
#   reflex (DÉRom's "dp. 1220", "ca 1650", "1551/1558").
# - attested_year: its parsed lower-bound year, NULL when the shape does
#   not parse (the verbatim text stays the record).
Sequel.migration do
  change do
    alter_table(:dictionary_reflexes) do
      add_column :relation, String, null: true
      add_column :attested, String, null: true
      add_column :attested_year, Integer, null: true
    end
  end
end
