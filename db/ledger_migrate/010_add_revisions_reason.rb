# frozen_string_literal: true

# P93-2 (№R-16, half 1): the durable half of the withdrawal reason —
# the revisions ledger survives `nabu rebuild` (architecture §5), so
# the WHY must live here to outlive the derived catalog row (catalog
# migration 030 is the queryable projection). Stamped on "withdrawn"
# events only: "upstream-gone" (document completeness sweep) or
# "revision-pruned" (passage vanished from a revised document). NULL
# on pre-P93 rows and on every other event kind.
Sequel.migration do
  change do
    alter_table(:revisions) do
      add_column :reason, String, null: true
    end
  end
end
