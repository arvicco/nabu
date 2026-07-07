# frozen_string_literal: true

module Nabu
  module Store
    # One durable content-transition event in the history LEDGER
    # (db/history.sqlite3): a document or passage that was revised (old/new
    # sha), withdrawn, restored, retired, or unretired — urn-keyed, append-
    # only, written by the Loader alongside its (derived, catalog-resident)
    # provenance journal. This is the revision history that survives
    # `nabu rebuild`; per-load noise ("loaded", "superseded", "quarantined")
    # deliberately stays in the catalog journal only (architecture §5).
    class Revision < Sequel::Model(:revisions)
    end
  end
end
