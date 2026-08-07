# frozen_string_literal: true

require "test_helper"

# Nabu::PeriodBands (P62-0): the ruled period→band table. Tests read the
# REAL config/period_bands.yml — the table is ruled config (the
# lect-rules precedent), and these pins are its contract: the shared
# normalize fold, the honest nils, and the band conventions the wave's
# extractors stand on.
class PeriodBandsTest < Minitest::Test
  def table
    @table ||= Nabu::PeriodBands.load(
      File.join(Nabu::Config::PROJECT_ROOT, "config", "period_bands.yml")
    )
  end

  def test_bare_and_glossed_and_queried_labels_share_one_row
    assert_equal [-2100, -2000], table.lookup("Ur III")
    assert_equal [-2100, -2000], table.lookup("Ur III (ca. 2100-2000 BC)"),
                 "CDLI's parenthetical gloss normalizes away — same ruled row"
    assert_equal [-2100, -2000], table.lookup("Ur III (ca. 2100-2000 BC) ?"),
                 "the trailing cataloguer's ? strips (the lect-rules fold, shared)"
  end

  def test_the_ruled_conventions_hold
    assert_equal [-911, -612], table.lookup("Neo-Assyrian")
    assert_equal [-312, -63], table.lookup("Seleucid")
    assert_equal [-2340, -2200], table.lookup("Sargonic"), "ebl's label for Old Akkadian"
    assert_equal [-547, -331], table.lookup("Persian"), "ebl's label for Achaemenid"
    assert_equal [-2900, -2340], table.lookup("Early Dynastic"),
                 "the unsubperiodized span — honest coarseness"
  end

  def test_unruled_labels_are_honestly_nil
    assert_nil table.lookup("Uncertain")
    assert_nil table.lookup("Standard Babylonian"),
               "a REGISTER label misfiled as a period upstream — a date claim from it would be invented"
    assert_nil table.lookup(nil)
    assert_equal [-3350, -3000], table.lookup("Archaic"),
                 "the P16-3 extractor had already ruled Archaic (proto-cuneiform horizon) — adopted"
  end

  def test_every_band_is_a_sane_interval
    yaml = YAML.safe_load_file(File.join(Nabu::Config::PROJECT_ROOT, "config", "period_bands.yml"))
    yaml["periods"].each do |label, entry|
      nb, na = entry.fetch("band")
      assert nb < na, "#{label}: band must run forward (#{nb}..#{na})"
      assert entry.key?("basis"), "#{label}: every band cites its convention"
    end
  end
end
