# frozen_string_literal: true

# Store tests run against a fresh migrated in-memory SQLite (CLAUDE.md).
# Mix this in and call #store_test_db in setup for an isolated database with
# the models bound to it.
module StoreTestDB
  def store_test_db
    db = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(db)
    Nabu::Store.setup!(db)
    db
  end
end
