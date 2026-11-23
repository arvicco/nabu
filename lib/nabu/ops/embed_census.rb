# frozen_string_literal: true

module Nabu
  module Ops
    # The embed census (`rake aggregates:embed_census`): fills the
    # source_aggregates table's vector_coverage_count column (migration
    # 054) — per source, the LIVE passages (live-on-live, the
    # passages_count rules) whose urn holds a +model+ row in
    # vectors.sqlite3.
    #
    # EXPLICIT ONLY, never on the sync or rebuild path: vectors.sqlite3
    # outlives rebuilds while source_aggregates does not, so after a
    # rebuild the column reads NULL (honestly unknown) until this runs
    # again. Presence only — no text hashing, so it is a bounded index
    # walk, never the hour-class freshness census (`nabu embed --status`
    # keeps the fresh/stale verdict): keyset pages of vector urns off the
    # vectors' (model, urn) primary key, each page resolved through the
    # catalog's unique urn index (the CatalogJoin two-step — two
    # connections, no ATTACH; the vectors connection may be read-only).
    #
    # Lives in ops/ (outside the shared derivation core) on purpose: it is
    # a standalone writer no rebuild ever runs, so it must not move the
    # core digest every derivation stamp is held against.
    module EmbedCensus
      VECTORS_TABLE = :vectors # Nabu::Embed::VECTORS_TABLE
      PAGE = 1_000

      module_function

      # Walk, tally, and re-set every aggregates row in one transaction:
      # tallied sources get their count, the rest 0 (known: nothing
      # embedded). Returns { source_id => count }, or nil on a catalog
      # predating the table. +progress+ is called with the vector rows
      # walked so far, once per page.
      def run!(catalog:, vectors:, model:, page: PAGE, progress: nil)
        return nil unless Store::SourceAggregates.available?(catalog)

        tally = tally(catalog, vectors, model, page, progress)
        table = catalog[Store::SourceAggregates::TABLE]
        now = Time.now
        catalog.transaction do
          table.update(vector_coverage_count: 0, updated_at: now)
          tally.each do |source_id, count|
            table.insert_conflict(target: :source_id, update: { vector_coverage_count: count, updated_at: now })
                 .insert(source_id: source_id, vector_coverage_count: count, updated_at: now)
          end
        end
        tally
      end

      def tally(catalog, vectors, model, page, progress)
        return {} unless vectors.table_exists?(VECTORS_TABLE)

        tally = Hash.new(0)
        cursor = ""
        seen = 0
        loop do
          after = vectors[VECTORS_TABLE].where(model: model).where { urn > cursor }
          urns = after.order(:urn).limit(page).select_map(:urn)
          break if urns.empty?

          cursor = urns.last
          seen += urns.size
          live_sources_for(catalog, urns).each { |source_id, count| tally[source_id] += count }
          progress&.call(seen)
        end
        tally.to_h
      end

      def live_sources_for(catalog, urns)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:passages][:urn] => urns, Sequel[:passages][:withdrawn] => false,
                 Sequel[:documents][:withdrawn] => false)
          .group_and_count(Sequel[:documents][:source_id])
          .to_hash(:source_id, :count)
      end
    end
  end
end
