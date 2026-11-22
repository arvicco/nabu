# frozen_string_literal: true

# Nabu::Store::Indexer — the bulk slice mode internals and the slice-pending marker.
# A partial of lib/nabu/store/indexer.rb, which loads it.
module Nabu
  module Store
    module Indexer
      module_function

      # -- the bulk slice mode internals (P111-1) ----------------------------

      # The FTS5 tables the deferred-merge recipe governs: EVERY slice write
      # against the contentless shape, whatever its size (the constants'
      # ndl-kotenseki note — the hazard is the index's tombstone debt, so
      # the write's size cannot gate it); a legacy contentful file gets []
      # and keeps the old untouched path. The cjk lane joins whenever it
      # exists — its slice shares the same delete+insert mechanics. The
      # trigram lane stays out: contentful shape, and its scoped sources
      # (documentary shelves) never reach bulk size.
      def governed_fts_tables(fulltext)
        return [] unless fts_contentless?(fulltext)

        [TABLE] + (fulltext.table_exists?(CJK_TABLE) ? [CJK_TABLE] : [])
      end

      # -- the slice-pending marker + freshness stamp (P111-1b, P112-3) ------
      # P112-3 generalizes the pending marker into a FRESHNESS
      # STAMP: a finished slice records the catalog state it serves (the
      # source's live row count + max passage id at finish). Health
      # cross-checks the stamp against the live catalog, so any skip-gate
      # hole that leaves a slice behind the catalog is a VISIBLE finding
      # instead of a silent staleness (the P111 lesson, generalized). An
      # absent stamp is NOT stale — a full rebuild clears the table and
      # makes everything fresh by construction.

      def create_slice_refreshes_table(fulltext)
        fulltext.create_table?(SLICE_REFRESHES_TABLE) do
          String :slug, primary_key: true
          String :started_at, null: false
          String :finished_at
          Integer :live_rows
          Integer :max_passage_id
          String :shape # "atomic" | "bulk" — CENSUS_BASELINES_TABLE note
        end
        ensure_slice_stamp_columns(fulltext)
      end

      # A slice_refreshes table minted by P111 code lacks the stamp
      # columns — add them in place (additive, nullable: old rows simply
      # carry no stamp until their next refresh).
      def ensure_slice_stamp_columns(fulltext)
        columns = fulltext[SLICE_REFRESHES_TABLE].columns
        fulltext.alter_table(SLICE_REFRESHES_TABLE) do
          add_column :live_rows, Integer unless columns.include?(:live_rows)
          add_column :max_passage_id, Integer unless columns.include?(:max_passage_id)
          add_column :shape, String unless columns.include?(:shape)
        end
      end

      # +shape+ records the run's transaction shape (the census heal's
      # question); nil — the index watcher's hygiene marking a killed
      # writer's slice — leaves the shape the run itself recorded.
      def mark_slice_pending!(fulltext, slug, shape: nil)
        create_slice_refreshes_table(fulltext)
        update = { started_at: Time.now.utc.iso8601, finished_at: nil, live_rows: nil, max_passage_id: nil }
        update[:shape] = shape if shape
        fulltext[SLICE_REFRESHES_TABLE]
          .insert_conflict(target: :slug, update: update)
          .insert(slug: slug, started_at: Time.now.utc.iso8601, finished_at: nil, shape: shape)
      end

      # The shape the slice's last run recorded, nil when unrecorded.
      def slice_shape(fulltext, slug)
        return nil unless fulltext.table_exists?(SLICE_REFRESHES_TABLE)
        return nil unless fulltext[SLICE_REFRESHES_TABLE].columns.include?(:shape)

        fulltext[SLICE_REFRESHES_TABLE].where(slug: slug).get(:shape)
      end

      def mark_slice_finished!(fulltext, slug, live_rows: nil, max_passage_id: nil)
        fulltext[SLICE_REFRESHES_TABLE].where(slug: slug)
                                       .update(finished_at: Time.now.utc.iso8601,
                                               live_rows: live_rows, max_passage_id: max_passage_id)
      end

      # The freshness stamps, slug-keyed — a P111-era table without the
      # stamp columns reads back rows whose [:live_rows] is simply nil (no
      # ALTER here: health reads through READ-ONLY handles). Empty hash
      # when the table is absent.
      def slice_stamps(fulltext)
        return {} unless fulltext.table_exists?(SLICE_REFRESHES_TABLE)

        fulltext[SLICE_REFRESHES_TABLE].all.to_h { |row| [row[:slug], row] }
      end

      # The catalog state a finished slice serves: [live row count, max
      # live passage id]. Two bounded B-tree queries.
      def source_live_stats(catalog, slug)
        scope = catalog[:passages]
                .join(:documents, id: Sequel[:passages][:document_id])
                .join(:sources, id: Sequel[:documents][:source_id])
                .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
                .where(Sequel[:sources][:slug] => slug)
        [scope.count, scope.max(Sequel[:passages][:id])]
      end

      # Whether +slug+'s last slice refresh never finished (a crashed run —
      # the index is behind the catalog). Absent table = nothing pending
      # (fresh rebuild, or a pre-P111 file whose slices all completed under
      # the old monolithic-transaction shape).
      def slice_pending?(fulltext, slug)
        return false unless fulltext.table_exists?(SLICE_REFRESHES_TABLE)

        !fulltext[SLICE_REFRESHES_TABLE].where(slug: slug, finished_at: nil).empty?
      end

      # The pending marker's blind spot (live 2026-10-14: two first syncs
      # lost their index step to a catalog lock held by a concurrent crawl;
      # the idempotent retries skipped the slice): the marker is written at
      # refresh START, so a sync whose load lands rows but dies before the
      # reindex ever begins leaves no row at all — pending? sees nothing.
      # This probe asks the index itself: a slice is BEHIND when the
      # source's max live passage id is absent from passages_fts (every
      # indexed passage lands there — the CJK/trigram lanes are additive).
      # O(1): one bounded B-tree max + one fts rowid lookup. A source with
      # no live passages is vacuously current.
      def slice_behind?(fulltext, catalog, slug)
        _count, max_id = source_live_stats(catalog, slug)
        return false if max_id.nil?

        fulltext[TABLE].where(rowid: max_id).empty?
      end

      # The slice body's transaction shape (constants note): the ordinary
      # slice is one atomic swap; a bulk slice autocommits per statement
      # batch (auto-checkpoint keeps the WAL bounded between batches) and
      # TRUNCATE-checkpoints when the pass completes.
      def slice_write_unit(fulltext, bulk:, progress: nil, &)
        return fulltext.transaction(&) unless bulk

        yield
        checkpoint_wal!(fulltext, progress: progress)
      end

      # PRAGMA has no Sequel-dataset form — rides this file's documented
      # raw-SQL exception (DDL/maintenance statements only). Harmless on an
      # in-memory db (busy 0, log/checkpointed -1).
      #
      # Returns the engine's answer row as { busy:, log:, checkpointed: }
      # and announces through +progress+ when busy is nonzero: TRUNCATE
      # degrades SILENTLY against a reader pinning an old snapshot (a
      # long-lived `nabu mcp`, a desk query mid-scan) — the frames past
      # that reader's mark stay in the WAL, the file never shrinks, and
      # the run reads as "checkpointed" unless somebody looks at the row.
      def checkpoint_wal!(fulltext, progress: nil)
        row = fulltext.fetch("PRAGMA wal_checkpoint(TRUNCATE)").first || {}
        result = { busy: row[:busy].to_i, log: row[:log].to_i, checkpointed: row[:checkpointed].to_i }
        if result[:busy].positive?
          remaining = [result[:log] - result[:checkpointed], 0].max
          progress&.stage("wal checkpoint refused (reader pinning) — #{remaining} frames remain")
        end
        result
      end

      # Apply the deferred-merge settings around the block and ALWAYS
      # restore the defaults — the settings are persisted index config, so
      # an exception must not leave a never-merging index behind. The
      # ensure arm cannot cover a SIGKILL, so each table's restore is
      # JOURNALED before its bulk setting applies (Store::EngineIntents):
      # a killed run's restore replays on the next read-write connect.
      def with_bulk_write_mode(fulltext, tables)
        return yield if tables.empty?

        intents = []
        begin
          tables.each do |table|
            intents << EngineIntents.journal!(fulltext, table: table, restore: DEFAULT_MERGE_SETTINGS)
            apply_merge_settings(fulltext, table, BULK_MERGE_SETTINGS)
          end
          yield
        ensure
          tables.each { |table| apply_merge_settings(fulltext, table, DEFAULT_MERGE_SETTINGS) }
          EngineIntents.clear!(fulltext, intents)
        end
      end

      # FTS5 config commands ride the special INSERT form
      # (`INSERT INTO t(t, rank) VALUES('automerge', 0)`) — expressed as a
      # Sequel dataset insert, so the raw-DDL exception does not widen.
      def apply_merge_settings(fulltext, table, settings)
        settings.each { |key, value| fulltext[table].insert(table => key, :rank => value) }
      end

      # The merge PROBE after every governed slice write — its own
      # announced stage, AFTER the defaults are restored (crash-safe order)
      # and outside the write's transaction: ONE bounded chunk per table
      # (SYNC_PROBE_CHUNKS), never a consolidation to completion. The
      # maintenance rail (Store::IndexMaintenance, `nabu index maintain`)
      # owns consolidation — the proportionality law keeps the sync path
      # O(Δ), and an index's standing merge debt is O(index), not O(Δ): the
      # 2026-11 ndl delta that hung 5h+ was paying exactly that debt inline.
      # Debt the probe leaves is REPORTED (IndexMaintenance.debt_line) as a
      # durable note naming the rail. On a debt-free index the probe is one
      # no-op chunk per table, exactly as before.
      def consolidate_deferred_merges!(fulltext, tables, slug:, ledger: nil, progress: nil)
        return if tables.empty?

        timed_sync_stage(ledger, slug, "fts_merge",
                         "index slice: #{slug} — merge consolidation probe (one bounded chunk per table)",
                         progress) do
          tables.each do |table|
            consolidate_merges!(fulltext, table, progress: progress, max_chunks: SYNC_PROBE_CHUNKS)
            line = IndexMaintenance.debt_line(fulltext, table)
            progress&.note(line) if line
          end
        end
      end
      SYNC_PROBE_CHUNKS = 1

      # Positive incremental merges until the total_changes probe reports a
      # no-op call (< 2 — the documented completion signal), or until
      # +max_chunks+ chunks ran (the sync path's probe). Proportional to
      # the debt it consumes; ticks so an hours-scale consolidation (the
      # maintenance rail's) is never silent.
      def consolidate_merges!(fulltext, table, progress: nil, max_chunks: nil)
        chunks = 0
        loop do
          worked = merge_chunk!(fulltext, table) >= MERGE_NOOP_LINE
          chunks += 1
          if (chunks % 25).zero?
            progress&.stage("fts merge: #{table} — chunk #{chunks}")
            checkpoint_wal!(fulltext, progress: progress) # merges rewrite pages too — keep the WAL bounded
          end
          break unless worked
          break if max_chunks && chunks >= max_chunks
        end
        checkpoint_wal!(fulltext, progress: progress)
        chunks
      end

      # ONE bounded positive merge step — its own statement (autocommit
      # outside a transaction), at most MERGE_CHUNK_PAGES pages of work.
      # Returns the total_changes delta the step caused: the probe counts
      # the command row itself (1) plus every page the merge wrote, so
      # below MERGE_NOOP_LINE is the documented no-op completion signal.
      # Positive merges run with deletemerge=0 active — the deferral
      # governs only the engine's own delete-triggered merges.
      def merge_chunk!(fulltext, table)
        before = total_changes(fulltext)
        fulltext[table].insert(table => "merge", :rank => MERGE_CHUNK_PAGES)
        total_changes(fulltext) - before
      end
      MERGE_NOOP_LINE = 2

      def total_changes(fulltext)
        fulltext.synchronize(&:total_changes)
      end
    end
  end
end
