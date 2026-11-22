# frozen_string_literal: true

# Nabu::Store::Indexer — the trigram and CJK lanes (rebuild + slice refresh).
# A partial of lib/nabu/store/indexer.rb, which loads it.
module Nabu
  module Store
    module Indexer
      module_function

      # Drop and rebuild the trigram fragment index (class note) over the live
      # passages of the +fuzzy_slugs+ sources, and record that scope. A second
      # streaming pass rather than a branch in the main one: the scope is a
      # small subset of the corpus, and the fts/lemma pass stays untouched.
      # Returns the number of passages trigram-indexed.
      # The lane lives in its own file (Store::Lanes): the build readies the
      # lane schema and qualifies its DDL; the inserts stay unqualified.
      # The build runs through Lanes.build!'s crash-honest swap: a fresh
      # file, renamed over the serving one only once complete.
      def rebuild_trigram!(catalog:, fulltext:, fuzzy_slugs:)
        Lanes.build!(fulltext, Lanes::TRIGRAM) do |schema|
          fulltext.run(create_trigram_sql(schema))
          fulltext.create_table(Lanes.qualified(Lanes::TRIGRAM, TRIGRAM_SCOPE_TABLE)) do
            String :slug, null: false
          end

          count = 0
          fulltext.transaction do
            fulltext[TRIGRAM_SCOPE_TABLE].multi_insert(fuzzy_slugs.map { |slug| { slug: slug } })
            trigram_passages(catalog, fuzzy_slugs).each_slice(BATCH_SIZE) do |batch|
              fulltext[TRIGRAM_TABLE].multi_insert(batch.map { |row| index_row(row) })
              count += batch.size
            end
          end
          count
        end
      end

      # REBUILD-CADENCE (the 2026-11-11 maintenance ruling): the
      # rebuild-side lane refresh — with rebuild!'s own corpus stage, the
      # ONLY cjk writers. Rebuilds the lane WHOLE (drop + linear append:
      # no tombstones, no merge debt against a standing structure) when
      # the built scope drifted from the config flags, a flagged source
      # replayed, or the lane is missing; returns nil untouched otherwise.
      # The incremental rebuild calls this after its replays; syncs and
      # refreshes never do.
      def refresh_cjk_lane!(catalog:, fulltext:, cjk_slugs:, replayed_slugs:, progress: nil)
        flags = cjk_slugs.sort
        scope = fulltext.table_exists?(CJK_SCOPE_TABLE) &&
                fulltext[CJK_SCOPE_TABLE].select_map(:slug).sort
        return nil if scope == flags && !replayed_slugs.intersect?(flags)

        rebuild_cjk!(catalog: catalog, fulltext: fulltext, cjk_slugs: cjk_slugs, progress: progress)
      end

      # Drop and rebuild the CJK bigram lane (CJK_TABLE note) over the live
      # passages of the +cjk_slugs+ sources, and record that scope — the
      # announced, batch-ticked linear append (insert_cjk_batches). Returns
      # the number of passages indexed (runless passages contribute none).
      def rebuild_cjk!(catalog:, fulltext:, cjk_slugs:, progress: nil)
        # A flagless build is an instant table mint — announcing it would
        # only pollute the rebuild's stage record.
        progress&.stage("cjk bigram lane: rebuilding over #{cjk_slugs.size} flagged sources") if
          cjk_slugs.any?
        # Its own file, built through the crash-honest swap (Store::Lanes):
        # a death anywhere in here leaves the previous lane serving.
        Lanes.build!(fulltext, Lanes::CJK) do |schema|
          fulltext.run(create_cjk_sql(schema))
          fulltext.create_table(Lanes.qualified(Lanes::CJK, CJK_SCOPE_TABLE)) do
            String :slug, null: false
          end

          count = 0
          fulltext.transaction do
            fulltext[CJK_SCOPE_TABLE].multi_insert(cjk_slugs.map { |slug| { slug: slug } })
            count = insert_cjk_batches(fulltext, cjk_passages(catalog, cjk_slugs), progress: progress)
          end
          count
        end
      end

      # The trigram slice: refresh when the source is flagged now, drop its
      # rows (and scope row) when the last build indexed it but the flag is
      # gone, and stay entirely hands-off otherwise (class note on
      # refresh_source!).
      def refresh_trigram_slice(catalog, fulltext, slug, fuzzy_slugs, ids)
        fuzzy = fuzzy_slugs.include?(slug)
        in_scope = !fulltext[TRIGRAM_SCOPE_TABLE].where(slug: slug).empty?
        return unless fuzzy || in_scope

        delete_fts_rows(fulltext, TRIGRAM_TABLE, ids) if in_scope
        if fuzzy
          fulltext[TRIGRAM_SCOPE_TABLE].insert(slug: slug) unless in_scope
          trigram_passages(catalog, [slug]).each_slice(BATCH_SIZE) do |batch|
            fulltext[TRIGRAM_TABLE].multi_insert(batch.map { |row| index_row(row) })
          end
        else
          fulltext[TRIGRAM_SCOPE_TABLE].where(slug: slug).delete
        end
      end

      # The trigram lane at the delta grain (P112-1): changed rowids out,
      # upserted rows in — provided the flag and the scope row AGREE. On
      # config drift (newly flagged / de-flagged since the last build) the
      # lane's membership changes wholesale, so it delegates to the slice
      # routine with the full key set — the rare path pays the full fetch.
      def refresh_trigram_delta(catalog, fulltext, slug, fuzzy_slugs, delta)
        fuzzy = fuzzy_slugs.include?(slug)
        in_scope = !fulltext[TRIGRAM_SCOPE_TABLE].where(slug: slug).empty?
        return unless fuzzy || in_scope

        unless fuzzy && in_scope
          source_id = catalog[:sources].where(slug: slug).get(:id)
          ids, = source_passage_keys(catalog, source_id)
          return refresh_trigram_slice(catalog, fulltext, slug, fuzzy_slugs, ids)
        end

        delete_fts_rows(fulltext, TRIGRAM_TABLE, delta.changed_ids)
        ids_scoped(trigram_passages(catalog, [slug]), delta.upserted_ids).each_slice(BATCH_SIZE) do |batch|
          fulltext[TRIGRAM_TABLE].multi_insert(batch.map { |row| index_row(row) })
        end
      end

      # The rebuild-time CJK insert loop, governed and TICKED per full
      # batch (P105-5d — the 2026-11-11 stall ran the lane's writes over
      # millions of rows without a line of output). Returns the number of
      # rows landed (runless rows index nothing).
      def insert_cjk_batches(fulltext, rows, progress: nil, batch_size: BATCH_SIZE)
        governor = fts_governor(fulltext, CJK_TABLE, progress: progress)
        count = 0
        rows.each_slice(batch_size) do |batch|
          landed = batch.filter_map { |row| cjk_row(row) }
          fulltext[CJK_TABLE].multi_insert(landed)
          count += landed.size
          progress&.load_tick(count, 0) if batch.size == batch_size
          governor&.tick!
        end
        count
      end

      # The CJK pass's slice of live_passages: the trigram_passages shape
      # plus language and slug (both sentinel columns ride every row).
      def cjk_passages(catalog, slugs)
        return [] if slugs.empty?

        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .where(Sequel[:sources][:slug] => slugs)
          .select(
            Sequel[:passages][:text_search].as(:text_normalized),
            Sequel[:passages][:id].as(:passage_id),
            Sequel[:passages][:language],
            Sequel[:sources][:slug].as(:source_slug)
          )
      end

      # One passage's CJK-lane row, or nil when its text carries no run.
      def cjk_row(row)
        cjk = CjkBigrams.index_text(row.fetch(:text_normalized))
        return nil unless cjk

        { rowid: row.fetch(:passage_id), cjk: cjk,
          language: language_token(row[:language]),
          source: source_token(row.fetch(:source_slug)) }
      end
    end
  end
end
