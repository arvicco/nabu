# frozen_string_literal: true

# P43-0 (D42-c): the durable record that the owner reviewed a quarantine-creep
# anomaly and accepted the source's then-current baseline. The creep alarm
# (TrendRules.quarantine_creep over the migration-005 baselines) watches the
# baseline's cumulative drift above the low-water anchor — which only ever
# moves DOWN, so before this table a reviewed-and-accepted creep kept `nabu
# health` exit-1 forever, with no acknowledgment path.
#
# It belongs in the history LEDGER, not the drop-and-rebuild catalog, for the
# grant-acknowledgment (007) reason: an owner ruling is authored runtime state,
# not a function of canonical/, so a `nabu rebuild` must never wipe it. Keyed
# by source_slug (survives id re-minting). Unlike 007's one-row-per-source
# acknowledgment, acceptances are HISTORY: each review appends a row, the
# LATEST governs (Health::QuarantineBaseline reads it), and the trail records
# every level the owner ever signed off on.
#
# +accepted_baseline+ is the baseline value at acceptance time — the anchor-
# floor the alarm re-arms past. The acceptance applies only while the current
# baseline sits at or above it; a recovery below it (parser fix) makes it
# dormant, so it can never mask fresh creep from a recovered low. +note+ is
# the owner's optional free-text rationale. Forward-only, like every migration
# in this directory.
Sequel.migration do
  change do
    create_table(:creep_acceptances) do
      primary_key :id
      String :source_slug, null: false
      Integer :accepted_baseline, null: false
      String :note, text: true
      DateTime :recorded_at, null: false

      index :source_slug
    end
  end
end
