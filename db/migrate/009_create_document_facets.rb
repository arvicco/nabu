# frozen_string_literal: true

# The genre facet (P17-2, edh-survey §4.3): a skinny catalog-side table of
# categorical document facts — inscription type/genre, Roman province,
# material, object type — the filters `search --type/--province/--material`
# compose over. NOT columns on documents, for exactly the document_axes
# arguments replayed: facet values are sparse (25.7% of EDH carries no type),
# multi-valued in principle (a source may attest several), and a NEW facet
# must never mean a new migration — the facet column is an open vocabulary.
#
# - facet: the facet name ("genre", "province", "material", "object_type" for
#   EDH v1; future sources add values, not columns).
# - value: the normalized display/filter term — the source's own English/
#   EAGLE-vocabulary term where it carries one ("epitaph", "Germania
#   inferior", "altar"), else the upstream term verbatim.
# - raw: the upstream verbatim code/term ("titsep?", "GeI", "Tafel") — the
#   `?` certainty rider SURVIVES normalization (conventions §3: there is no
#   "original", only what the source said).
#
# Rebuild-regenerated (Store::FacetBuilder — from the loaded documents'
# metadata_json, itself f(canonical)), like document_axes: dropping every row
# and rebuilding is the lifecycle, so rows carry no bookkeeping columns.
#
# RIDER: documents.metadata_json. Adapters already emit Nabu::Document
# +metadata+ (persons prosopography, Trismegistos ids, facets — edh-survey
# §4.5/§4.6), but the loader had nowhere to put it; this column persists it.
# It is METADATA, never content — deliberately kept OUT of
# Store::ContentHash (the license_override precedent), so a metadata change
# never fakes a content revision and every already-stored document sha is
# byte-stable.
Sequel.migration do
  change do
    create_table(:document_facets) do
      primary_key :id
      foreign_key :document_id, :documents, null: false
      String :facet, null: false
      String :value, null: false
      String :raw

      index :document_id
      index %i[facet value]
    end

    alter_table(:documents) do
      add_column :metadata_json, String, text: true, null: false, default: "{}"
    end
  end
end
