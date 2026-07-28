# frozen_string_literal: true

require "json"

module Nabu
  module Store
    # Populates the catalog's document_facets table (P17-2, migration 009 —
    # the genre facet, edh-survey §4.3) from the loaded documents'
    # metadata_json "facets" key. A post-load pass like the TimelineBuilder, but
    # reading the CATALOG rather than canonical: the loader already persisted
    # each document's adapter-emitted facets (themselves f(canonical) — the
    # parser reads the record's own EAGLE terms, the adapter joins the CSV
    # raw codes), so the rebuild pass is a cheap projection, no canonical
    # re-parse. Wired into Rebuild#run after the timeline; facets = f(catalog) =
    # f(canonical), and `nabu rebuild` regenerates the table (the invariant).
    #
    # Full-rebuild semantics: drop every row, re-project. Rows are skinny
    # (document_id, facet, value, raw) with no bookkeeping columns — the
    # drop-and-rebuild lifecycle of the derived indexes. Withdrawn documents
    # contribute no rows (facets feed corpus-facing filters, which never see
    # withdrawn documents anyway).
    module FacetBuilder
      # What one rebuild projected: distinct faceted documents + total rows.
      Summary = Data.define(:documents, :rows)

      module_function

      # Drop and re-project. The cheap substring probe skips the JSON parse
      # for the facet-less majority; metadata_json is our own canonical_json
      # output, so a parse failure is real corruption and honestly raises.
      def rebuild!(catalog:)
        catalog[:document_facets].delete
        documents = 0
        rows = 0
        catalog[:documents]
          .where(withdrawn: false)
          .where(Sequel.like(:metadata_json, '%"facets"%'))
          .select_map(%i[id metadata_json]).each do |id, json|
            facets = JSON.parse(json)["facets"]
            next unless facets.is_a?(Hash) && !facets.empty?

            documents += 1
            rows += insert_facets(catalog, id, facets)
          end
        Summary.new(documents: documents, rows: rows)
      end

      # The per-source seam (P47-r3, the lane-drift audit): drop this
      # source's facet rows, re-project its facet-bearing documents —
      # SyncRunner calls it post-load so the facet lane never lags a sync
      # (before this, facets refreshed only at full rebuild; EDR, IIP,
      # Elephantine and the Sefaria Rabbinic wave all served zero facet
      # rows until the next rebuild).
      def refresh_source!(catalog:, slug:)
        source_id = catalog[:sources].where(slug: slug).get(:id)
        return 0 if source_id.nil?

        doc_ids = catalog[:documents].where(source_id: source_id).select(:id)
        catalog[:document_facets].where(document_id: doc_ids).delete
        rows = 0
        catalog[:documents]
          .where(source_id: source_id, withdrawn: false)
          .where(Sequel.like(:metadata_json, '%"facets"%'))
          .select_map(%i[id metadata_json]).each do |id, json|
            facets = JSON.parse(json)["facets"]
            next unless facets.is_a?(Hash) && !facets.empty?

            rows += insert_facets(catalog, id, facets)
          end
        rows
      end

      # A facet entry carries a singular "value" (EDH, EDR, Elephantine…)
      # or a plural "values" array (IIP — one row per value; P47-r3, the
      # lane-drift audit: the singular-only reader left IIP dark through a
      # full rebuild).
      def insert_facets(catalog, document_id, facets)
        facets.sum do |facet, entry|
          next 0 unless entry.is_a?(Hash)

          values = entry.key?("values") ? Array(entry["values"]) : [entry["value"]]
          values.compact.count do |value|
            catalog[:document_facets].insert(
              document_id: document_id, facet: facet,
              value: value, raw: entry["raw"]
            )
            true
          end
        end
      end
    end
  end
end
