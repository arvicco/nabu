# frozen_string_literal: true

# P93-2 (№R-16, half 1): record WHY a document left. The loader has
# withdrawn documents since P1 (never hard-deleted — architecture §3)
# but the row never said why, so the attic answered "gone" without
# "gone how". Two mints only, both loader-stamped at the withdrawal
# site: "upstream-gone" (a full load's completeness sweep — the urn
# vanished from upstream) is the document-level reason; passage-level
# withdrawal is definitionally revision pruning (the document was
# revised and the passage vanished from the new parse), so passages
# carry NO column — their reason is derived. NULL means "withdrawn
# before this column existed, or not withdrawn" — an honest absence;
# the DURABLE record rides the history ledger's revisions.reason
# (ledger migration 010), which survives `nabu rebuild` where these
# catalog rows do not. A restore clears both columns.
Sequel.migration do
  change do
    alter_table(:documents) do
      add_column :withdrawn_reason, String, null: true
      add_column :withdrawn_at, DateTime, null: true
    end
  end
end
