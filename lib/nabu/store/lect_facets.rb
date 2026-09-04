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
      # The lect census (lect_stats, migration 023) derives in the same
      # breath — the write-time-census stance (source_stats/P42-0): reads
      # never aggregate the half-million-row facet, and the numbers cannot
      # drift from the facet they summarize.
      def rebuild!(catalog:, registry:, progress: nil)
        catalog[:document_facets].where(facet: FACET).delete
        unless registry
          derive_stats!(catalog)
          return 0
        end

        # The no-silent-passes rule (owner, restated 2026-09-04 on this
        # exact command): this walks EVERY language document — minutes at
        # library scale — so it announces and ticks.
        progress&.stage("lect facet: re-materializing every document's resolution " \
                        "(minutes at library scale)")
        count = 0
        batch = []
        each_language_document(catalog) do |row|
          resolution = resolved(registry, row)
          next unless resolution

          batch << { document_id: row[:id], facet: FACET, value: resolution.id, raw: resolution.basis }
          next unless batch.size >= INSERT_BATCH

          catalog[:document_facets].multi_insert(batch)
          count += batch.size
          progress&.load_tick(count, 0)
          batch = []
        end
        catalog[:document_facets].multi_insert(batch)
        progress&.stage("lect facet: deriving the census stats")
        derive_stats!(catalog)
        count + batch.size
      end

      # Recompute ONE document's row (the journal CLI's post-ruling hook).
      # Unknown urn is a no-op; a resolution back to identity removes the row.
      # The affected census rows (old value, new value, the bare code) are
      # re-counted EXACTLY — never incremented — so the stats stay drift-free
      # without the wholesale pass.
      def refresh_document!(catalog:, registry:, urn:)
        row = catalog[:documents]
              .join(:sources, id: :source_id)
              .where(Sequel[:documents][:urn] => urn)
              .select(Sequel[:documents][:id].as(:id), Sequel[:documents][:urn].as(:urn),
                      Sequel[:documents][:language].as(:language), Sequel[:sources][:slug].as(:slug))
              .first
        return unless row

        old_value = catalog[:document_facets].where(document_id: row[:id], facet: FACET).get(:value)
        catalog[:document_facets].where(document_id: row[:id], facet: FACET).delete
        resolution = registry && resolved(registry, row)
        if resolution
          catalog[:document_facets].insert(document_id: row[:id], facet: FACET,
                                           value: resolution.id, raw: resolution.basis)
        end
        refresh_stats_for!(catalog, values: [old_value, resolution&.id].compact.uniq,
                                    codes: [row[:language]].compact)
      end

      # The wholesale census: one aggregation pass at WRITE time (the whole
      # point — `nabu language` reads these as indexed lookups). Skips
      # silently on a pre-023 catalog.
      def derive_stats!(catalog)
        return unless catalog.table_exists?(:lect_stats)

        catalog[:lect_stats].delete
        lect_rows = catalog[:document_facets]
                    .join(:documents, id: :document_id)
                    .where(Sequel[:document_facets][:facet] => FACET,
                           Sequel[:documents][:withdrawn] => false)
                    .group(Sequel[:document_facets][:value])
                    .select { [document_facets[:value].as(:key), count.function.*.as(:documents)] }
                    .map { |row| { kind: "lect", key: row[:key], documents: row[:documents] } }
        bare_rows = catalog[:documents]
                    .where(withdrawn: false).exclude(language: nil)
                    .exclude(id: catalog[:document_facets].where(facet: FACET).select(:document_id))
                    .group(:language)
                    .select { [language.as(:key), count.function.*.as(:documents)] }
                    .map { |row| { kind: "bare", key: row[:key], documents: row[:documents] } }
        (lect_rows + bare_rows).each_slice(INSERT_BATCH) { |slice| catalog[:lect_stats].multi_insert(slice) }
      end

      # Exact re-count of the named census keys (a hand ruling touches at
      # most two lect values and one bare code).
      def refresh_stats_for!(catalog, values:, codes:)
        return unless catalog.table_exists?(:lect_stats)

        values.each do |value|
          count = catalog[:document_facets]
                  .join(:documents, id: :document_id)
                  .where(Sequel[:document_facets][:facet] => FACET,
                         Sequel[:document_facets][:value] => value,
                         Sequel[:documents][:withdrawn] => false)
                  .count
          upsert_stat(catalog, kind: "lect", key: value, documents: count)
        end
        codes.each do |code|
          count = catalog[:documents]
                  .where(withdrawn: false, language: code)
                  .exclude(id: catalog[:document_facets].where(facet: FACET).select(:document_id))
                  .count
          upsert_stat(catalog, kind: "bare", key: code, documents: count)
        end
      end

      # Has a materialization ever run on this catalog? The query-path
      # feature detect: no rows at all -> `--lect` falls back to the P57-4
      # (language, source) pair resolution, byte-identical legacy behavior.
      def materialized?(catalog)
        !catalog[:document_facets].where(facet: FACET).first.nil?
      end

      def upsert_stat(catalog, kind:, key:, documents:)
        if documents.zero?
          catalog[:lect_stats].where(kind: kind, key: key).delete
        elsif catalog[:lect_stats].where(kind: kind, key: key).update(documents: documents) != 1
          catalog[:lect_stats].insert(kind: kind, key: key, documents: documents)
        end
      end

      # The document's non-identity Resolution (id + provenance basis), or
      # nil for identity (no row — the D58-e invariant). P81 U-5: the basis
      # is written into the facet row's raw column, so render surfaces can
      # join it back to the ruling's stated tier (Nabu::LectGloss) without
      # re-resolving — the raw column is exactly the facet family's
      # "upstream verbatim" slot (migration 009).
      def resolved(registry, row)
        resolution = registry.resolution(row[:language], source: row[:slug], urn: row[:urn])
        resolution.id == row[:language] ? nil : resolution
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
      private_class_method :resolved, :each_language_document, :upsert_stat
    end
  end
end
