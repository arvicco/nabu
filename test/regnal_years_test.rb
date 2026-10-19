# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::RegnalYears (owner-ruled 2026-08-11, the P73-6 scout ratified): the ruled
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
    assert_raises(ArgumentError, "the us2 mark is read as written — no shift keyword") do
      table.span("Šulgi", 44, us2: true)
    end
    assert_equal [-2094, -2047], table.span("Šulgi", 0), "year 00 = the whole-reign span"
    assert_equal [-486, -486], table.span("Darius1", 36), "P&D: Darius I year 36 = 486 BC"
    assert_equal :unruled, table.span("Lugalanda", 4),
                 "ED III stays deliberately unruled — false precision refused"
    assert_equal :out_of_range, table.span("Amar-Suen", 12), "Amar-Suen reigned 9 years"
  end

  # The Achaemenid reigns the Babylonian archives date by (Parker &
  # Dubberstein): Cyrus II and Cambyses II join under cdli's NUMBERED
  # spellings only — bare "Cyrus"/"Cambyses" stay unruled homonyms.
  def test_cyrus_and_cambyses_rule_under_their_numbered_spellings
    table = Nabu::RegnalYears.default
    assert_equal [-538, -530], table.span("Cyrus2", 0), "P&D: Cyrus years 1–9 = 538/7–530/29 BC"
    assert_equal [-529, -522], table.span("Cambyses2", 0), "P&D: Cambyses years 1–8 = 529/8–522/1 BC"
    assert_equal [-536, -536], table.span("Cyrus2", 3)
    assert_equal :unruled, table.span("Cyrus", 3), "the unnumbered homonym stays unruled"
  end

  def test_load_returns_nil_for_a_missing_file
    assert_nil Nabu::RegnalYears.load("/nonexistent/regnal_years.yml")
  end
end
