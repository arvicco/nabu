# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::RegnalYears (№R-28, the P73-6 scout ratified): the ruled
# regnal-year table — cdli ruler spellings → absolute spans under the
# stated chronology commitment; unruled/out-of-range answers are typed,
# never guessed.
class RegnalYearsTest < Minitest::Test
  def teardown = Nabu::RegnalYears.reset!

  def test_the_ruled_table_loads_and_converts_the_scout_examples
    table = Nabu::RegnalYears.default
    refute_nil table, "config/regnal_years.yml is ruled repo config"
    assert_operator table.size, :>=, 20

    assert_equal [-2051, -2051], table.span("Šulgi", 44), "Šulgi 44 = 2051 BC middle chronology"
    assert_equal [-2050, -2050], table.span("Šulgi", 44, us2: true), "the us2 year is the next year"
    assert_equal [-2094, -2047], table.span("Šulgi", 0), "year 00 = the whole-reign span"
    assert_equal [-486, -486], table.span("Darius1", 36), "P&D: Darius I year 36 = 486 BC"
    assert_equal :unruled, table.span("Lugalanda", 4),
                 "ED III stays deliberately unruled — false precision refused"
    assert_equal :out_of_range, table.span("Amar-Suen", 12), "Amar-Suen reigned 9 years"
  end

  def test_load_returns_nil_for_a_missing_file
    assert_nil Nabu::RegnalYears.load("/nonexistent/regnal_years.yml")
  end
end
