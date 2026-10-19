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

  # The 2026-10-20 extension (owner-ruled): the major unruled rulers of
  # the catalog census join under a named published basis — Isin / Larsa /
  # Babylon I and the Assyrian kings on Brinkman's tables, the Kassites on
  # Brinkman 1976, the first-millennium reigns on Parker & Dubberstein.
  def test_the_extension_rules_the_censused_major_rulers
    table = Nabu::RegnalYears.default
    assert_equal [-1812, -1812], table.span("Sin-muballit", 1), "Sin-muballit 1 = 1812 BC (middle chronology)"
    assert_equal [-1932, -1906], table.span("Gungunum", 0), "Gungunum's 27-year reign"
    assert_equal [-1934, -1924], table.span("Lipit-Ishtar", 0)
    assert_equal [-1114, -1076], table.span("Tiglath-pileser1", 0), "Brinkman: 1114–1076 BC"
    assert_equal [-1273, -1244], table.span("Shalmaneser1", 0)
    assert_equal [-1245, -1233], table.span("Shagarakti-shuriash", 0)
    assert_equal [-424, -424], table.span("Artaxerxes1", 41), "P&D: Artaxerxes I year 41 = 424/423 BC"
    assert_equal [-605, -605], table.span("Nabopolassar", 21)
    assert_equal table.span("Assurbanipal", 5), table.span("Ashurbanipal", 5), "spelling variants share one reign"
    assert_equal :out_of_range, table.span("Darius2", 30), "Darius II reigned 19 years"
  end

  # Contested absolute chronology stays OUT — the period band is the honest
  # fallback (the table header names each group).
  def test_contested_and_homonym_rulers_stay_unruled
    table = Nabu::RegnalYears.default
    %w[Lugalanda Urukagina_l Enmetena Naramsin Shar-kali-sharri Rimush Ur-Baba Sin-kashid Rim-Anum
       Ibal-pi-el2 Zimri-Lim Shamshi-Adad1 Sin-sharru-ishkun Nebuchadnezzar Cyrus Kurigalzu
       Shilhak-Inshushinak1 Nebuchadnezzar1].each do |ruler|
      assert_equal :unruled, table.span(ruler, 1), ruler
    end
  end

  def test_every_row_names_its_basis
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "regnal_years.yml")
    YAML.safe_load_file(path).fetch("rulers").each do |ruler, entry|
      refute_empty entry["basis"].to_s.strip, "#{ruler}: every row carries its basis"
    end
  end

  def test_load_returns_nil_for_a_missing_file
    assert_nil Nabu::RegnalYears.load("/nonexistent/regnal_years.yml")
  end
end
