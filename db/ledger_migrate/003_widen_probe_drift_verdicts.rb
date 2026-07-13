# frozen_string_literal: true

# P15-7: widen the source_probes drift CHECK constraint. P14-12 froze the
# cache's drift vocabulary at %w[current behind never_synced unknown multi],
# but the honest-labels fix mints two more verdicts the cache must be able to
# persist:
#
#   unpinned — the source HAS been synced (a run in the ledger, or a canonical
#              tree on disk) but carries no ledger pin yet: it last fetched
#              before the pins ledger existed (P7). "never-synced" was a lie
#              for proiel/torot/papyri-ddbdp; this is the truth.
#   frozen   — a frozen-policy source: no drift is expected or computed, so the
#              health --remote verdict agrees with status's up=frozen (P14-12).
#
# SQLite has no ALTER DROP CONSTRAINT; Sequel emulates it by recreating the
# table and copying the rows, so the cached verdicts survive the widening.
Sequel.migration do
  drift_verdicts = %w[current behind never_synced unpinned unknown multi frozen].freeze
  legacy_verdicts = %w[current behind never_synced unknown multi].freeze

  up do
    alter_table(:source_probes) do
      drop_constraint(:source_probes_drift_valid)
      add_constraint(:source_probes_drift_valid, drift: drift_verdicts)
    end
  end

  down do
    alter_table(:source_probes) do
      drop_constraint(:source_probes_drift_valid)
      add_constraint(:source_probes_drift_valid, drift: legacy_verdicts)
    end
  end
end
