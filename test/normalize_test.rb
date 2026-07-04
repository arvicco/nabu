# frozen_string_literal: true

require "test_helper"

class NormalizeTest < Minitest::Test
  # NFD-decomposed polytonic Greek "andra" (ἄνδρα), built from explicit
  # codepoints so the fixture stays decomposed regardless of how the editor or
  # filesystem stores the file bytes:
  #   alpha U+03B1 + psili U+0313 + oxia U+0301 + nu + delta + rho + alpha
  NFD_ANDRA = "ἄνδρα"
  # Precomposed NFC form: U+1F04 (alpha with psili and oxia) + nu + delta + rho + alpha
  NFC_ANDRA = "ἄνδρα"

  def test_decomposed_greek_normalizes_to_precomposed
    refute_equal NFC_ANDRA, NFD_ANDRA, "fixture must actually be decomposed"
    assert_equal NFC_ANDRA, Nabu::Normalize.nfc(NFD_ANDRA)
  end

  def test_already_nfc_round_trips_unchanged
    assert_equal NFC_ANDRA, Nabu::Normalize.nfc(NFC_ANDRA)
  end

  def test_result_is_utf8
    assert_equal Encoding::UTF_8, Nabu::Normalize.nfc(NFD_ANDRA).encoding
  end

  def test_invalid_utf8_bytes_raise_nabu_error
    invalid = "\xC3(".b # truncated 2-byte sequence: not valid UTF-8
    assert_raises(Nabu::Error) { Nabu::Normalize.nfc(invalid) }
  end

  def test_bytes_tagged_utf8_but_ill_formed_raise
    invalid = "abc\xFF".dup.force_encoding("UTF-8")
    assert_raises(Nabu::Error) { Nabu::Normalize.nfc(invalid) }
  end

  def test_plain_ascii_round_trips
    assert_equal "hello", Nabu::Normalize.nfc("hello")
  end

  # -- fold_diacritics (P4-1 search form) ----------------------------------

  def test_fold_strips_polytonic_greek_accents_and_breathings
    # μῆνιν (perispomeni), ἄνδρα (breathing+oxia), ᾠδή (iota subscript),
    # ῥαψῳδία (rough breathing + iota subscript) → bare letters.
    assert_equal "μηνιν", Nabu::Normalize.fold_diacritics("μῆνιν")
    assert_equal "ανδρα", Nabu::Normalize.fold_diacritics("ἄνδρα")
    assert_equal "ωδη", Nabu::Normalize.fold_diacritics("ᾠδή")
    assert_equal "ραψωδια", Nabu::Normalize.fold_diacritics("ῥαψῳδία")
  end

  def test_fold_strips_latin_diacritics
    assert_equal "cafe", Nabu::Normalize.fold_diacritics("café")
  end

  def test_fold_leaves_undecorated_text_unchanged
    assert_equal "μηνιν", Nabu::Normalize.fold_diacritics("μηνιν")
    assert_equal "hello", Nabu::Normalize.fold_diacritics("hello")
  end

  def test_fold_result_is_nfc_utf8
    folded = Nabu::Normalize.fold_diacritics("μῆνιν")
    assert_equal Encoding::UTF_8, folded.encoding
    assert_equal folded, folded.unicode_normalize(:nfc)
  end
end
