# frozen_string_literal: true

# Per-scope derivation stamps for the links stage (Nabu::LinkStamps).
# The links stage used to wipe the journal and re-mine every recorded
# scope at every rebuild; a scope whose inputs are provably unchanged
# now carries its edges instead. Two tables, both state ABOUT the
# derived edges (wiped and re-minted with them — the link_run_chunks
# precedent):
#
#   link_scope_stamps  one row per recorded batch scope (producer +
#                      the link_scopes.yml scope string): the identity
#                      the scope was last mined under (+stamp+, a sha256
#                      over +inputs_json+ — the producer code digest, the
#                      resolved params, the member sources' content
#                      identities and any producer-specific extras), and
#                      the link_runs ids that mining minted. A scope may
#                      be carried only when its recomputed stamp equals
#                      this one AND the journal still holds exactly these
#                      runs.
#   link_stage_runs    one row per links-stage execution: how it ran
#                      ("full" — nothing could be carried; "stamped" —
#                      clean scopes carried; "self-check" — the periodic
#                      or forced full re-mine compared against the
#                      stamped state) and what it found. The self-check
#                      cadence counts these rows; drift (a stamp that
#                      lied) is recorded here as well as announced.
#
# Additive only (the 002/003 precedent): applied forward to a live
# journal with zero data loss. A journal without stamps simply mines
# every scope at its next links stage.
Sequel.migration do
  change do
    create_table(:link_scope_stamps) do
      String :producer, null: false
      String :scope, null: false
      String :stamp, null: false
      String :inputs_json, null: false
      String :run_ids_json, null: false
      DateTime :stamped_at, null: false

      primary_key %i[producer scope]
    end

    create_table(:link_stage_runs) do
      primary_key :id
      String :mode, null: false
      Integer :mined, null: false, default: 0
      Integer :carried, null: false, default: 0
      Integer :verified, null: false, default: 0
      Integer :drifted, null: false, default: 0
      String :drift_json
      DateTime :ran_at, null: false
    end
  end
end
