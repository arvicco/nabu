# frozen_string_literal: true

module Nabu
  module Store
    # One sync or rebuild-replay run with its Load counts (architecture §8).
    # Lives in the history LEDGER (db/history.sqlite3), not the catalog, and
    # is keyed by source SLUG so run history stays continuous across rebuilds
    # (which re-mint catalog source ids). +kind+ is "sync" or "rebuild";
    # health trends read kind=sync only (a rebuild re-adds the whole corpus,
    # which would poison sync baselines). Read by `nabu status` and
    # `nabu health`; written by RunRecorder.
    class Run < Sequel::Model(:runs)
    end
  end
end
