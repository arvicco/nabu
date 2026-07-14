# frozen_string_literal: true

# P19-1: widen the source_probes drift CHECK constraint for the local
# vocabulary word. sync_policy: local shelves (canonical/local-language) have
# NO upstream — the probe short-circuits to the frozen-style "local" verdict
# (Health::RemoteProbe#probe_local_source) and the cache must persist it so
# `nabu status` renders up=local without a live probe. Same recreate-and-copy
# widening as ledger migration 003.
Sequel.migration do
  drift_verdicts = %w[current behind never_synced unpinned unknown multi frozen local].freeze
  legacy_verdicts = %w[current behind never_synced unpinned unknown multi frozen].freeze

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
