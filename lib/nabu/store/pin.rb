# frozen_string_literal: true

module Nabu
  module Store
    # One upstream git repo's sync pin + license baseline, keyed
    # (source_slug, repo_url) in the history LEDGER (db/history.sqlite3).
    # Unifies what pre-P7-1 was split between sources columns (single-repo)
    # and the source_repos table (multi-repo): every repo an adapter declares
    # via Adapter.upstream_repo_urls gets one pin row. Written by SyncRunner
    # (last_sync_sha) and Health::RemoteProbe (license_baseline_sha256);
    # survives `nabu rebuild` by construction. No business logic here.
    class Pin < Sequel::Model(:pins)
    end
  end
end
