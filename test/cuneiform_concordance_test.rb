# frozen_string_literal: true

require "test_helper"

# Nabu::CuneiformConcordance — the shared key rules behind the
# CDLI↔ETCSL concordance hubs. Every input string below is a REAL
# upstream value: the ETCSL c.*.xml `<biblScope type="museumNumber">`
# entries and CDLI cdli_cat.csv museum_no / subgenre cells (censused
# 2026-10-18 over the held assets).
class CuneiformConcordanceTest < Minitest::Test
  CC = Nabu::CuneiformConcordance

  # -- museum numbers (display form: publication stripped, joins intact) ----

  def test_museum_number_strips_the_parenthetical_publication
    assert_equal "CBS 7914", CC.museum_number("CBS 7914 (JCS 1 27)")
    assert_equal "HS 1504", CC.museum_number("HS 1504 (TMH NF 3 54; WZJ 6 pl. iii)")
  end

  def test_museum_number_keeps_joins_intact
    assert_equal "N 1013 + Ni 9950", CC.museum_number("N 1013 + Ni 9950")
    assert_equal "CBS 14077 + N 3637 + Ni 9925",
                 CC.museum_number("CBS 14077 (STVC 41) + N 3637 (photos E. Robson) + Ni 9925 (ISET 1 145)")
  end

  def test_museum_number_keeps_the_indirect_join_marker
    assert_equal "UET 6 185 (+) UET 6 *156", CC.museum_number("UET 6 185 (+) UET 6 *156")
    assert_equal "CBS 10309 + CBS 10412 (+) CBS 10322", CC.museum_number("CBS 10309 + CBS 10412 (+?) CBS 10322")
  end

  def test_museum_number_drops_sic_and_editorial_flags
    assert_equal "CBS 13325", CC.museum_number("CBS 13325! (SEM 31)")
    assert_equal "BM 80054 (+) BM 80094", CC.museum_number("BM 80054 (+) BM 80094 (CT 53 49) ***")
  end

  def test_museum_number_of_a_publication_only_entry_is_kept_verbatim
    assert_equal "OECT 1 pl. 9", CC.museum_number("OECT 1 pl. 9")
  end

  # -- object hubs (one per physical fragment, fold-both-sides) -------------

  def test_object_hubs_split_a_join_into_its_fragments
    assert_equal ["object:N 1362", "object:N 1412"], CC.object_hubs("N 1362 + N 1412")
  end

  def test_object_hubs_strip_leading_zeros_so_cdli_padding_meets_etcsl
    assert_equal CC.object_hubs("CBS 8337"), CC.object_hubs("CBS 08337")
    assert_equal ["object:BM 16920"], CC.object_hubs("BM 016920")
  end

  def test_object_hubs_shed_cdlis_istanbul_collection_prefix
    # CDLI writes the Istanbul Nippur collection "Ist Ni 04405"; ETCSL
    # writes the same tablet "Ni 4405".
    assert_equal CC.object_hubs("Ni 4405 (ISET 2 43) + Ni 9933 (ISET 1 148)"),
                 CC.object_hubs("Ist Ni 04405 + Ist Ni 09933")
  end

  def test_object_hubs_inherit_the_prefix_for_bare_join_numbers
    assert_equal ["object:CBS 10305", "object:CBS 10315", "object:N 3068"],
                 CC.object_hubs("CBS 10305 + 10315 + N 3068 (Tf. 2-3)")
  end

  def test_object_hubs_take_both_sides_of_an_equation
    assert_equal ["object:3 N T 350", "object:IM 58439"], CC.object_hubs("3N-T350 = IM 58439")
  end

  def test_object_hubs_ignore_spacing_and_punctuation_drift
    assert_equal CC.object_hubs("IM 011053,054a"), CC.object_hubs("IM 11053,54a (Sumer 15 pl. 2; TIM 9 47)")
    assert_equal CC.object_hubs("3N-T 350"), CC.object_hubs("3N-T350")
  end

  def test_object_hubs_drop_trailing_prose_but_keep_short_suffixes
    assert_equal ["object:N 7000"], CC.object_hubs("N 7000 (Alster pl. 16) wrong mus. no. (?)")
    assert_equal ["object:IM 11053 54 B"], CC.object_hubs("IM 11053,54 B")
  end

  def test_object_hubs_mint_nothing_for_withheld_or_unknown_numbers
    assert_empty CC.object_hubs("BM —")
    assert_empty CC.object_hubs("unknown")
    assert_empty CC.object_hubs("Stevenson Collection")
    assert_equal ["object:CBS 8859", "object:N 2914", "object:N 5285"],
                 CC.object_hubs("CBS 08859 + N 2914 + N 5285 + unn.")
  end

  def test_object_hubs_shed_uncertainty_marks
    assert_equal ["object:N 6385"], CC.object_hubs("?N 6385")
    assert_equal ["object:IM 51545 A"], CC.object_hubs("IM 051545,a ?")
  end

  # -- ETCSL composition hubs ----------------------------------------------

  def test_etcsl_hub_folds_segment_padding_both_ways
    # ETCSL pads irregularly (c.0.2.01, c.3.1.06.1); CDLI pads every
    # segment (0.02.01). The hub folds both to unpadded segments.
    assert_equal "etcsl:0.2.1", CC.etcsl_hub("0.2.01")
    assert_equal "etcsl:0.2.1", CC.etcsl_hub("0.02.01")
    assert_equal "etcsl:1.8.2.1", CC.etcsl_hub("1.08.02.01")
    assert_equal "etcsl:2.4.2.a", CC.etcsl_hub("2.4.2.a")
  end

  def test_etcsl_hub_refuses_a_malformed_number
    assert_nil CC.etcsl_hub("2.05.add01")
    assert_nil CC.etcsl_hub("nn")
  end

  def test_etcsl_refs_read_the_cdli_subgenre_composition_numbers
    assert_equal ["1.08.02.01"], CC.etcsl_refs("ETCSL 1.08.02.01 Lugalbanda and Mountain Cave (witness)")
    assert_equal ["6.01.02", "6.02.05"],
                 CC.etcsl_refs("ETCSL 6.01.02 Proverbs Collection 02; ETCSL 6.02.05 Proverbs from unknown (witne")
  end

  def test_etcsl_refs_skip_cut_off_and_non_etcsl_numbers
    assert_empty CC.etcsl_refs("ETCSL nn (witness)")
    assert_empty CC.etcsl_refs("ETCSL 2.05.add01 OB Letter"), "CDLI's own addendum numbering is not ETCSL's"
    assert_empty CC.etcsl_refs("Archaic Lu2 A (witness)")
    assert_empty CC.etcsl_refs("ETCSL 4.08.0"), "a number cut off at the column limit is no claim"
  end
end
