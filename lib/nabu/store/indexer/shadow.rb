# frozen_string_literal: true

# Nabu::Store::Indexer — the shadow forecast and the shadow build (above-budget rewrites).
# A partial of lib/nabu/store/indexer.rb, which loads it.
module Nabu
  module Store
    module Indexer
      module_function

      # == The shadow forecast: delta-engaged is not delta-priced
      #
      # MEASURED (2026-11-21): a two-source `index refresh` whose ledger
      # priced its per-source slices at ~13 min was killed three times at
      # its watcher deadline — each time deep inside the passages_fts
      # shadow build, a ~95M-row append into a fresh table with the fts
      # governor consolidating the shadow's level-0 segments as it grew.
      # The refreshed slices were the DELTA; the shadow is the whole
      # index, so the stage that dominated the run was the one the
      # deadline never priced, and a kill inside it discards everything
      # (the orphan shadow is dropped at the next entry; the governor's
      # relief chunks run inside the build's commit groups) — kill + retry
      # restarted from zero. A clean never-kill run took 73m33s.
      #
      # So the refresh PREDICTS the shadow before it starts, from the very
      # state refresh_source!/refresh_sources! decide on: each member's
      # slice volume (slice_plan's key set — the source's every passage on
      # the whole-slice grain, the exact heal diff over a pending marker)
      # against +row_budget+, the contentless shape, and shadow_ready?'s
      # sidecar completeness; a wave over budget takes ONE corpus-scoped
      # shadow, else each member decides alone. Returns one ShadowForecast
      # per predicted build — +scope+ the ledger scope the build records
      # under (the slug, or "corpus" for a wave), +slugs+ the refreshed
      # sources it serves, +rows+ the rows the
      # shadow will hold (the sidecar's rows outside the members plus the
      # members' live rows: exactly what build_fts_shadow! writes). Empty
      # when no shadow is coming. Read-only; whole-slice grain only (the
      # `index refresh` shape — a sync's load delta is not known before
      # its load, so the sync preflight never forecasts).
      ShadowForecast = Data.define(:scope, :slugs, :rows)

      def fts_shadow_forecasts(catalog:, fulltext:, slugs:, row_budget: IN_PLACE_ROW_BUDGET)
        return [] unless incremental_ready?(fulltext) && fts_contentless?(fulltext)

        source_ids = catalog[:sources].where(slug: slugs.uniq).to_hash(:slug, :id)
        members = slugs.uniq.select { |slug| source_ids[slug] }
        volumes = members.to_h { |slug| [slug, forecast_volume(catalog, fulltext, slug, source_ids[slug])] }
        ids_of = ->(group) { group.map { |slug| source_ids[slug] } }
        if members.size > 1 && volumes.values.sum > row_budget && shadow_ready?(catalog, fulltext, ids_of.call(members))
          return [shadow_forecast(catalog, fulltext, "corpus", members, ids_of.call(members))]
        end

        members.filter_map do |slug|
          next unless volumes[slug] > row_budget && shadow_ready?(catalog, fulltext, source_ids[slug])

          shadow_forecast(catalog, fulltext, slug, [slug], ids_of.call([slug]))
        end
      end

      # A member's slice volume as slice_plan would measure it — the
      # source's every passage (withdrawn included) on the rewrite path,
      # counted rather than loaded; the exact heal diff when a pending
      # marker makes the run a heal.
      def forecast_volume(catalog, fulltext, slug, source_id)
        if slice_pending?(fulltext, slug)
          return slice_plan(catalog, fulltext, slug: slug, source_id: source_id).ids.size
        end

        catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                          .where(Sequel[:documents][:source_id] => source_id).count
      end

      def shadow_forecast(catalog, fulltext, scope, members, member_ids)
        recorded = fulltext[ROW_SHAS_TABLE].exclude(source_id: member_ids).count
        live = shadow_catalog_rows(catalog)
               .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
               .where(Sequel[:documents][:source_id] => member_ids).count
        ShadowForecast.new(scope: scope, slugs: members, rows: recorded + live)
      end

      # -- the shadow build (SHADOW_TABLE note) -----------------------------

      # Whether this run's main-index write goes to a shadow: over the
      # budget, contentless shape (a legacy contentful file keeps its old
      # path, like every recipe of this family), and a sidecar complete
      # enough to name the old table's membership — else in place,
      # announced.
      def shadow_main?(catalog, fulltext, ids, row_budget, source_id:, slug:, progress: nil)
        return false unless ids.size > row_budget && fts_contentless?(fulltext)
        return true if shadow_ready?(catalog, fulltext, source_id)

        progress&.stage("index slice: #{slug} — #{ids.size} rows over the #{row_budget}-row in-place budget, " \
                        "but the row-sha sidecar incomplete (a slice predating it): writing in place " \
                        "under the governor until a full rebuild backfills it")
        false
      end

      # The sidecar names every OTHER source's indexed membership: each
      # source either has sidecar rows, or no indexed rows at all (its
      # first and last live passages probed in the index — a slice that
      # predates the sidecar was written whole, so both would be there).
      # O(sources) point lookups.
      def shadow_ready?(catalog, fulltext, source_id)
        return false unless fulltext.table_exists?(ROW_SHAS_TABLE)

        catalog[:sources].exclude(id: source_id).select_map(:id).all? do |other|
          next true unless fulltext[ROW_SHAS_TABLE].where(source_id: other).empty?

          scope = live_passages(catalog).where(Sequel[:documents][:source_id] => other)
          probes = [scope.min(Sequel[:passages][:id]), scope.max(Sequel[:passages][:id])].compact
          probes.empty? || fulltext[TABLE].where(rowid: probes).empty?
        end
      end

      # Build SHADOW_TABLE as an append-only linear pass (class note):
      # every sidecar-recorded row of the other sources, re-derived from
      # the catalog by id, then the refreshing source's live rows. Batch-
      # ticked, governed, committed every SHADOW_COMMIT_BATCHES batches.
      # Returns the rows written. +source_id+ may be one id or a wave's
      # array of them (refresh_sources!): the refreshed set's live rows,
      # everyone else's recorded ones.
      def build_fts_shadow!(catalog:, fulltext:, source_id:, progress: nil)
        fulltext.drop_table?(SHADOW_TABLE)
        fulltext.run(CREATE_TABLE.sub("passages_fts", SHADOW_TABLE.to_s))
        slugs = source_slugs(catalog)
        governor = FtsGovernor.new(fulltext: fulltext, table: SHADOW_TABLE, progress: progress)
        count = 0
        shadow_rows(catalog, fulltext, source_id).each_slice(BATCH_SIZE * SHADOW_COMMIT_BATCHES) do |group|
          fulltext.transaction do
            group.each_slice(BATCH_SIZE) do |batch|
              fulltext[SHADOW_TABLE].multi_insert(
                batch.map { |row| fts_row(row, language: true, source_slugs: slugs, contentless: true) }
              )
              count += batch.size
              progress&.load_tick(count, 0) if batch.size == BATCH_SIZE
              governor.tick!
            end
          end
        end
        checkpoint_wal!(fulltext, progress: progress)
        count
      end

      # The swap: one transaction drops the old table whole (pages to the
      # freelist — no tombstones, no merges) and renames the shadow over
      # it (fts5's xRename carries its shadow tables along).
      def swap_fts_shadow!(fulltext)
        fulltext.transaction do
          fulltext.drop_table(TABLE)
          fulltext.rename_table(SHADOW_TABLE, TABLE)
        end
      end

      # The shadow's row stream: the sidecar-keyed membership of the other
      # sources (paged by rowid — never the whole id set in memory), then
      # the refreshing source's live rows.
      def shadow_rows(catalog, fulltext, source_id)
        Enumerator.new do |y|
          last = 0
          loop do
            others = fulltext[ROW_SHAS_TABLE].exclude(source_id: source_id)
            page = others.where { rowid > last }.order(:rowid).limit(BATCH_SIZE).select_map(:rowid)
            break if page.empty?

            shadow_catalog_rows(catalog).where(Sequel[:passages][:id] => page).each { |row| y << row }
            last = page.last
          end
          shadow_catalog_rows(catalog)
            .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
            .where(Sequel[:documents][:source_id] => source_id).each { |row| y << row }
        end
      end

      # The lean four-column row fts_row needs — no liveness filter: a
      # recorded row the old table still holds (a withdrawal not yet
      # refreshed) is membership the shadow must keep.
      def shadow_catalog_rows(catalog)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .select(Sequel[:passages][:text_search].as(:text_normalized), Sequel[:passages][:id].as(:passage_id),
                  Sequel[:passages][:language], Sequel[:documents][:source_id].as(:source_id))
      end

      # Whether this refresh writes the source's trigram slice at all:
      # flagged now, or indexed by the last build (refresh_trigram_slice's
      # own hands-off rule).
      def trigram_touched?(fulltext, slug, fuzzy_slugs)
        fuzzy_slugs.include?(slug) || !fulltext[TRIGRAM_SCOPE_TABLE].where(slug: slug).empty?
      end
    end
  end
end
