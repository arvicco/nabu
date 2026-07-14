# frozen_string_literal: true

# P18-7: the quarantine baseline. Every rebuild reprints "quarantined 9312 —
# parser regression?" for papyri's standing (audited-honest) text-less stubs,
# so a REAL regression would drown in the shout. The fix is a recorded
# per-source baseline: the sync/rebuild warning goes DELTA-aware — silent when
# this run's errored count equals the baseline, loud with the delta when it
# changed.
#
# Two columns, deliberately (the advance-rule argument):
#
#   baseline — the errored count of the most recent OK (succeeded) sync or
#              rebuild run. Auto-advances on every ok run, so each CHANGE is
#              announced exactly once, at the run that changed it, and steady
#              state is silent.
#   anchor   — the LOW-WATER mark: set at first recording, advances DOWNWARD
#              only (an improvement resets it; an increase never does). The
#              auto-advancing baseline alone would let a slow creep hide —
#              +5 a sync is a one-line warning each time, absorbed each time
#              (the trend_rules withdrawal-creep precedent: per-step checks
#              miss cumulative bleed). `nabu health` therefore watches
#              baseline-vs-anchor drift and flags the running total.
#
# Lives in the LEDGER because the baseline must survive `nabu rebuild` (the
# catalog is dropped; the whole point is that the standing count carries
# ACROSS rebuilds). Slug-keyed like everything else here; exactly one row per
# source, upserted at each ok run (state, not history — the runs table already
# keeps per-run errored counts).
Sequel.migration do
  change do
    create_table(:quarantine_baselines) do
      primary_key :id
      String :source_slug, null: false
      Integer :baseline, null: false
      Integer :anchor, null: false
      DateTime :recorded_at, null: false

      index :source_slug, unique: true
    end
  end
end
