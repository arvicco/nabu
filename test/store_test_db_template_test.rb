# frozen_string_literal: true

require "test_helper"

# The StoreTestDB rig clones every test database from a per-process
# migrated template (test/support/store_test_db.rb). That shortcut is only
# sound if a clone is indistinguishable from running the migrations fresh
# and if no two clones share state — pinned here.
class StoreTestDBTemplateTest < Minitest::Test
  include StoreTestDB

  def test_catalog_clone_matches_a_fresh_migration
    fresh = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(fresh)

    assert_equal schema_of(fresh), schema_of(store_test_db)
  end

  def test_ledger_clone_matches_a_fresh_migration
    fresh = Nabu::Store::Ledger.connect("sqlite::memory:")
    Nabu::Store::Ledger.migrate!(fresh)

    assert_equal schema_of(fresh), schema_of(ledger_test_db)
  end

  def test_clone_carries_connection_pragmas_and_no_rows
    db = store_test_db

    assert_equal 1, db.fetch("PRAGMA foreign_keys").get(:foreign_keys)
    user_tables(db).each do |table|
      next if table.to_s.start_with?("schema_")

      assert_equal 0, db[table].count, "a cloned catalog is born empty (#{table})"
    end
  end

  def test_clones_share_no_state
    first = store_test_db
    Nabu::Store::Source.create(slug: "one", name: "One", adapter_class: "TestAdapter",
                               license_class: "open", enabled: true)
    second = store_test_db

    assert_equal 1, first[:sources].count
    assert_equal 0, second[:sources].count, "a later clone never sees an earlier test's rows"
    refute_same first, second
  end

  def test_clone_is_already_at_the_latest_migration
    db = store_test_db
    before = schema_of(db)

    Nabu::Store.migrate!(db)

    assert_equal before, schema_of(db), "re-migrating a clone is a no-op"
  end

  # --- class_template_db --------------------------------------------------

  # A throwaway class so the build counter is this test's alone.
  def template_class
    Class.new do
      include StoreTestDB

      class << self
        attr_accessor :builds
      end

      def catalog
        class_template_db do |db|
          self.class.builds = (self.class.builds || 0) + 1
          db[:sources].insert(slug: "seeded", name: "Seeded", adapter_class: "TestAdapter",
                              license_class: "open", enabled: true)
        end
      end
    end
  end

  def test_class_template_builds_once_and_hands_out_isolated_copies
    klass = template_class
    first = klass.new.catalog
    first[:sources].insert(slug: "scribble", name: "S", adapter_class: "TestAdapter",
                           license_class: "open", enabled: true)
    second = klass.new.catalog

    assert_equal 1, klass.builds, "the replay runs once per class"
    assert_equal %w[scribble seeded], first[:sources].select_order_map(:slug)
    assert_equal %w[seeded], second[:sources].select_order_map(:slug),
                 "a copy never carries an earlier test's writes"
    assert_equal first[:sources].where(slug: "seeded").get(:id), second[:sources].where(slug: "seeded").get(:id)
  end

  def test_class_template_copy_preserves_the_autoincrement_sequence
    klass = template_class
    replayed = store_test_db
    replayed[:sources].insert(slug: "seeded", name: "Seeded", adapter_class: "TestAdapter",
                              license_class: "open", enabled: true)
    copied = klass.new.catalog

    next_replayed = replayed[:sources].insert(slug: "next", name: "N", adapter_class: "TestAdapter",
                                              license_class: "open", enabled: true)
    next_copied = copied[:sources].insert(slug: "next", name: "N", adapter_class: "TestAdapter",
                                          license_class: "open", enabled: true)

    assert_equal next_replayed, next_copied, "ids continue exactly as after a replay"
  end

  def test_class_template_binds_the_models_to_the_copy
    db = template_class.new.catalog

    assert_same db, Nabu::Store::Source.db
    assert_equal %w[seeded], Nabu::Store::Source.select_order_map(:slug)
  end

  # --- class_template_step -----------------------------------------------

  def step_class
    Class.new do
      include StoreTestDB

      class << self
        attr_accessor :replays
      end

      def load!(db)
        class_template_step(:seed, db: db) do
          self.class.replays = (self.class.replays || 0) + 1
          db[:sources].insert(slug: "stepped", name: "Stepped", adapter_class: "TestAdapter",
                              license_class: "open", enabled: true)
        end
      end
    end
  end

  def test_class_template_step_restores_the_replayed_state_for_an_identical_start
    klass = step_class
    replayed = store_test_db
    klass.new.load!(replayed)
    restored = store_test_db
    klass.new.load!(restored)

    assert_equal 1, klass.replays, "the second arrival at the same state restores, never replays"
    assert_equal StoreTestDB::Templates.digest(replayed), StoreTestDB::Templates.digest(restored)
    assert_equal %w[stepped], restored[:sources].select_order_map(:slug)
  end

  def test_class_template_step_replays_when_the_starting_state_differs
    klass = step_class
    klass.new.load!(store_test_db)
    diverged = store_test_db
    diverged[:sources].insert(slug: "first", name: "F", adapter_class: "TestAdapter",
                              license_class: "open", enabled: true)
    klass.new.load!(diverged)

    assert_equal 2, klass.replays, "a different starting state must replay the step"
    assert_equal %w[first stepped], diverged[:sources].order(:id).select_map(:slug)
  end

  def test_class_template_step_snapshot_is_untouched_by_later_writes
    klass = step_class
    first = store_test_db
    klass.new.load!(first)
    first[:sources].insert(slug: "after", name: "A", adapter_class: "TestAdapter",
                           license_class: "open", enabled: true)
    second = store_test_db
    klass.new.load!(second)

    assert_equal %w[stepped], second[:sources].select_order_map(:slug)
  end

  private

  # Every schema object's DDL plus the migrator's bookkeeping rows.
  def schema_of(db)
    ddl = db.fetch("SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name").all
    applied = db.tables.select { |t| t.to_s.start_with?("schema_") }.sort.to_h { |t| [t, db[t].all] }
    [ddl, applied, db.fetch("PRAGMA user_version").get(:user_version)]
  end

  def user_tables(db) = db.tables
end
