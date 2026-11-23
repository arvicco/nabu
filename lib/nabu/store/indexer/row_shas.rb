# frozen_string_literal: true

# Nabu::Store::Indexer — the row-sha sidecar and the exact heal diff.
# A partial of lib/nabu/store/indexer.rb, which loads it.
module Nabu
  module Store
    module Indexer
      module_function

      # -- the row-sha sidecar (ROW_SHAS_TABLE note) ---------------------------

      # Bare at rebuild (+indexed: false+ — index_row_shas builds the
      # source_id B-tree in one pass after the streaming insert, the lemma
      # table's P36-2 trick); indexed at once when a full-slice rewrite
      # brings it to an older file. Idempotent.
      def create_row_shas_table(fulltext, indexed: true)
        return if fulltext.table_exists?(ROW_SHAS_TABLE)

        fulltext.create_table(ROW_SHAS_TABLE) do
          Integer :rowid, primary_key: true # = passages.id, the FTS rowid convention
          Integer :source_id, null: false
          File :sha, null: false # the first 8 bytes of the catalog content_sha256
        end
        index_row_shas(fulltext) if indexed
      end

      def index_row_shas(fulltext)
        fulltext.add_index(ROW_SHAS_TABLE, :source_id, if_not_exists: true)
      end

      # The sidecar grain: the catalog's hex sha → its first 8 bytes.
      def row_sha(hex)
        Sequel.blob([hex.to_s[0, 16]].pack("H*"))
      end

      # Upsert one insert batch's shas (the batch's LAST statement).
      def write_row_shas(fulltext, batch)
        fulltext[ROW_SHAS_TABLE].insert_conflict(:replace).multi_insert(
          batch.map do |row|
            { rowid: row.fetch(:passage_id), source_id: row.fetch(:source_id),
              sha: row_sha(row.fetch(:content_sha256)) }
          end
        )
      end

      # Clear the doomed rows' shas — the FIRST destructive write of a
      # slice/delta/heal pass. No-op on a fulltext without the sidecar.
      def delete_row_shas(fulltext, ids)
        return unless fulltext.table_exists?(ROW_SHAS_TABLE)

        delete_rowid_slices(fulltext, ROW_SHAS_TABLE, ids)
      end

      # The exact heal's sets: +changed_ids+/+changed_urns+ — every row
      # to clear from the fts+lemma grain; +upserted_ids+ — the live ones
      # among them, to re-derive; +slice_ids+/+slice_urns+ — the source's
      # whole key set, for the lanes that keep their whole-slice heal.
      HealDiff = Data.define(:changed_ids, :changed_urns, :upserted_ids, :slice_ids, :slice_urns)

      # Diff the catalog's live (id, sha8) set for +source_id+ against the
      # sidecar's, or nil when the sidecar cannot answer (absent table,
      # legacy shape, or no rows for this source — the full-slice heal).
      # One ordered catalog pass merge-walks the sidecar slice, held as a
      # sorted id array + one packed byte string (16 bytes a row, never a
      # Hash of millions of strings). A row drifts when it is live but
      # unrecorded or recorded under another sha, or recorded but no longer
      # live. The one case the sidecar cannot see — a crashed run inserted a
      # row that a LATER load withdrew before this heal, leaving it neither
      # live nor recorded — is closed by probing the source's unrecorded
      # non-live ids against the index itself (rowid lookups, reads only).
      def exact_heal_diff(catalog, fulltext, source_id)
        return nil unless fts_contentless?(fulltext) && fulltext.table_exists?(ROW_SHAS_TABLE)

        recorded = fulltext[ROW_SHAS_TABLE].where(source_id: source_id).order(:rowid)
        return nil if recorded.empty?

        recorded_ids = []
        recorded_shas = +"".b
        recorded.select(:rowid, :sha).each do |row|
          recorded_ids << row[:rowid]
          recorded_shas << row[:sha].to_s.b
        end
        walk_heal_diff(catalog, fulltext, source_id, recorded_ids, recorded_shas)
      end

      def walk_heal_diff(catalog, fulltext, source_id, recorded_ids, recorded_shas)
        changed = Set.new
        changed_urns = []
        upserted = Set.new
        slice_ids = Set.new
        slice_urns = []
        unseen = [] # [id, urn] of non-live, unrecorded rows — probed below
        cursor = 0
        source_passage_states(catalog, source_id).each do |row|
          id = row.fetch(:passage_id)
          slice_ids << id
          slice_urns << row.fetch(:urn)
          while cursor < recorded_ids.size && recorded_ids[cursor] < id
            changed << recorded_ids[cursor] # recorded, but no longer the source's row at all
            cursor += 1
          end
          sha = nil
          if cursor < recorded_ids.size && recorded_ids[cursor] == id
            sha = recorded_shas.byteslice(cursor * 8, 8)
            cursor += 1
          end
          live = !row.fetch(:passage_withdrawn) && !row.fetch(:document_withdrawn)
          current = (row_sha(row.fetch(:content_sha256)).b if live)
          next if current == sha && !current.nil?

          if current.nil? && sha.nil?
            unseen << [id, row.fetch(:urn)]
            next
          end
          changed << id
          changed_urns << row.fetch(:urn)
          upserted << id if live
        end
        changed.merge(recorded_ids[cursor..])
        indexed_unseen(fulltext, unseen).each do |id, urn|
          changed << id
          changed_urns << urn
        end
        HealDiff.new(changed_ids: changed, changed_urns: changed_urns, upserted_ids: upserted,
                     slice_ids: slice_ids, slice_urns: slice_urns)
      end

      # Which of the [id, urn] pairs the index still holds (rowid lookups —
      # the slice_behind? read, batched).
      def indexed_unseen(fulltext, pairs)
        pairs.each_slice(BATCH_SIZE).flat_map do |batch|
          present = fulltext[TABLE].where(rowid: batch.map(&:first)).select_map(Sequel.lit("rowid")).to_set
          batch.select { |pair| present.include?(pair.first) }
        end
      end

      # Every passage of the source (withdrawn included — the
      # source_passage_keys scope) with its liveness and sha, in id order.
      def source_passage_states(catalog, source_id)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:documents][:source_id] => source_id)
          .order(Sequel[:passages][:id])
          .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:urn],
                  Sequel[:passages][:content_sha256],
                  Sequel[:passages][:withdrawn].as(:passage_withdrawn),
                  Sequel[:documents][:withdrawn].as(:document_withdrawn))
      end

      # Whether any of the slice's passages carries lemma rows — bounded
      # passage_id IN probes, stopping at the first hit.
      def source_lemma_rows?(fulltext, ids:)
        ids.to_a.each_slice(BATCH_SIZE).any? do |batch|
          !fulltext[LEMMA_TABLE].where(passage_id: batch).empty?
        end
      end

      # The contentless shape's delete (P93-1): rowid IS the catalog
      # passage id, so the source's rows delete by key — no streaming scan
      # at all (the legacy path below pays a full-table pass per sync).
      # contentless_delete=1 makes these real deletions. Returns the
      # number of rows deleted.
      # Governed tables tick the merge governor per batch: contentless
      # deletes write tombstones and flush segments like inserts do.
      def delete_fts_rows_by_rowid(fulltext, table, ids, progress: nil, ledger: nil)
        governor = fts_governor(fulltext, table, progress: progress, ledger: ledger)
        ids.to_a.each_slice(BATCH_SIZE).sum do |batch|
          deleted = fulltext[table].where(rowid: batch).delete
          governor&.tick!
          deleted
        end
      end

      # Delete the source's rows from a LEGACY contentful FTS5 table: one
      # streaming scan collects the rowids whose passage_id is in +ids+
      # (passage_id is UNINDEXED — per-batch IN deletes would each rescan
      # the table), then targeted rowid deletes. Returns the number of
      # rows deleted. (The trigram table still uses this shape.)
      def delete_fts_rows(fulltext, table, ids)
        return 0 if ids.empty?

        doomed = []
        fulltext[table].select(:rowid, :passage_id).each do |row|
          doomed << row.fetch(:rowid) if ids.include?(row.fetch(:passage_id))
        end
        doomed.each_slice(BATCH_SIZE) { |batch| fulltext[table].where(rowid: batch).delete }
        doomed.size
      end

      # Delete the source's lemma rows by passage_id (B-tree indexed — no
      # scan). Returns the number of rows deleted. A retired v1 table
      # refuses here, before the slice's first lemma write.
      def delete_source_lemma_rows(fulltext, ids:)
        require_v2_lemmas!(fulltext)
        ids.to_a.each_slice(BATCH_SIZE).sum do |batch|
          fulltext[LEMMA_TABLE].where(passage_id: batch).delete
        end
      end
    end
  end
end
