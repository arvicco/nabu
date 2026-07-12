# frozen_string_literal: true

module Nabu
  module Store
    # One source's cached upstream-probe verdict, keyed by source_slug in the
    # history LEDGER (db/history.sqlite3). Written (upserted) by
    # Health::RemoteProbe on every `nabu health --remote` / `status --remote`
    # run; read by StatusReport and the MCP nabu_status surface to render the
    # compact `up=…` column WITHOUT any live network probe. A cache, not
    # history: exactly one row per source (the runs table holds the per-run
    # history). Survives `nabu rebuild` by construction. No business logic here.
    class Probe < Sequel::Model(:source_probes)
    end
  end
end
