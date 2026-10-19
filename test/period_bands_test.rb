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

  # The UD Egyptian-PC sentence dates ("5th Dynasty" / "6th Dynasty") band
  # through the TLA thesaurus's own dynasty bounds — the same nodes the
  # held AED headers date AES texts by.
  def test_the_old_kingdom_dynasties_band_by_the_tla_thesaurus
    assert_equal [-2520, -2364], table.lookup("5th Dynasty")
    assert_equal [-2363, -2233], table.lookup("6th Dynasty")
  end

  def test_unruled_labels_are_honestly_nil
    assert_nil table.lookup("Uncertain")
    assert_nil table.lookup("Standard Babylonian"),
               "a REGISTER label misfiled as a period upstream — a date claim from it would be invented"
    assert_nil table.lookup(nil)
    assert_equal [-3350, -3000], table.lookup("Archaic"),
                 "the P16-3 extractor had already ruled Archaic (proto-cuneiform horizon) — adopted"
  end

  def test_the_aegean_ceramic_phases_band
    assert_equal [-1370, -1190], table.lookup("LM IIIA2 or LM IIIB"),
                 "a compound label bands as its phases' envelope"
    assert_equal [-1230, -1070], table.lookup("LH IIIB2/LH IIIC")
    assert_equal [-1330, -1190], table.lookup("LM IIIB ?"),
                 "the cataloguer's trailing ? strips, the shared fold"
    assert_equal [-1450, -1190], table.lookup("LM II-LM IIIA1 or LM IIIB")
    assert_nil table.lookup("-"), "the corpus's own no-claim marker stays nil"
  end

  # The Ancient North Arabian script-tradition spans (OCIANA's held
  # script field): conventional tradition envelopes after Macdonald 2000
  # and OCIANA's own corpus introductions; the minor classes stay nil.
  def test_the_ana_script_traditions_band
    assert_equal [-100, 400], table.lookup("Safaitic"), "1st c. BC – 4th c. AD (Macdonald 2000: 44)"
    assert_equal [-100, 400], table.lookup("Hismaic")
    assert_equal [-800, -400], table.lookup("Taymanitic")
    assert_equal [-800, 100], table.lookup("Dadanitic")
    assert_equal [-100, 400], table.lookup("Mixed Safaitic/Hismaic"), "a compound label = its envelope"
    assert_nil table.lookup("Thamudic B"), "the Thamudic pending file carries no ruled span"
    assert_nil table.lookup("Greek"), "a non-ANA script names no tradition span"
  end

  # The DCS composition time slots (Hellwig's five slots, named early/
  # epic/classical/medieval/late on the corpus's own text list).
  def test_the_dcs_time_slots_band
    assert_equal [-1300, -300], table.lookup("DCS time slot 1"),
                 "the Vedic slot: Hellwig 2020's own RV-to-Sūtra priors"
    assert_equal [-500, 400], table.lookup("DCS time slot 2")
    assert_equal [300, 1000], table.lookup("DCS time slot 3")
    assert_equal [800, 1500], table.lookup("DCS time slot 4")
    assert_equal [1400, 1900], table.lookup("DCS time slot 5"), "the corpus's own 1900 CE ceiling"
    assert_nil table.lookup("DCS time slot None"), "upstream's None slot stays honestly bare"
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
