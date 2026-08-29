# frozen_string_literal: true

require "test_helper"

# Nabu::CharDispatch (P65-3): `nabu char` input → desk-card lane, decided
# purely from Unicode blocks. The one-glyph grain rule survives: multi-char
# input is only ever a NAME lane (or a compound cuneiform rendering, which
# is one sign identity), never a text lane.
class CharDispatchTest < Minitest::Test
  def test_cuneiform_glyphs_and_compound_renderings
    assert_equal :cuneiform, Nabu::CharDispatch.lane("𒋀")
    assert_equal :cuneiform, Nabu::CharDispatch.lane("𒋀𒀊"), "a compound is ONE sign identity"
    assert_equal :cuneiform, Nabu::CharDispatch.lane("𒐕"), "Numbers & Punctuation block"
    assert_equal :cuneiform, Nabu::CharDispatch.lane("𒒐"), "Early Dynastic block"
  end

  def test_hieroglyphs_incl_extended_a
    assert_equal :hieroglyphic, Nabu::CharDispatch.lane("𓅃")
    assert_equal :hieroglyphic, Nabu::CharDispatch.lane("𓑠"), "Extended-A block"
  end

  def test_any_other_single_char_keeps_the_han_lane
    assert_equal :han, Nabu::CharDispatch.lane("棄")
    assert_equal :han, Nabu::CharDispatch.lane("木")
    assert_equal :han, Nabu::CharDispatch.lane("x"), "the existing card path owns its own errors"
  end

  def test_multi_char_input_is_the_name_lane
    assert_equal :name, Nabu::CharDispatch.lane("SAR")
    assert_equal :name, Nabu::CharDispatch.lane("G5")
    assert_equal :name, Nabu::CharDispatch.lane("szesz")
    assert_equal :name, Nabu::CharDispatch.lane("|ŠEŠ.AB|")
  end

  # P86-5 (Q50, flipped DELIBERATELY from the P65-3 pin): a SINGLE kana is an
  # identity first — its card composes the reading panel beside the
  # hiragana/katakana identity (--as reading keeps the pure query). Multi-kana
  # stays a reading query: no single identity exists for ひと.
  def test_single_kana_is_the_single_char_lane_multi_kana_stays_a_reading_query
    assert_equal :han, Nabu::CharDispatch.lane("ア"), "single kana → identity card + panels (Q50)"
    assert_equal :han, Nabu::CharDispatch.lane("と")
    assert_equal :name, Nabu::CharDispatch.lane("ひと")
    assert_equal :name, Nabu::CharDispatch.lane("タイ")
  end
end
