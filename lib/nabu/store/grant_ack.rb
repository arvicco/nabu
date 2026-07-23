# frozen_string_literal: true

module Nabu
  module Store
    # One recorded fetch-grant acknowledgment in the history LEDGER (P42-r1,
    # ledger migration 007), keyed by source_slug. Written by Nabu::GrantGate
    # when a user acknowledges a permission-bound source's terms (typed
    # `granted` or the scripted --grant-acknowledged flag); read by the same
    # gate so a later sync passes silently. Survives `nabu rebuild` by
    # construction (the ledger is the never-dropped file). No business logic
    # here — the gate owns the policy.
    class GrantAck < Sequel::Model(:grant_acknowledgments)
    end
  end
end
