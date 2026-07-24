# frozen_string_literal: true

# P43-2: a per-source CREDIT line — the human attribution string a grant may
# require rendered "wherever displayed" (TITUS Avestan's №41-3 grant: "TITUS and
# the editors clearly indicated wherever displayed"). Distinct from the free-text
# `license` (legal terms) and the `license_class` enum: a generic, nullable seam
# any source may carry, written from the adapter manifest by
# SourceRegistry::Entry#sync_source! and threaded beside license_class onto the
# serving surfaces (show cards, search hits, MCP payloads). Rebuild replays it
# from the manifest, so `db/` stays a pure function of canonical + registry.
Sequel.migration do
  up do
    alter_table(:sources) do
      add_column :credit, String # nullable; absent on every ordinary source
    end
  end

  down do
    alter_table(:sources) do
      drop_column :credit
    end
  end
end
