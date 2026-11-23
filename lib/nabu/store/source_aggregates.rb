# frozen_string_literal: true

require "time"

module Nabu
  module Store
    # The source_aggregates DERIVED table (migration 054): O(1) per-source
    # library accounting — live document/passage counts plus the fulltext
    # slice's membership and freshness — maintained AT WRITE TIME so census,
    # status and delta reads stop walking the catalog (or probing the index
    # file) per invocation. The read seam is .fetch / .all / .rollup.
    #
    # == Who writes what (one writer per column family)
    #
    # - documents_count / passages_count: SourceStats::Maintainer moves them
    #   by the very per-document delta it applies to source_stats, inside
    #   the loader's document transaction (.move_counts!); the wholesale
    #   SourceStats.derive! re-sets them in its own transaction
    #   (.set_counts!). Same census rules as source_stats by construction.
    # - fts_behind (true): the Loader, inside the transaction that moved an
    #   index-visible row (an added document, a content revision or
    #   restore, a sweep withdrawal — exactly LoadReport#passages_changed?,
    #   the signal the sync's reindex decision reads), once per load
    #   (Tracker). A load that lands and dies before its reindex therefore
    #   reads behind with no probe at all.
    # - fts_member_count / fts_behind (false) / last_index_refresh_at: the
    #   index refresh call sites, right after Indexer.refresh_source! /
    #   refresh_sources! return (.index_refreshed! — the refresh's return
    #   value IS the slice's live membership) and after a full
    #   Indexer.rebuild! (.index_rebuilt! — every live passage is indexed by
    #   construction). The hooks sit at the callers, not inside the indexer:
    #   the indexer files are the fulltext-index core (DerivationFingerprint
    #   INDEX_CORE_FILES), which by membership rule never write a catalog row.
    # - vector_coverage_count: reserved; nothing writes it yet (migration
    #   054 note).
    #
    # == Derivability
    #
    # Derived data: `nabu rebuild` re-derives every column (migration note);
    # .backfill! is the one-time population of a pre-054 live catalog
    # (`rake aggregates:backfill`). .drift is the sampled truth cross-check.
    module SourceAggregates
      TABLE = :source_aggregates

      # One source's aggregates. fts_* / last_index_refresh_at /
      # vector_coverage_count are nil when unknown.
      Row = Data.define(:source_id, :documents_count, :passages_count, :fts_member_count, :fts_behind,
                        :last_index_refresh_at, :vector_coverage_count)

      COLUMNS = Row.members

      module_function

      # Feature detection: a catalog predating migration 054 has no table —
      # every writer below is then a no-op and readers fall back.
      def available?(db)
        !db.nil? && db.table_exists?(TABLE)
      end

      # -- the read seam -------------------------------------------------------

      # One source's row (zeros / unknowns when it has none — it holds no
      # documents and was never refreshed). O(1): the source_id unique index.
      def fetch(db, source_id)
        row = db[TABLE].where(source_id: source_id).select(*COLUMNS).first
        row ? Row.new(**row) : empty(source_id)
      end

      # { source_id => Row } for every row — O(#sources).
      def all(db)
        db[TABLE].select(*COLUMNS).to_h { |row| [row[:source_id], Row.new(**row)] }
      end

      # The library totals, summed over the per-source rows (no stored
      # global row — the SourceStats stance: a stored total could drift from
      # its own parts). behind_sources counts rows flagged behind.
      def rollup(db)
        rows = db[TABLE]
        { documents_count: rows.sum(:documents_count).to_i,
          passages_count: rows.sum(:passages_count).to_i,
          fts_member_count: rows.sum(:fts_member_count).to_i,
          behind_sources: rows.where(fts_behind: true).count }
      end

      def empty(source_id)
        Row.new(source_id: source_id, documents_count: 0, passages_count: 0, fts_member_count: nil,
                fts_behind: nil, last_index_refresh_at: nil, vector_coverage_count: nil)
      end

      # -- writers: the catalog counts -----------------------------------------

      # Move one source's counts by a delta (the loader's per-document
      # transaction — SourceStats::Maintainer).
      def move_counts!(db, source_id, documents:, passages:)
        return if documents.zero? && passages.zero?

        updated = db[TABLE].where(source_id: source_id).update(
          documents_count: Sequel[:documents_count] + documents,
          passages_count: Sequel[:passages_count] + passages, updated_at: Time.now
        )
        return unless updated.zero?

        db[TABLE].insert(source_id: source_id, documents_count: documents, passages_count: passages,
                         updated_at: Time.now)
      end

      # The wholesale counts (SourceStats.derive!, inside its transaction):
      # +counts+ is { source_id => [documents, passages] }. Rows of sources
      # absent from +counts+ (no documents any more) drop to zero but keep
      # their fulltext columns — an incremental rebuild re-derives counts
      # without touching the index.
      def set_counts!(db, counts)
        return unless available?(db)

        now = Time.now
        db[TABLE].exclude(source_id: counts.keys).update(documents_count: 0, passages_count: 0, updated_at: now)
        counts.each do |source_id, (documents, passages)|
          db[TABLE]
            .insert_conflict(target: :source_id,
                             update: { documents_count: documents, passages_count: passages, updated_at: now })
            .insert(source_id: source_id, documents_count: documents, passages_count: passages, updated_at: now)
        end
      end

      # -- writers: the fulltext columns ---------------------------------------

      # The catalog moved index-visible rows of this source (Tracker).
      def mark_behind!(db, source_id)
        upsert(db, source_id, fts_behind: true)
      end

      # A slice refresh of +slug+ finished: the slice serves +members+
      # passages and is current. No-op without the table or the source.
      def index_refreshed!(db, slug:, members:, at: Time.now)
        return unless available?(db)

        source_id = db[:sources].where(slug: slug).get(:id)
        return if source_id.nil?

        upsert(db, source_id, fts_member_count: members.to_i, fts_behind: false, last_index_refresh_at: at)
      end

      # A full Indexer.rebuild! just indexed every live passage: each row's
      # membership is its live passage count, and nothing is behind.
      def index_rebuilt!(db, at: Time.now)
        return unless available?(db)

        db[TABLE].update(fts_member_count: Sequel[:passages_count], fts_behind: false,
                         last_index_refresh_at: at, updated_at: at)
      end

      def upsert(db, source_id, values)
        values = values.merge(updated_at: Time.now)
        db[TABLE].insert_conflict(target: :source_id, update: values)
                 .insert(values.merge(source_id: source_id))
      end

      # -- backfill + drift ----------------------------------------------------

      # The one-time population (`rake aggregates:backfill`): counts
      # recounted from the catalog (one documents scan + one passages-join
      # scan — the SourceStats.aggregate truth), fulltext columns from the
      # index's own records — the finish stamp's live_rows/finished_at, the
      # pending marker, and the O(1) max-id behind probe. A source without a
      # stamp that is not behind was built by a full rebuild (which clears
      # the stamps): its membership is its live count. +fulltext+ nil means
      # no index file — nothing is a member, everything with passages is
      # behind. Returns the number of rows written.
      def backfill!(catalog:, fulltext: nil)
        return 0 unless available?(catalog)

        counts = SourceStats.aggregate(catalog).transform_values { |s| [s[:live], s[:passages]] }
        catalog.transaction { set_counts!(catalog, counts) }
        stamps = fulltext ? Indexer.slice_stamps(fulltext) : {}
        slugs = catalog[:sources].select_hash(:id, :slug)
        written = 0
        catalog.transaction do
          all(catalog).each_value do |row|
            upsert(catalog, row.source_id, backfill_index_columns(catalog, fulltext, slugs[row.source_id],
                                                                  row, stamps))
            written += 1
          end
        end
        written
      end

      def backfill_index_columns(catalog, fulltext, slug, row, stamps)
        if fulltext.nil? || slug.nil?
          return { fts_member_count: 0, fts_behind: row.passages_count.positive?,
                   last_index_refresh_at: nil }
        end

        stamp = stamps[slug]
        behind = Indexer.slice_pending?(fulltext, slug) || Indexer.slice_behind?(fulltext, catalog, slug)
        finished = stamp && stamp[:finished_at]
        members = if finished && stamp[:live_rows] then stamp[:live_rows]
                  elsif !behind && stamp.nil? then row.passages_count
                  end
        { fts_member_count: members, fts_behind: behind,
          last_index_refresh_at: finished ? Time.parse(finished) : nil }
      end

      # The truth cross-check over +source_ids+ (a sample — each probe is
      # O(one source) on the source_id indexes): an array of
      # { source_id:, column:, stored:, truth: } mismatches, empty when the
      # stored counts are exact.
      def drift(db, source_ids)
        source_ids.flat_map do |source_id|
          row = fetch(db, source_id)
          truth = { documents_count: db[:documents].where(source_id: source_id, withdrawn: false).count,
                    passages_count: SourceStats.passage_truth(db, source_id) }
          truth.filter_map do |column, value|
            stored = row.public_send(column)
            { source_id: source_id, column: column, stored: stored, truth: value } unless stored == value
          end
        end
      end

      # The loader's once-per-load fts_behind mark. The mark runs inside the
      # document's transaction (or savepoint); it counts as landed only once
      # that unit commits — a rolled-back document re-arms it, so the next
      # index-visible document marks again. Mirrors IndexDelta's
      # stage/commit/discard rhythm.
      class Tracker
        def initialize(db:, source_id:)
          @db = db
          @source_id = source_id
          reset!
        end

        # A fresh load: nothing marked yet this pass.
        def reset!
          @marked = false
          @pending = false
        end

        def mark_behind!
          return if @marked || @pending

          SourceAggregates.mark_behind!(@db, @source_id)
          @pending = true
        end

        def commit!
          @marked ||= @pending
          @pending = false
        end

        def discard!
          @pending = false
        end
      end

      def tracker(db:, source:)
        available?(db) ? Tracker.new(db: db, source_id: source.id) : nil
      end
    end
  end
end
