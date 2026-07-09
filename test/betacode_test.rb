# frozen_string_literal: true

require "test_helper"

# Nabu::Betacode (P11-4): the minimal TLG betacode → Unicode Greek decoder the
# LSJ TEI needs (keys, orths, quotes are betacode there; conventions §1 NFC).
# Every case below is a real string from the checked-in lexica fixtures.
class BetacodeTest < Minitest::Test
  def decode(str) = Nabu::Betacode.decode(str)

  def test_decodes_plain_words_with_final_sigma
    assert_equal "μῆνις", decode("mh=nis")
    assert_equal "λόγος", decode("lo/gos")
    assert_equal "μηνίσκος", decode("mhni/skos")
    assert_equal "λογοσυλλεκτάδης", decode("logosullekta/dhs")
  end

  def test_decodes_breathings_and_accents
    assert_equal "ὁ", decode("o(")
    assert_equal "ἡ", decode("h(")
    assert_equal "τοὺς", decode("tou\\s")
    assert_equal "ἔχων", decode("e)/xwn")
    assert_equal "καθαροὺς", decode("kaqarou\\s")
    assert_equal "μήνιος", decode("mh/nios")
  end

  def test_decodes_capitals_with_diacritics_before_the_letter
    assert_equal "Αἰήταο", decode("*ai)h/tao")
    assert_equal "Ἀθηναίων", decode("*)aqhnai/wn")
  end

  def test_decodes_iota_subscript_and_diaeresis_in_canonical_mark_order
    assert_equal "τῷ", decode("tw=|")
    # Source order is acute-then-diaeresis; canonical composition (ΐ U+0390)
    # needs diaeresis first — the decoder must emit marks in canonical order.
    assert_equal "λωΐων", decode("lwi/+wn")
  end

  def test_decodes_digamma
    assert_equal "Ϝ", decode("*v")
    assert_equal "ϝ", decode("v")
  end

  def test_strips_vowel_length_marks
    assert_equal "πεταννύω", decode("peta^nnu/w")
    assert_equal "μᾶν-", decode("ma=n-") # stem hyphens pass through
  end

  def test_passes_through_non_betacode_characters
    assert_equal "μήν1", decode("mh/n1") # homograph digit (caller's concern)
    assert_equal "μῆνιν ἔχειν ἀπὸ θεοῦ", decode("mh=nin e)/xein a)po\\ qeou=")
  end

  def test_output_is_nfc
    %w[mh=nis tw=| lwi/+wn *)aqhnai/wn].each do |raw|
      assert decode(raw).unicode_normalized?(:nfc), "#{raw} did not decode to NFC"
    end
  end

  def test_sigma_is_medial_before_a_letter_and_final_before_punctuation
    assert_equal "μηνίσκος, ὁ", decode("mhni/skos, o(")
  end
end
