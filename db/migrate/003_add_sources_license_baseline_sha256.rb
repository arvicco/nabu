# frozen_string_literal: true

# P5-3 upstream probe: `nabu health --remote` records a per-source sha256 of
# the upstream license file the first time it sees one, then flags a change on
# later probes — a no-clone license-drift check. This baseline is RUNTIME state
# (like last_sync_sha in the same table), not data derived from canonical/, so
# it does not compromise rebuild-purity: `nabu rebuild` drops it and the next
# probe re-records it. Forward-only, like every migration here.
Sequel.migration do
  change do
    alter_table(:sources) do
      add_column :license_baseline_sha256, String
    end
  end
end
