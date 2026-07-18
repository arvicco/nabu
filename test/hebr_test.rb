# frozen_string_literal: true

require "test_helper"

# Nabu::Hebr (P27-2): pointed Hebrew/Aramaic → SBL-style romanization for
# `--display translit`. Census-scoped: the table covers exactly the OSHB
# fixture inventory (U+0591–05C3 marks, U+05D0–05EA letters — counted in the
# P27-2 census); the fixture strings below are real stored OSHB bytes
# (byte-verbatim, NFC-exempt — the transcoder must never rely on mark order).
class HebrTest < Minitest::Test
  # OSHB Gen 1:1 exactly as OshbOsisParser stores it.
  GEN_1_1 = "בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ׃"
  # Gen 1:2 opening — carries maqaf (עַל־פְּנֵי).
  AL_PNE = "עַל־פְּנֵ֣י"

  def test_gen_1_1_romanizes_letter_for_letter
    assert_equal "bəreʾshiyt baraʾ ʾelohiym ʾet hashamayim wəʾet haʾarets.",
                 Nabu::Hebr.to_sbl(GEN_1_1)
  end

  def test_begadkefat_follows_the_dagesh
    assert_equal "bə", Nabu::Hebr.to_sbl("בְּ"), "dagesh → plosive b"
    assert_equal "wə", Nabu::Hebr.to_sbl("וְ"), "consonantal vav is w"
    assert_equal "v", Nabu::Hebr.to_sbl("ב"), "no dagesh → spirant v"
    assert_equal "k", Nabu::Hebr.to_sbl("כּ")
    assert_equal "kh", Nabu::Hebr.to_sbl("כ")
    assert_equal "p", Nabu::Hebr.to_sbl("פּ")
    assert_equal "f", Nabu::Hebr.to_sbl("פ")
  end

  def test_shin_and_sin_split_on_their_dots
    assert_equal "sh", Nabu::Hebr.to_sbl("שׁ")
    assert_equal "ś", Nabu::Hebr.to_sbl("שׂ")
    assert_equal "sh", Nabu::Hebr.to_sbl("ש"), "undotted shin reads sh — journaled default"
  end

  def test_shuruq_and_holam_vav
    assert_equal "u", Nabu::Hebr.to_sbl("וּ"), "vav + dagesh alone is shuruq"
    assert_equal "o", Nabu::Hebr.to_sbl("וֹ"), "vav + holam alone is holam male"
  end

  def test_maqaf_becomes_a_hyphen_never_fusing_words
    assert_equal "ʿal-pəney", Nabu::Hebr.to_sbl(AL_PNE)
  end

  def test_cantillation_and_meteg_leave_no_residue
    romanized = Nabu::Hebr.to_sbl(GEN_1_1)
    assert_empty romanized.scan(/[֑-ׇא-ת]/),
                 "no Hebrew codepoint survives romanization"
  end

  def test_final_forms_share_their_letter_value
    assert_equal Nabu::Hebr.to_sbl("מ"), Nabu::Hebr.to_sbl("ם")
    assert_equal Nabu::Hebr.to_sbl("כ"), Nabu::Hebr.to_sbl("ך")
  end

  def test_non_hebrew_text_passes_through
    assert_equal "verse 1: ", Nabu::Hebr.to_sbl("verse 1: ")
  end
end
