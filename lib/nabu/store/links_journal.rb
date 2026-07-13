# frozen_string_literal: true

require "fileutils"
require "json"

module Nabu
  module Store
    # The links journal: db/links.sqlite3 (P16-1, architecture §15,
    # docs/intertext-design.md §7). Batch-mined cross-reference edges between
    # passages — `links(from_urn, to_urn, kind, score, run_id, created_at)`
    # plus a `link_runs` companion recording each run's provenance (producer,
    # scope, params, code version).
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
    # exactly two tables and four verbs — open, supersede, record, write — and
    # the readers (Query::Links, the `show` footer, MCP nabu_links) are
    # dataset-shaped too.
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
        runs = db[:link_runs].where(id: run_ids).delete
        [runs, edges]
      end

      # Record a producer run; returns its id (the edges' run_id).
      def record_run!(db, producer:, scope:, params:, code_version:, at: Time.now)
        db[:link_runs].insert(producer: producer, scope: scope,
                              params_json: JSON.generate(params),
                              code_version: code_version, created_at: at)
      end

      # Write one edge, keeping AT MOST ONE edge per unordered pair per kind:
      # if the pair already exists in either direction (a prior run over an
      # overlapping scope), that edge is REFRESHED in place (score/run_id/
      # created_at updated, its original discovery direction preserved) rather
      # than duplicated. Returns :inserted or :refreshed.
      def write_edge!(db, from_urn:, to_urn:, kind:, score:, run_id:, at: Time.now)
        fresh = { score: score, run_id: run_id, created_at: at }
        return :refreshed if db[:links].where(from_urn: from_urn, to_urn: to_urn, kind: kind).update(fresh) == 1
        return :refreshed if db[:links].where(from_urn: to_urn, to_urn: from_urn, kind: kind).update(fresh) == 1

        db[:links].insert(from_urn: from_urn, to_urn: to_urn, kind: kind,
                          score: score, run_id: run_id, created_at: at)
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
