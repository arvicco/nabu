# frozen_string_literal: true

# Initial schema for the lect-assignment journal (db/lects.sqlite3, P58-1).
# The journal is the PERSISTENCE for the per-document overlay tier of
# Nabu::Lects#resolve (the highest-precedence seam, constructor-only since
# P57-3): owner-ratified — or rule-compiled, see `basis` — statements that
# ONE document's use of a bare code means a specific lect ("this Plautus
# edition's lat is lat:arch").
#
# Why its own file (the LinksJournal argument, architecture §15): the
# catalog/fulltext are dropped by `nabu rebuild`; these assignments are
# rulings about documents, not derivations from canonical — losing them
# loses decisions. So: own forward-only migration track (this directory;
# Sequel's schema_info lives INSIDE each db file, so version counters never
# collide), urn keying because rebuilds re-mint catalog row ids, absent
# file = empty state (readers treat "no journal" as "no assignments").
Sequel.migration do
  change do
    # One CURRENT assignment per (urn, code): re-assigning updates in place
    # (the write path reports :updated), so the journal states what IS ruled,
    # not the history of rulings — the ruling ledger is the plan docs/git.
    # `basis` distinguishes authorship: "owner" (a hand ruling) vs
    # "rule:<id>" (compiled by `nabu lect apply-rules`/`infer-dates`, P58-2/3)
    # — a rule re-run supersedes exactly its own basis, never a hand ruling.
    create_table(:lect_assignments) do
      primary_key :id
      String :urn, null: false
      String :code, null: false     # the bare stored code this row refines
      String :lect_id, null: false  # registry lect id (grammar-checked at write)
      String :basis, null: false    # "owner" | "rule:<id>"
      String :note                  # the why, in the owner's words
      DateTime :created_at, null: false

      index %i[urn code], unique: true
      index :basis
    end
  end
end
