# frozen_string_literal: true

require "test_helper"

# Nabu::Deva — the one-way Devanagari → IAST transcoder (P26-2, the
# Slp1/Betacode precedent: a TRANSCODE at the adapter boundary, not a fold
# rule). SARIT stores 40+ editions with a native Devanagari surface; the
# canonical passage text keeps that script untouched, and this transcoder
# derives the IAST form the SEARCH layer folds — so an IAST query (the
# MW/GRETIL desk-loop norm) lands on both scripts.
class DevaTest < Minitest::Test
  # -- consonants + inherent a ----------------------------------------------

  def test_bare_consonant_carries_inherent_a
    assert_equal "ka", Nabu::Deva.to_iast("क")
    assert_equal "namaḥ", Nabu::Deva.to_iast("नमः")
  end

  def test_virama_suppresses_inherent_a_in_clusters
    assert_equal "jñānam", Nabu::Deva.to_iast("ज्ञानम्")
    assert_equal "śrī", Nabu::Deva.to_iast("श्री")
  end

  def test_vowel_sign_replaces_inherent_a
    assert_equal "kathaṃ", Nabu::Deva.to_iast("कथं")
    assert_equal "muktirbhaviṣyati", Nabu::Deva.to_iast("मुक्तिर्भविष्यति")
  end

  # -- independent vowels, marks, digits, daṇḍas ----------------------------

  def test_independent_vowels_and_avagraha
    assert_equal "aham", Nabu::Deva.to_iast("अहम्")
    assert_equal "ṛtvijam", Nabu::Deva.to_iast("ऋत्विजम्")
    assert_equal "so 'ham", Nabu::Deva.to_iast("सो ऽहम्")
  end

  def test_anusvara_visarga_candrabindu_and_om
    assert_equal "aṃśa", Nabu::Deva.to_iast("अंश")
    assert_equal "duḥkha", Nabu::Deva.to_iast("दुःख")
    assert_equal "sam̐skṛta", Nabu::Deva.to_iast("सँस्कृत")
    assert_equal "oṃ", Nabu::Deva.to_iast("ॐ")
  end

  def test_digits_and_dandas
    assert_equal "|| 12 ||", Nabu::Deva.to_iast("॥ १२ ॥")
    assert_equal "namaḥ |", Nabu::Deva.to_iast("नमः ।")
  end

  # -- the MBh opening, end to end ------------------------------------------

  def test_mahabharata_opening_line
    assert_equal "nārāyaṇaṃ namaskṛtya naraṃ caiva narottamam |",
                 Nabu::Deva.to_iast("नारायणं नमस्कृत्य नरं चैव नरोत्तमम् ।")
  end

  # -- passthrough honesty ---------------------------------------------------

  def test_characters_outside_the_inventory_pass_through
    assert_equal "abc (x) — 5", Nabu::Deva.to_iast("abc (x) — 5")
    # Zero-width joiners are layout, not text: dropped.
    assert_equal "śrī", Nabu::Deva.to_iast("श्री‍‌")
  end

  def test_output_is_nfc
    assert Nabu::Deva.to_iast("नारायणं नमस्कृत्य").unicode_normalized?(:nfc)
  end

  # -- the join argument: fold(transcode(deva)) == fold(iast) ----------------

  # The whole point of the transcode: the generic san fold lands the
  # Devanagari surface on the same search form as its IAST spelling, so one
  # IAST query matches SARIT-Deva, SARIT-IAST, GRETIL and MW alike.
  def test_folded_transcode_equals_folded_iast
    pairs = [
      ["नारायणं नमस्कृत्य नरं चैव नरोत्तमम् ।", "nārāyaṇaṃ namaskṛtya naraṃ caiva narottamam |"],
      ["कथं ज्ञानमवाप्नोति", "kathaṃ jñānamavāpnoti"],
      ["व्यापकं नित्यमेकं च सामान्यं", "vyāpakaṃ nityamekaṃ ca sāmānyaṃ"]
    ]
    pairs.each do |deva, iast|
      assert_equal Nabu::Normalize.search_form(iast, language: "san-Latn"),
                   Nabu::Normalize.search_form(Nabu::Deva.to_iast(deva), language: "san-Deva"),
                   "fold(transcode(#{deva})) must equal fold(#{iast})"
    end
  end

  # -- to_iast_with_map (P27-2): the KWIC-alignment variant ------------------

  def test_to_iast_with_map_matches_to_iast_byte_for_byte
    ["धर्मन्", "नारायणं नमस्कृत्य नरं चैव नरोत्तमम् ।", "क्त कत", "श्री‍‌", "abc धik"].each do |text|
      iast, map = Nabu::Deva.to_iast_with_map(text)
      assert_equal Nabu::Deva.to_iast(text), iast
      assert_equal iast.length, map.length
    end
  end

  def test_to_iast_with_map_points_output_chars_at_source_chars
    # धर्मन् = ध(0) र(1) ्(2) म(3) न(4) ्(5) → "dharman"
    iast, map = Nabu::Deva.to_iast_with_map("धर्मन्")
    assert_equal "dharman", iast
    assert_equal [0, 0, 0, 1, 3, 3, 4], map,
                 "dh+inherent a ← ध; r ← र (virāma kills its a); m+a ← म; n ← न"
  end
end
