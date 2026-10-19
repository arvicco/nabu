# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"

module Nabu
  module Store
    # The links journal: db/links.sqlite3 (P16-1, architecture §15,
    # docs/intertext-design.md §7). Batch-mined cross-reference edges between
    # passages — `links(from_urn, to_urn, kind, score, detail, run_id,
    # created_at)` — minted by the batch producers (BatchParallels,
    # BatchFormulas, BatchCognates) — plus a `link_runs` companion recording
    # each run's provenance (producer, scope, params, code version).
    #
    # == Why its own file (the host argument, architecture §5)
    #
    # The catalog/fulltext are pure functions of canonical/ and get dropped by
    # `nabu rebuild`; the history ledger is runtime HISTORY (append-only, never
    # regenerable). Batch links are NEITHER: they are a function of (canonical,
    # params, code version) — minutes to recompute, so they must survive a
    # rebuild (journal-style, the Phase-8 enrichment stance), but a rerun of
    # the same scope legitimately REPLACES its edges, which an append-only
    # ledger must never do. So the journal is a third file with the ledger's
    # MECHANICS (own forward-only migration track in db/links_migrate, urn
    # keying because rebuilds re-mint catalog ids, absent-file = empty state)
    # and its own lifecycle: rebuild never touches it, backups may include it,
    # and losing it costs only a re-mine.
    #
    # Plain module functions over datasets (no Sequel models): the journal has
    # two tables and four verbs — open, supersede, record, write — plus the
    # P122-2 chunk companion (link_run_chunks, migration 003) and its three
    # verbs for resumable chunked runs (record_chunk!, finish_run!,
    # unfinished_run); the readers (Query::Links, the `show` footer, MCP
    # nabu_links) are dataset-shaped too.
    module LinksJournal
      MIGRATIONS_DIR = File.expand_path("../../../db/links_migrate", __dir__)

      module_function

      # Same scheme-less-path handling as Store.connect, so callers can pass
      # config.links_path directly.
      def connect(url, readonly: false) = Store.connect(url, readonly: readonly)

      # Apply pending journal migrations (db/links_migrate) to +db+.
      def migrate!(db)
        require "sequel/extensions/migration"
        Sequel::Migrator.run(db, MIGRATIONS_DIR)
        db
      end

      # The write-path opener: create the file if absent, migrate forward.
      def open!(path)
        FileUtils.mkdir_p(File.dirname(path))
        migrate!(connect(path))
      end

      # The read-path opener: nil when the file is absent (no batch producer
      # has ever run — readers treat that as "no links", never an error).
      def open_readonly(path)
        return nil unless File.exist?(path)

        connect(path, readonly: true)
      end

      # Delete the edges AND run rows of every prior run of (producer, scope):
      # a rerun supersedes — the journal keeps the CURRENT mining of a scope,
      # with run rows as provenance for live edges only. Returns
      # [runs_deleted, edges_deleted].
      def supersede!(db, producer:, scope:)
        run_ids = db[:link_runs].where(producer: producer, scope: scope).select_map(:id)
        return [0, 0] if run_ids.empty?

        edges = db[:links].where(run_id: run_ids).delete
        db[:link_run_chunks].where(run_id: run_ids).delete
        runs = db[:link_runs].where(id: run_ids).delete
        [runs, edges]
      end

      # Empty the whole journal: edges, chunk rows, runs — children first —
      # and the scope stamps that described them.
      def wipe!(db)
        db[:links].delete
        db[:link_run_chunks].delete
        db[:link_runs].delete
        db[:link_scope_stamps].delete
      end

      # -- per-scope stamps (Nabu::LinkStamps; migration 004) --------------

      # Delete every run NOT in +keep+ (ids) with its edges and chunk rows —
      # the links stage's start under stamps: the carried scopes' runs
      # survive, everything else is re-mined. Returns [runs_deleted,
      # edges_deleted]. One scan of the edge table (run_id is unindexed;
      # the same cost the old whole-journal wipe paid in spirit).
      def retain_runs!(db, keep)
        doomed = db[:link_runs].exclude(id: keep).select_map(:id)
        return [0, 0] if doomed.empty?

        edges = keep.empty? ? db[:links].delete : db[:links].exclude(run_id: keep).delete
        db[:link_run_chunks].where(run_id: doomed).delete
        [db[:link_runs].where(id: doomed).delete, edges]
      end

      # Every run id recorded by one of +producers+.
      def run_ids_for(db, producers:)
        db[:link_runs].where(producer: producers).select_order_map(:id)
      end

      # The highest run id so far (0 on an empty journal) — what a scope's
      # replay compares against to name the runs it minted.
      def max_run_id(db) = db[:link_runs].max(:id) || 0

      # { [producer, scope] => { stamp:, inputs:, run_ids: } } — the stored
      # scope stamps, JSON columns decoded.
      def scope_stamps(db)
        db[:link_scope_stamps].all.to_h do |row|
          [[row[:producer], row[:scope]],
           { stamp: row[:stamp], inputs: JSON.parse(row[:inputs_json]),
             run_ids: JSON.parse(row[:run_ids_json]), stamped_at: row[:stamped_at] }]
        end
      end

      # Upsert one scope's stamp: the identity it was just mined under and
      # the runs that mining minted.
      def write_scope_stamp!(db, producer:, scope:, stamp:, inputs:, run_ids:, at: Time.now)
        db[:link_scope_stamps].where(producer: producer, scope: scope).delete
        db[:link_scope_stamps].insert(producer: producer, scope: scope, stamp: stamp,
                                      inputs_json: JSON.generate(inputs),
                                      run_ids_json: JSON.generate(run_ids.sort), stamped_at: at)
      end

      # Keep only the stamps of +keys+ ([producer, scope] pairs) — a scope
      # about to be re-mined loses its stamp FIRST, so a crash mid-mine can
      # never leave a stamp vouching for edges that are gone.
      def retain_scope_stamps!(db, keys)
        db[:link_scope_stamps].all.each do |row|
          next if keys.include?([row[:producer], row[:scope]])

          db[:link_scope_stamps].where(producer: row[:producer], scope: row[:scope]).delete
        end
      end

      # The self-check's comparison basis: per "producer scope" (the run
      # row's own scope string), the edge count and an ORDER-INDEPENDENT
      # digest of the edges' content (pair, kind, score, detail) — run ids,
      # chunk numbers and timestamps are bookkeeping and stay out, so a
      # faithful re-mine digests equal to the edges it replaces.
      def edge_digests(db, run_ids)
        return {} if run_ids.empty?

        sums = Hash.new { |hash, key| hash[key] = { edges: 0, digest: 0 } }
        db[:links].join(:link_runs, id: :run_id)
                  .where(Sequel[:links][:run_id] => run_ids)
                  .select(Sequel[:link_runs][:producer], Sequel[:link_runs][:scope],
                          Sequel[:links][:from_urn], Sequel[:links][:to_urn], Sequel[:links][:kind],
                          Sequel[:links][:score], Sequel[:links][:detail])
                  .each do |row|
          slot = sums["#{row[:producer]} #{row[:scope]}"]
          slot[:edges] += 1
          slot[:digest] = (slot[:digest] + edge_hash(row)) & DIGEST_MASK
        end
        sums.transform_values { |slot| { edges: slot[:edges], digest: slot[:digest].to_s(16) } }
      end

      DIGEST_MASK = (1 << 128) - 1

      # One edge's content hash as a 128-bit integer (summed mod 2^128 —
      # commutative, so the digest never depends on row order). The score
      # rides as its exact IEEE bytes: a bitwise-equal re-mine is the claim.
      def edge_hash(row)
        score = row[:score].nil? ? "-" : [row[:score]].pack("G").unpack1("H*")
        Digest::SHA256.digest([row[:from_urn], row[:to_urn], row[:kind], score, row[:detail].to_s]
                                .join("\x1f")).unpack("Q>Q>").then { |hi, lo| (hi << 64) | lo }
      end

      # Append one links-stage execution to the stage log (+mode+ "full" |
      # "stamped" | "self-check"; +drift+ the drifted "producer scope"
      # names a self-check found).
      def record_stage_run!(db, mode:, mined: 0, carried: 0, verified: 0, drift: [], at: Time.now)
        db[:link_stage_runs].insert(mode: mode, mined: mined, carried: carried, verified: verified,
                                    drifted: drift.size, drift_json: drift.empty? ? nil : JSON.generate(drift),
                                    ran_at: at)
      end

      # How many "stamped" stage runs have happened since the last full
      # re-mine (a "full" or "self-check" row) — the self-check cadence's
      # counter. An empty log reads 0.
      def stamped_streak(db)
        last_full = db[:link_stage_runs].exclude(mode: "stamped").max(:id)
        dataset = db[:link_stage_runs].where(mode: "stamped")
        dataset = dataset.where { id > last_full } if last_full
        dataset.count
      end

      # Record a producer run; returns its id (the edges' run_id). A chunked
      # run (P122-2) passes status: "running" and its chunk_size, and is
      # advanced by record_chunk! / closed by finish_run!; every other
      # producer leaves status NULL (a run row written whole).
      def record_run!(db, producer:, scope:, params:, code_version:, at: Time.now, status: nil, chunk_size: nil)
        db[:link_runs].insert(producer: producer, scope: scope,
                              params_json: JSON.generate(params),
                              code_version: code_version, created_at: at,
                              status: status, chunk_size: chunk_size)
      end

      # The latest still-running chunked run of (producer, scope), or nil —
      # what a resumed batch continues from.
      def unfinished_run(db, producer:, scope:)
        db[:link_runs].where(producer: producer, scope: scope, status: "running").reverse(:id).first
      end

      # Record one committed chunk and advance its run's cursor. Callers run
      # this INSIDE the chunk's edge transaction, so the cursor can never
      # claim a chunk whose edges did not land (P122-2).
      def record_chunk!(db, run_id:, chunk:, first_urn:, last_urn:, anchors:, candidates:,
                        edges_inserted:, edges_refreshed:, seconds:, at: Time.now)
        db[:link_run_chunks].insert(run_id: run_id, chunk: chunk, first_urn: first_urn, last_urn: last_urn,
                                    anchors: anchors, candidates: candidates, edges_inserted: edges_inserted,
                                    edges_refreshed: edges_refreshed, seconds: seconds, finished_at: at)
        db[:link_runs].where(id: run_id)
                      .update(cursor_urn: last_urn || Sequel[:cursor_urn],
                              chunks_done: Sequel[:chunks_done] + 1,
                              anchors_done: Sequel[:anchors_done] + anchors)
      end

      # Close a chunked run: every chunk committed.
      def finish_run!(db, run_id, at: Time.now)
        db[:link_runs].where(id: run_id).update(status: "complete", finished_at: at)
      end

      # Write one edge, keeping AT MOST ONE edge per unordered pair per kind:
      # if the pair already exists in either direction (a prior run over an
      # overlapping scope), that edge is REFRESHED in place (score/detail/
      # run_id/created_at updated, its original discovery direction preserved)
      # rather than duplicated. +detail+ is the optional per-edge evidence
      # string (migration 002: the formula gram, the cognate meet); +chunk+
      # the chunked run's chunk that minted it (migration 003). Returns
      # :inserted or :refreshed.
      #
      # +first_in_run+ (P122-2): a pair THIS run already wrote is left
      # exactly as found and :kept is returned — the within-run "stored
      # once, in the direction first found" rule made durable, so a resumed
      # run's later chunk re-finding the reverse direction neither
      # duplicates nor re-scores it. Another run's edge still refreshes.
      def write_edge!(db, from_urn:, to_urn:, kind:, score:, run_id:, detail: nil, chunk: nil, at: Time.now,
                      first_in_run: false)
        pairs = [{ from_urn: from_urn, to_urn: to_urn }, { from_urn: to_urn, to_urn: from_urn }]
        return :kept if first_in_run && pairs.any? { |pair| db[:links].where(kind: kind, run_id: run_id, **pair).any? }

        fresh = { score: score, detail: detail, run_id: run_id, chunk: chunk, created_at: at }
        return :refreshed if pairs.any? { |pair| db[:links].where(kind: kind, **pair).update(fresh) == 1 }

        db[:links].insert(from_urn: from_urn, to_urn: to_urn, kind: kind, score: score, detail: detail,
                          run_id: run_id, chunk: chunk, created_at: at)
        :inserted
      end

      # Edge counts by kind touching +urn+ in either direction — the `show`
      # footer's one cheap query (two indexed range probes).
      def kind_counts(db, urn)
        db[:links]
          .where(Sequel.expr(from_urn: urn) | Sequel.expr(to_urn: urn))
          .group_and_count(:kind)
          .as_hash(:kind, :count)
      end
    end
  end
end
