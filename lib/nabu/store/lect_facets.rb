# frozen_string_literal: true

module Nabu
  module Store
    # The materialized lect resolution (P58-4): one document_facets row
    # (facet "lect", value = the resolved lect id) per document whose
    # resolution differs from its bare stored code. D58-e scope, and the
    # invariant the query path stands on: NO ROW means "resolves to
    # itself" — so `--lect` can filter as (facet row matches) OR (bare code
    # matches AND no facet row), with per-document journal rulings, source
    # overrides and codemap defaults all flattened into one indexed axis.
    #
    # Pure derived data: f(catalog documents, registry incl. overrides,
    # journal via the registry's overlay). Recomputed wholesale by `nabu
    # rebuild` and `nabu lect materialize`, per-document by the journal CLI
    # after a hand ruling. The registry handed in decides which tiers
    # apply — load_default's :auto overlay carries the journal.
    module LectFacets
      FACET = "lect"
      # const: SQLite bound-parameter comfort for the bulk insert
      INSERT_BATCH = 1_000

      module_function

      # Wholesale recompute. nil +registry+ (module absent) drops any stale
      # rows and writes none — the feature-off posture. Returns the row count.
      def rebuild!(catalog:, registry:)
        catalog[:document_facets].where(facet: FACET).delete
        return 0 unless registry

        count = 0
        batch = []
        each_language_document(catalog) do |row|
          value = resolved_value(registry, row)
          next unless value

          batch << { document_id: row[:id], facet: FACET, value: value }
          next unless batch.size >= INSERT_BATCH

          catalog[:document_facets].multi_insert(batch)
          count += batch.size
          batch = []
        end
        catalog[:document_facets].multi_insert(batch)
        count + batch.size
      end

      # Recompute ONE document's row (the journal CLI's post-ruling hook).
      # Unknown urn is a no-op; a resolution back to identity removes the row.
      def refresh_document!(catalog:, registry:, urn:)
        row = catalog[:documents]
              .join(:sources, id: :source_id)
              .where(Sequel[:documents][:urn] => urn)
              .select(Sequel[:documents][:id].as(:id), Sequel[:documents][:urn].as(:urn),
                      Sequel[:documents][:language].as(:language), Sequel[:sources][:slug].as(:slug))
              .first
        return unless row

        catalog[:document_facets].where(document_id: row[:id], facet: FACET).delete
        value = registry && resolved_value(registry, row)
        catalog[:document_facets].insert(document_id: row[:id], facet: FACET, value: value) if value
      end

      # Has a materialization ever run on this catalog? The query-path
      # feature detect: no rows at all -> `--lect` falls back to the P57-4
      # (language, source) pair resolution, byte-identical legacy behavior.
      def materialized?(catalog)
        !catalog[:document_facets].where(facet: FACET).first.nil?
      end

      def resolved_value(registry, row)
        resolved = registry.resolve(row[:language], source: row[:slug], urn: row[:urn])
        resolved == row[:language] ? nil : resolved
      end

      def each_language_document(catalog, &)
        catalog[:documents]
          .join(:sources, id: :source_id)
          .exclude(Sequel[:documents][:language] => nil)
          .where(Sequel[:documents][:withdrawn] => false)
          .select(Sequel[:documents][:id].as(:id), Sequel[:documents][:urn].as(:urn),
                  Sequel[:documents][:language].as(:language), Sequel[:sources][:slug].as(:slug))
          .each(&)
      end
      private_class_method :resolved_value, :each_language_document
    end
  end
end
