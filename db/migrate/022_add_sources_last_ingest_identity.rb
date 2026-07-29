# frozen_string_literal: true

# P50-r1 (owner ruling D50-a): the stale-ingest guard's record — the canonical
# cone identity (Nabu::DerivationFingerprint.canonical_identity) a source's
# catalog rows were last INGESTED from. Both ingest paths write it (sync's
# update_source_state; the rebuild replays at their stamp sites), and
# `nabu data build` reads it: a dataset whose manifest would cite canonical
# bytes the catalog rows were not derived from is refused, not published.
# Nullable on purpose — nil means "cannot prove" (a pre-record ingest, or a
# tree with no honest identity) and the guard refuses; the weak-identity
# doctrine, never a silent pass.
#
# The derivation stamps cannot serve directly: only the rebuild paths write
# them (sync deliberately does not — a sync-written stamp would let
# `rebuild --incremental` skip the rebuild-scoped corpus builders), so after
# an ordinary sync a stamp is honestly STALE while the catalog is current.
#
# Backfill: a stamp's canonical_identity asserts the source's rows satisfied
# that identity at the last rebuild — copying it can only cause honest
# refusals, never a false pass. If canonical moved since the stamp (with or
# without a sync), the copied identity mismatches the current cone and the
# guard refuses until a re-ingest records the truth; if canonical did not
# move, the rows — however often re-synced — derive from exactly that
# identity, and the pass is honest.
Sequel.migration do
  up do
    alter_table(:sources) { add_column :last_ingest_identity, String }
    backfill = from(:derivation_stamps).where(slug: Sequel[:sources][:slug]).select(:canonical_identity)
    from(:sources).update(last_ingest_identity: backfill)
  end

  down do
    alter_table(:sources) { drop_column :last_ingest_identity }
  end
end
