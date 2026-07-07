# frozen_string_literal: true

module Nabu
  # What Adapter#fetch returns (architecture §3): the outcome of bringing an
  # upstream snapshot down to local canonical/. A frozen value, compared by
  # content, sibling to Store::LoadReport (which reports what the *load* did).
  #
  # - +sha+: the upstream revision now on disk (e.g. a git HEAD sha). This is
  #   what lands in sources.last_sync_sha and pins the canonical snapshot.
  # - +fetched_at+: when the fetch completed.
  # - +notes+: free-form remarks (nullable) — e.g. "already up to date", a
  #   rate-limit pause, a resumed crawl. Surfaced by `nabu status`, never load
  #   logic.
  # - +repos+: per-repo pins for a MULTI-repo source (UD), a { repo_url => sha }
  #   hash so SyncRunner can record one ledger pin per upstream repo and
  #   the remote probe can report drift/license per repo (P6-3). Nil for the
  #   common single-repo case — those adapters keep pinning only +sha+ into
  #   their one declared repo's pin via the aggregate +sha+ (behavior
  #   byte-identical to before this field existed).
  FetchReport = Data.define(:sha, :fetched_at, :notes, :repos) do
    def initialize(sha:, fetched_at:, notes: nil, repos: nil)
      super
    end
  end
end
