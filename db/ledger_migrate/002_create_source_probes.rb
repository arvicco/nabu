# frozen_string_literal: true

# P14-12: the upstream-probe cache. `nabu health --remote` (and `status
# --remote`) already compute per-source drift/license verdicts against the
# ledger pins, then discarded them after rendering — so between probe runs the
# owner had no idea IF an upstream had moved. This table PERSISTS the last
# verdict per source so `nabu status` can render a compact `up=…` column
# without any live network call, making "should I sync?" an informed decision.
#
# It lives in the ledger (not the catalog) on purpose: like runs and pins, the
# probe cache must survive `nabu rebuild` (a rebuild re-mints catalog ids but
# says nothing about upstream state). It is a CACHE, not history — exactly one
# row per source, upserted every probe run (the runs table already carries the
# per-run history). Slug-keyed, like everything else in the ledger.
Sequel.migration do
  change do
    drift_verdicts = %w[current behind never_synced unknown multi].freeze
    license_verdicts = %w[baseline_recorded unchanged changed unchecked].freeze

    create_table(:source_probes) do
      primary_key :id
      String :source_slug, null: false
      DateTime :checked_at, null: false
      # The Drift#status / License#status symbols the RemoteProbe already
      # computes, stored as strings. drift drives the status up= column;
      # license rides along for the same surface (a CHANGED license is signal
      # too). detail is the compact human line (behind repos, a changed-license
      # note, an unreachable reason) — nil when there is nothing to add.
      String :drift, null: false
      String :license, null: false
      String :detail

      constraint(:source_probes_drift_valid, drift: drift_verdicts)
      constraint(:source_probes_license_valid, license: license_verdicts)
      index :source_slug, unique: true
    end
  end
end
