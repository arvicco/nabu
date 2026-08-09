# frozen_string_literal: true

# P63-5: the place crosswalk — asserted equivalences BETWEEN gazetteer
# namespaces, as DATA with provenance (never inferred; the Dp-b doctrine:
# namespaces are parallel, crosswalks are what an upstream actually says).
# First writer: the CIGS derive (its own pleiades/geonames/cdli-provenience
# columns); the P63 plan's Wikidata harvest appends under its own `source`.
# Derived wholesale per source (delete-where-source + insert), so each
# asserting shelf owns its slice — the place_index per-gazetteer contract.
Sequel.migration do
  up do
    create_table(:place_crosswalk) do
      String :source, null: false # which shelf asserts it ("cigs", "wikidata"…)
      String :gazetteer_a, null: false
      String :id_a, null: false
      String :gazetteer_b, null: false
      String :id_b, null: false

      index %i[source gazetteer_a id_a gazetteer_b id_b], unique: true
      index %i[gazetteer_a id_a]
      index %i[gazetteer_b id_b]
    end
  end

  down do
    drop_table(:place_crosswalk)
  end
end
