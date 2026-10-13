# frozen_string_literal: true

# Resumable chunked runs for the batch producers (P122-2). A parallels
# batch over a 100M-passage scope runs in CHUNKS of anchors (urn order);
# each chunk's edges and its chunk row commit in ONE transaction, so a
# killed run loses at most the chunk in flight and resumes at the run's
# cursor without re-mining finished chunks.
#
# The cursor lives HERE, beside the edges it describes, not in a sidecar
# file: the state and the output share one lifecycle (a links re-mine
# wipes both), and committing them atomically is what makes "this chunk
# is done" true by construction.
#
#   link_runs        + status ("running" / "complete"; NULL = a run row
#                      written whole, the pre-chunking shape every other
#                      producer keeps), chunk_size, cursor_urn (the last
#                      anchor of the last committed chunk), chunks_done,
#                      anchors_done, finished_at
#   links            + chunk (the chunk that minted the edge; NULL for the
#                      unchunked producers)
#   link_run_chunks  one row per committed chunk: its anchor span, the
#                      candidates the engine returned, edges minted/
#                      refreshed, and its wall time
#
# All additions are nullable or defaulted, applied in place to a live
# journal (the 002 precedent: zero data loss, forward-only).
Sequel.migration do
  change do
    alter_table(:link_runs) do
      add_column :status, String
      add_column :chunk_size, Integer
      add_column :cursor_urn, String
      add_column :chunks_done, Integer, null: false, default: 0
      add_column :anchors_done, Integer, null: false, default: 0
      add_column :finished_at, DateTime
    end

    alter_table(:links) do
      add_column :chunk, Integer
    end

    create_table(:link_run_chunks) do
      primary_key :id
      Integer :run_id, null: false
      Integer :chunk, null: false
      String :first_urn
      String :last_urn
      Integer :anchors, null: false
      Integer :candidates, null: false
      Integer :edges_inserted, null: false
      Integer :edges_refreshed, null: false
      Float :seconds
      DateTime :finished_at, null: false

      index %i[run_id chunk], unique: true
    end
  end
end
