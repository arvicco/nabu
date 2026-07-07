# frozen_string_literal: true

# Initial schema for the history ledger (db/history.sqlite3, architecture §5).
# This db is the OPPOSITE of the catalog: never derived from canonical/, never
# dropped by `nabu rebuild`, part of the backup set. Everything in it is keyed
# by durable identity (source SLUG, repo URL, passage/document URN) — never by
# catalog row ids, which a rebuild re-mints.
#
# Migration track: this directory is the ledger's own forward-only track,
# entirely separate from db/migrate (the catalog's). Sequel records applied
# versions in a schema_info table INSIDE each database file, so the two tracks
# can never collide — history.sqlite3 counts db/ledger_migrate, catalog.sqlite3
# counts db/migrate.
#
# Phase 8 note: the enrichment journal (paid API output that must survive
# rebuilds) will live here too, urn-keyed like revisions — the identity scheme
# below is the contract it plugs into.
Sequel.migration do
  change do
    run_statuses = %w[running succeeded failed aborted].freeze
    run_kinds = %w[sync rebuild].freeze
    revision_events = %w[revised withdrawn restored retired unretired].freeze

    # One row per sync or rebuild replay of a source. Slug-keyed so history
    # stays continuous across rebuilds (source ids are re-minted; slugs are
    # the registry's stable identity). +kind+ separates operator syncs from
    # rebuild replays: a rebuild re-adds the whole corpus into a fresh catalog,
    # so its counts would poison sync-trend baselines (health reads kind=sync).
    create_table(:runs) do
      primary_key :id
      String :source_slug, null: false
      String :kind, null: false, default: "sync"
      DateTime :started_at, null: false
      DateTime :finished_at
      Integer :added, null: false, default: 0
      Integer :updated, null: false, default: 0
      Integer :withdrawn_count, null: false, default: 0
      Integer :errored, null: false, default: 0
      String :status, null: false, default: "running"
      String :notes, text: true

      constraint(:runs_status_valid, status: run_statuses)
      constraint(:runs_kind_valid, kind: run_kinds)
      index :source_slug
      index %i[source_slug kind]
    end

    # One row per upstream repo a source pulls from: its last-synced sha and
    # the license-file baseline the remote probe recorded. Unifies what the
    # catalog used to split between sources columns (single-repo) and the
    # source_repos table (multi-repo): every repo now gets a pin row keyed
    # (source_slug, repo_url) — the same url Adapter.upstream_repo_urls
    # declares and the probe ls-remotes.
    create_table(:pins) do
      primary_key :id
      String :source_slug, null: false
      String :repo_url, null: false
      String :last_sync_sha
      String :license_baseline_sha256

      index %i[source_slug repo_url], unique: true
      index :source_slug
    end

    # The durable revision history: one row per CONTENT TRANSITION of an
    # existing document/passage (revised, withdrawn, restored, retired,
    # unretired), urn-keyed with the sha pair. Deliberately compact: fresh
    # inserts ("loaded") are per-load noise that rebuild replays 60k+ times —
    # they stay in the catalog's derived provenance journal, which resets on
    # rebuild (documented in architecture §5).
    create_table(:revisions) do
      primary_key :id
      String :urn, null: false
      String :event, null: false
      String :old_sha
      String :new_sha
      DateTime :at, null: false

      constraint(:revisions_event_valid, event: revision_events)
      index :urn
    end
  end
end
