# frozen_string_literal: true

require "test_helper"

# Nabu::Romaji (P65 gate feedback): Hepburn-ish romaji → hiragana, so on/kun
# readings can be typed without a kana input method (`nabu char TAI`,
# `nabu char hito`). Unconvertible input answers nil — the caller's reading
# lane simply finds nothing, never guesses.
class RomajiTest < Minitest::Test
  def test_plain_syllables
    assert_equal "ひと", Nabu::Romaji.to_hiragana("hito")
    assert_equal "たい", Nabu::Romaji.to_hiragana("tai")
    assert_equal "くに", Nabu::Romaji.to_hiragana("kuni")
  end

  def test_hepburn_digraphs_and_their_kunrei_spellings
    assert_equal "しょう", Nabu::Romaji.to_hiragana("shou")
    assert_equal "しょう", Nabu::Romaji.to_hiragana("syou")
    assert_equal "きょう", Nabu::Romaji.to_hiragana("kyou")
    assert_equal "ちゃ", Nabu::Romaji.to_hiragana("cha")
    assert_equal "じん", Nabu::Romaji.to_hiragana("jin")
  end

  def test_sokuon_and_moraic_n
    assert_equal "がっこう", Nabu::Romaji.to_hiragana("gakkou")
    assert_equal "しんぶん", Nabu::Romaji.to_hiragana("shinbun")
    assert_equal "ほん", Nabu::Romaji.to_hiragana("hon")
  end

  def test_macron_long_vowels
    assert_equal "こう", Nabu::Romaji.to_hiragana("kō")
    assert_equal "きゅう", Nabu::Romaji.to_hiragana("kyū")
  end

  def test_unconvertible_input_is_nil_never_a_guess
    assert_nil Nabu::Romaji.to_hiragana("xyz")
    assert_nil Nabu::Romaji.to_hiragana("wen"), "wi/we are out — pinyin syllables must not convert"
    assert_nil Nabu::Romaji.to_hiragana("qi")
  end
end
