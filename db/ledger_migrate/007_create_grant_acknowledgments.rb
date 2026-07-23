# frozen_string_literal: true

# P42-r1: the durable record that a user has acknowledged a permission-bound
# source's fetch grant (StarLing's personal e-mail grant, the future TITUS
# Avestan). A public clone of nabu carries NO such right, so `nabu sync
# starling` demands a typed `granted` (or a scripted --grant-acknowledged)
# before the first fetch; this table is where that acknowledgment lives.
#
# It belongs in the history LEDGER, not the drop-and-rebuild catalog, for the
# same reason the run history and license baselines do: it is authored runtime
# state, NOT a function of canonical/, so a `nabu rebuild` must never wipe it
# and force the operator to re-acknowledge. Keyed by source_slug (survives the
# id re-minting a rebuild performs); recording is idempotent, so one row per
# source — a later sync sees it and passes silently.
#
# +terms+ is the grant terms VERBATIM as shown at acknowledgment time (an
# audit of exactly what the operator agreed to, frozen even if the registry
# text is later reworded); +how+ is "typed" (the interactive prompt) or "flag"
# (the scripted --grant-acknowledged path). Forward-only, like every migration
# in this directory.
Sequel.migration do
  change do
    create_table(:grant_acknowledgments) do
      primary_key :id
      String :source_slug, null: false
      String :terms, text: true, null: false
      String :how, null: false
      DateTime :created_at, null: false

      index :source_slug, unique: true
    end
  end
end
