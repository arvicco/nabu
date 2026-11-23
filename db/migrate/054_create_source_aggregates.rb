# frozen_string_literal: true

# The source_aggregates DERIVED table — O(1) library accounting. One row
# per source carrying the numbers the census / status / delta reads keep
# re-deriving by walking the catalog (or probing the fulltext file) per
# invocation:
#
# - documents_count / passages_count: live documents and live-on-live
#   passages (the source_stats census rules). Moved by the SAME
#   per-document delta, in the SAME transaction, as source_stats
#   (Store::SourceStats::Maintainer) — never a second derivation that
#   could disagree with it.
# - fts_member_count: the passages the source's fulltext slice serves, as
#   of its last index refresh (NULL = no refresh recorded yet).
# - fts_behind: the catalog has moved index-visible rows the fulltext
#   slice has not absorbed. Set by the Loader INSIDE the transaction that
#   moved them (so a sync that lands rows and dies before its reindex is
#   visible by construction — the slice-pending marker's blind spot),
#   cleared by the index refresh paths. NULL = unknown (not backfilled).
# - last_index_refresh_at: when the slice last finished a refresh.
# - vector_coverage_count: reserved for the embed lane (nullable; nothing
#   writes it yet — vectors.sqlite3 survives rebuild while this table does
#   not, so the column stays NULL until the lane gains a per-source tally).
#
# == Derivability (architecture §1)
#
# Pure derived data in db/: `nabu rebuild` recreates it in full — the
# loader hooks maintain the counts through the replay, SourceStats.derive!
# re-derives them wholesale, and the post-index hook stamps every source's
# fulltext columns from the freshly built index. `rake aggregates:backfill`
# is the one-time population of an existing live catalog (counts recounted
# from the catalog, fulltext columns from the index's own stamps/probes).
#
# The inline step below only COPIES the two counts from source_stats
# (O(#sources), milliseconds) so a migrated live catalog never reads zero
# holdings before the backfill runs; the fulltext columns stay NULL —
# honestly unknown — until the backfill or the source's next refresh.
Sequel.migration do
  up do
    create_table(:source_aggregates) do
      primary_key :id
      foreign_key :source_id, :sources, null: false, unique: true
      Integer :documents_count, null: false, default: 0
      Integer :passages_count, null: false, default: 0
      Integer :fts_member_count
      TrueClass :fts_behind
      DateTime :last_index_refresh_at
      Integer :vector_coverage_count
      DateTime :updated_at, null: false
    end

    now = Time.now
    from(:source_stats).select(:source_id, :live_documents, :live_passages).each do |row|
      from(:source_aggregates).insert(source_id: row[:source_id], documents_count: row[:live_documents],
                                      passages_count: row[:live_passages], updated_at: now)
    end
  end

  down do
    drop_table(:source_aggregates)
  end
end
