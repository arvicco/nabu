# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::EeboImprintPlace: the eebo-tcp imprint PUBPLACE → bare
# town. Every input below is a REAL BIBLFULL PUBPLACE string from the
# 60,326-file canonical census (2026-10-20; occurrence counts in the
# comments) — the shapes the normalizer exists for, never invented ones.
class EeboImprintPlaceTest < Minitest::Test
  def place(raw) = Nabu::Adapters::EeboImprintPlace.call(raw)

  def assert_town(expected, raw, why = nil)
    assert_equal({ "imprint_place" => expected }, place(raw), [why, "#{raw.inspect} → #{expected}"].compact.join(": "))
  end

  def assert_conjecture(expected, raw)
    assert_equal({ "imprint_place_conjecture" => expected }, place(raw), "#{raw.inspect} → #{expected}?")
  end

  def assert_unplaced(raw)
    assert_equal({}, place(raw), "#{raw.inspect} mints no place")
  end

  def test_the_bare_imprint_and_its_catalogue_punctuation
    assert_town "London", "London :"        # 29,427
    assert_town "London", "London, :"       # 2,648
    assert_town "London", "London: :"       # 268
    assert_town "Edinburgh", "Edinburgh :"  # 1,171
  end

  def test_cataloguer_supplied_brackets_are_still_the_claim
    assert_town "London", "[London] :"      # 3,449
    assert_town "London", "[London :"       # 6,862 (unbalanced — ESTC style)
    assert_town "London", "[[London] :"     # 138
    assert_town "London", "[London] printed :"
  end

  def test_period_imprint_furniture_strips_to_the_town
    assert_town "London", "Imprinted at London :"   # 2,458
    assert_town "London", "Printed at London :"     # 1,137
    assert_town "London", "At London :"             # 984
    assert_town "London", "London printed :"        # 259
    assert_town "London", "[Imprynted at London :"  # 121
    assert_town "London", "[Enprynted at London :"
    assert_town "Edinburgh", "Imprentit at Edinburgh :"
    assert_town "London", "Imprinted at London in Powles Churchyarde :"
    assert_town "York", "Imprinted at York by Robert Barker, :"
    assert_town "London", "Enprynted in the famous cyte of London :"
    assert_town "London", "March 11. 1643. London :"
    assert_town "Oxford", "At the Theater in Oxford :"
  end

  def test_scribal_brackets_inside_a_word_splice_back
    assert_town "London", "Imprinted at Lo[n]don :"
    assert_town "London", "Imprinted at Londo[n] :"
    assert_town "London", "[Lo]ndon :"
  end

  def test_latin_and_vernacular_imprint_forms_fold_to_the_english_town
    assert_town "London", "Londini :"             # 231
    assert_town "London", "Excusum Londini :"     # 54
    assert_town "London", "A Londres :"           # 40
    assert_town "London", "Printiedig yn Llundain :" # Welsh, 18
    assert_town "Oxford", "Oxoniæ :"
    assert_town "Oxford", "Oxon :"
    assert_town "Cambridge", "Cantabrigiæ :"
    assert_town "Edinburgh", "Edinburgi :"
    assert_town "Aberdeen", "Aberdene :"
    assert_town "Douai", "Printed at Doway :"
    assert_town "Saint-Omer", "At S. Omers :"
    assert_town "Leuven", "Louanii :"
    assert_town "The Hague", "Hage :"
    assert_town "St Andrews", "Imprentit at Sanctandrois :"
    assert_town "Westminster", "[Enprynted at westmestre :"
  end

  def test_the_cataloguers_ie_correction_outranks_the_false_imprint
    assert_town "London", "In the Savoy [i.e. London] :"
    assert_town "London", "Oxford [i.e. London] :"
    assert_town "Saint-Omer", "Printed at Paris [i.e. Saint-Omer :"
    assert_town "London", "Printed by His Majesties command at Oxford [i.e. London] Decemb. 15. :"
    assert_town "London", "Printed, by His Majesties command, at Oxford [i.e. London] :"
  end

  def test_an_uncorrected_false_imprint_rides_as_written
    # Declared coarseness: a clandestine "Amsterdam" no cataloguer
    # corrected is the imprint's own claim.
    assert_town "Amsterdam", "[Amsterdam] :"
    assert_town "Amsterdam", "Printed at Amsterdam :"
  end

  def test_question_marked_places_ride_the_conjecture_key_only
    assert_conjecture "London", "[London? :"                       # 1,456
    assert_conjecture "London", "[London?] :"                      # 201
    assert_conjecture "Wesel", "Imprinted at London [i.e. Wesel?] :"
    assert_conjecture "London", "From Roane [i.e. London?] :"
  end

  # A two-town conjecture is one hedged claim, never dropped: A05548's
  # imprint (Lindsay's Dialog, 1554) is the cataloguer's "Edinburgh or St.
  # Andrews, both queried". Two-place imprints ride as written (declared
  # coarseness) — the word cap applies per town, not to the pair.
  def test_a_multi_town_conjecture_rides_hedged_as_written
    assert_conjecture "Edinburgh or St. Andrews", "[Edinburgh? or St. Andrews?] :" # A05548
    assert_conjecture "Oxford or London", "[Oxford? or London?] :"
    assert_town "Oxford or London", "Oxford or London :"
  end

  def test_the_qualifier_never_leaks_into_the_name
    assert_town "Cambridge", "Cambridge [Cambridgeshire] :"
    assert_town "Cambridge", "[Cambridge (England) :"
    assert_town "Oxford", "Oxford [Oxfordshire] :"
    assert_town "Ratisbonne", "Ratisbonne [Amsterdam?] :",
                "a supplied non-i.e. bracket beside a printed town leaves the town (and its certainty) alone"
  end

  def test_the_two_cambridges_stay_apart
    assert_town "Cambridge, Mass.", "Cambridge [Mass.] :"
    assert_town "Cambridge, Mass.", "[Cambridge, Mass. :"
    assert_town "Boston", "Boston in New-England :"
    assert_town "Boston", "Boston :"
  end

  def test_the_reprint_place_is_the_artifacts_place
    assert_town "Edinburgh", "Printed at London, and re-printed at Edinburgh :"
    assert_town "London", "First printed at Edinborough ; and now reprinted at London :"
  end

  def test_a_cataloguer_sic_folds_the_misprint_it_marks
    assert_town "London", "Lodon [sic] :"
    assert_town "London", "Londn [sic] :"
  end

  def test_sine_loco_and_non_places_mint_nothing
    assert_unplaced "[S.l. :" # 1,090
    assert_unplaced "[S.l.] :"
    assert_unplaced "[N.p.] :"
    assert_unplaced "[Printed abroad :"
    assert_unplaced "unknown"
    assert_unplaced "Printed by Iohn Legat :"
    assert_unplaced "Printed in Sicilia on the back-side of the Cyclopean mountains :"
    assert_unplaced "Lo: :"
    assert_unplaced nil
    assert_unplaced "  "
  end
end
