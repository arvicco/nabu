# frozen_string_literal: true

require "test_helper"

# Store.analyze! (P42-4): the bounded post-load ANALYZE that refreshes the
# query planner's sqlite_stat1 statistics. ANALYZE on in-memory SQLite is
# legal, so the whole contract is exercised against a fresh migrated
# in-memory catalog.
class StoreAnalyzeTest < Minitest::Test
  include StoreTestDB

  def setup
    @db = store_test_db
  end

  def test_analyze_populates_sqlite_stat1_and_returns_elapsed_seconds
    refute @db.table_exists?(:sqlite_stat1), "a freshly migrated db carries no planner stats"

    seconds = Nabu::Store.analyze!(@db)

    assert @db.table_exists?(:sqlite_stat1), "ANALYZE writes sqlite_stat1 (legal on in-memory)"
    assert_kind_of Float, seconds
    assert_operator seconds, :>=, 0.0
  end

  def test_analyze_sets_the_bounded_analysis_limit
    # The bounded limit is a fixed engine knob, not a corpus measurement.
    assert_equal 1000, Nabu::Store::ANALYSIS_LIMIT
    # analysis_limit is a connection pragma; ANALYZE honours whatever was set.
    Nabu::Store.analyze!(@db)
    assert_equal Nabu::Store::ANALYSIS_LIMIT, @db.fetch("PRAGMA analysis_limit").single_value
  end
end
