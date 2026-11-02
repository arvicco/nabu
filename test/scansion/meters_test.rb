# frozen_string_literal: true

require "test_helper"

# The meter templates + the scanner glue (P152): a line scans only when
# exactly one template fits its syllable quantities; no fit and an
# unbroken tie both come back UNSCANNED with the reason, never a guess.
class ScansionMetersTest < Minitest::Test
  def scan(text, language) = Nabu::Scansion.scan(text, language: language)

  def test_aeneid_one_one_scans_as_a_hexameter
    result = scan("Arma virumque cano, Troiae qui primus ab oris", "lat")
    assert_predicate result, :scanned?
    assert_equal :hexameter, result.meter
    assert_equal "DDSSD", result.feet
    assert_equal "-uu-uu-----uu--", result.quantities
  end

  def test_an_elided_line
    result = scan("litora, multum ille et terris iactatus et alto", "lat")
    assert_predicate result, :scanned?
    assert_equal "DSSSD", result.feet
  end

  def test_an_elegiac_couplet_scans_both_halves
    hexameter = scan("Arma gravi numero violentaque bella parabam", "lat")
    assert_equal [:hexameter, "DDDDD"], [hexameter.meter, hexameter.feet]
    pentameter = scan("edere, materia conveniente modis.", "lat")
    assert_predicate pentameter, :scanned?
    assert_equal :pentameter, pentameter.meter
    assert_equal "DD", pentameter.feet
  end

  def test_greek_hexameters
    od = scan("ἄνδρα μοι ἔννεπε, μοῦσα, πολύτροπον, ὃς μάλα πολλὰ", "grc")
    assert_equal [:hexameter, "DDDDD"], [od.meter, od.feet]
    il = scan("οὐλομένην, ἣ μυρίʼ Ἀχαιοῖς ἄλγεʼ ἔθηκε,", "grc")
    assert_equal [:hexameter, "DSDSD"], [il.meter, il.feet]
  end

  def test_a_syllable_count_no_template_admits_is_unscanned
    result = scan("Gallia est omnis divisa in partes tres", "lat")
    refute_predicate result, :scanned?
    assert_equal :no_fit, result.reason
    assert_nil result.feet
  end

  def test_prose_is_unscanned
    refute_predicate scan("quo usque tandem abutere, Catilina, patientia nostra?", "lat"), :scanned?
  end

  def test_an_unsupported_language_is_unscanned
    result = scan("whan that aprille with his shoures soote", "enm")
    refute_predicate result, :scanned?
    assert_equal :unsupported_language, result.reason
  end

  def test_a_tie_is_never_broken_by_guessing
    # Every open syllable anceps and the syllable count admitting several
    # placements: the templates cannot decide, so the line is ambiguous.
    fits = Nabu::Scansion::Meters.fits(Array.new(15) { syllable(:anceps) }, meter: :hexameter)
    assert_operator fits.size, :>, 1
    result = Nabu::Scansion::Meters.choose(Array.new(15) { syllable(:anceps) })
    refute_predicate result, :scanned?
    assert_equal :ambiguous, result.reason
  end

  def test_the_scanner_records_whether_metrical_laws_broke_a_tie
    result = scan("Arma virumque cano, Troiae qui primus ab oris", "lat")
    assert_includes %i[unique laws], result.basis
  end

  def syllable(quantity)
    Nabu::Scansion::Syllable.new(text: "x", quantity: quantity, word: 0, word_final: true, elided_before: false)
  end
end
