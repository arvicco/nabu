# frozen_string_literal: true

# P7-1 storage split: runs, per-repo pins, and license baselines are runtime
# HISTORY, not data derived from canonical/ — yet they lived in the catalog,
# so `nabu rebuild` (which drops the catalog by design) erased health trends,
# license-drift baselines, and repo pins every time. They now live in the
# history ledger (db/history.sqlite3, its own migration track under
# db/ledger_migrate), keyed by source SLUG / repo URL instead of re-mintable
# row ids.
#
# Ordering contract: Store::Ledger.lift! copies any existing rows out of these
# tables into the ledger BEFORE this migration runs (every write path opens
# the ledger via Ledger.open_with_lift!, which lifts and only then migrates
# the catalog). Fresh catalogs simply create-then-drop in one migration pass.
# Forward-only, like every migration in this directory.
Sequel.migration do
  up do
    drop_table(:source_repos)
    drop_table(:runs)
    alter_table(:sources) do
      drop_column :license_baseline_sha256
    end
  end

  down do
    raise Sequel::Error, "forward-only migration: history moved to db/history.sqlite3 (P7-1)"
  end
end
