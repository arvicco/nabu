# frozen_string_literal: true

# Store tests run against a fresh migrated in-memory SQLite (CLAUDE.md).
# Mix this in and call #store_test_db in setup for an isolated database with
# the models bound to it. #ledger_test_db is the same rig for the history
# ledger (P7-1: its own file, migrations, and models in production).
module StoreTestDB
  def store_test_db
    db = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(db)
    Nabu::Store.setup!(db)
    db
  end

  def ledger_test_db
    db = Nabu::Store::Ledger.connect("sqlite::memory:")
    Nabu::Store::Ledger.migrate!(db)
    Nabu::Store::Ledger.setup!(db)
    db
  end
end
