# frozen_string_literal: true

# P6-3 per-repo pinning for multi-repo sources (UD ships one git repo per
# treebank). The sources table carries exactly ONE last_sync_sha + ONE
# license_baseline_sha256, which can only pin the last repo of a multi-repo
# fetch — so `nabu health --remote` could report drift/license for such a
# source only as :multi/:unchecked (the P5-3 deferral). This table gives each
# upstream repo its own pin row, keyed (source_id, repo_url).
#
# Like last_sync_* and license_baseline_sha256 in the sources table, every
# column here is RUNTIME state, not data derived from canonical/: `nabu
# rebuild` drops the whole catalog and the next sync re-pins these rows (the
# probe re-records their license baselines). Rebuild-purity therefore holds.
# Single-repo sources keep using the sources columns and write nothing here.
# Forward-only, like every migration in this directory.
Sequel.migration do
  change do
    create_table(:source_repos) do
      primary_key :id
      foreign_key :source_id, :sources, null: false
      String :repo_url, null: false
      String :last_sync_sha
      String :license_baseline_sha256

      index %i[source_id repo_url], unique: true
      index :source_id
    end
  end
end
