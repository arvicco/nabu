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
  FetchReport = Data.define(:sha, :fetched_at, :notes) do
    def initialize(sha:, fetched_at:, notes: nil)
      super
    end
  end
end
