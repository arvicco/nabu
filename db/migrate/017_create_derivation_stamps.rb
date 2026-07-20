# frozen_string_literal: true

# P36-1: per-source derivation stamps — the fingerprint each replay satisfied
# (canonical identity + parser/pipeline code digest + fold-rules digest +
# migration level + registry flags; Nabu::DerivationFingerprint). Lives IN the
# catalog on purpose: a full rebuild drops it with everything else and
# re-stamps as it replays (a full rebuild re-derives all, so its stamps are
# correct by construction), while `rebuild --incremental` reads it to skip
# fingerprint-clean sources. An absent row means DIRTY — never skip unstamped.
Sequel.migration do
  change do
    create_table(:derivation_stamps) do
      String :slug, primary_key: true
      String :fingerprint, null: false
      String :canonical_identity, null: false
      String :parser_digest, null: false
      String :fold_digest, null: false
      Integer :migration_level, null: false
      String :config_json, null: false
      Time :stamped_at, null: false
    end
  end
end
