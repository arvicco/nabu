# frozen_string_literal: true

# Initial schema for the links journal (db/links.sqlite3, architecture §15;
# docs/intertext-design.md §7). The journal holds batch-mined cross-reference
# EDGES between passages — output of the batch producers (parallels --batch is
# the first), which is a function of (canonical, params, code version), NOT of
# canonical alone. So it lives OUTSIDE the drop-and-rebuild dbs (`nabu rebuild`
# never touches this file), urn-keyed like the revisions ledger because catalog
# row ids re-mint on every rebuild.
#
# Migration track: this directory is the journal's own forward-only track (the
# db/ledger_migrate precedent) — Sequel records applied versions in a
# schema_info table INSIDE each database file, so the catalog's, the ledger's,
# and the journal's version counters can never collide.
Sequel.migration do
  change do
    # One row per batch producer run: which producer minted the edges, over
    # what scope, with what parameters, under which code version — so every
    # edge is honest about its provenance (run_id → this row). A rerun of the
    # same (producer, scope) SUPERSEDES the old run: its edges and run row are
    # replaced, keeping the journal the CURRENT mining of each scope (the run
    # table is provenance for live edges, not an append-only history ledger —
    # that difference is why the journal is its own file, not a ledger table).
    create_table(:link_runs) do
      primary_key :id
      String :producer, null: false     # "parallels" (formula/cognate producers later)
      String :scope, null: false        # source slug or urn prefix mined
      String :params_json, null: false  # the knobs: min_score, per_anchor, lang, …
      String :code_version, null: false # engine marker — scoring changes re-mint edges honestly
      DateTime :created_at, null: false

      index %i[producer scope]
    end

    # One row per mined edge, urn-keyed on both ends. `kind` ∈ {parallel,
    # formula, cognate, …} (design §7); direction is the direction the probe
    # FOUND (from_urn's batch anchor discovered to_urn), and each unordered
    # pair carries at most ONE edge per kind — the unique index below is that
    # invariant's floor (the producer also checks the reverse direction).
    create_table(:links) do
      primary_key :id
      String :from_urn, null: false
      String :to_urn, null: false
      String :kind, null: false
      Float :score
      foreign_key :run_id, :link_runs, null: false
      DateTime :created_at, null: false

      index %i[from_urn kind]
      index %i[to_urn kind]
      index %i[from_urn to_urn kind], unique: true
    end
  end
end
