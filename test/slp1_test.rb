# frozen_string_literal: true

require "test_helper"

# Nabu::Slp1 (P17-4): the SLP1 ↔ IAST transcoder at the MW adapter boundary
# (the Betacode precedent). Pins the mapping — including the tricky clusters
# the survey called out — and the both-directions determinism the module
# promises.
class Slp1Test < Minitest::Test
  # The survey's own worked examples plus every non-obvious cluster: the
  # nasals (M/N/Y/R), sibilants (S/z), cerebrals (w/W/q/Q), vowels (f/F/x/X,
  # E/O digraphs), aspirates (K/G/C/J/T/D/P/B), and the ḷ/ḻ split.
  MAPPINGS = {
    "aMSa" => "aṃśa",
    "BAz" => "bhāṣ",
    "kfzRa" => "kṛṣṇa",
    "jYAna" => "jñāna",
    "wIkA" => "ṭīkā",
    "aMhati" => "aṃhati",
    "duHKa" => "duḥkha",
    "Gowaka" => "ghoṭaka",
    "kOsala" => "kausala",
    "Ere" => "aire",
    "cCandas" => "cchandas",
    "qamaru" => "ḍamaru",
    "QORita" => "ḍhauṇita",
    "kxpta" => "kḷpta",
    "ILa" => "īḻa",
    "aTa" => "atha",
    "aDarma" => "adharma",
    "Pala" => "phala",
    "guRa" => "guṇa",
    "vfF" => "vṛṝ"
  }.freeze

  def test_pins_the_letter_mapping_both_directions
    MAPPINGS.each do |slp1, iast|
      assert_equal iast, Nabu::Slp1.to_iast(slp1), "to_iast(#{slp1})"
      assert_equal slp1, Nabu::Slp1.from_iast(iast), "from_iast(#{iast})"
    end
  end

  def test_output_is_nfc
    MAPPINGS.each_value do |iast|
      assert Nabu::Slp1.to_iast(Nabu::Slp1.from_iast(iast)).unicode_normalized?(:nfc)
    end
  end

  # The key2 apparatus: SLP1 accents after the vowel become combining marks
  # ON the vowel, NFC-composed — the print's own forms.
  def test_accents_compose_onto_the_vowel_and_round_trip
    assert_equal "áṃśa", Nabu::Slp1.to_iast("a/MSa")
    assert_equal "bhā́ṣate", Nabu::Slp1.to_iast("BA/zate")
    assert_equal "aṃhatí", Nabu::Slp1.to_iast("aMhati/")
    assert_equal "à", Nabu::Slp1.to_iast("a\\")
    assert_equal "a/MSa", Nabu::Slp1.from_iast("áṃśa")
    assert_equal "BA/zate", Nabu::Slp1.from_iast("bhā́ṣate")
  end

  # ś itself canonically decomposes to s + acute — the accent peel must NOT
  # shred it into "s/".
  def test_accent_peel_never_decomposes_iast_letters
    assert_equal "SaMsa", Nabu::Slp1.from_iast("śaṃsa")
  end

  # Compound seams, √, ˚, digits, punctuation pass through untouched — an
  # unknown character is more honestly kept than guessed at.
  def test_characters_outside_the_inventory_pass_through
    assert_equal "aṃśa—karaṇa", Nabu::Slp1.to_iast("aMSa—karaRa")
    assert_equal "á-kūpāra", Nabu::Slp1.to_iast("a/-kUpAra")
    assert_equal "√ bhāṣ ˚ti 12", Nabu::Slp1.to_iast("√ BAz ˚ti 12")
    assert_equal "aMSa—karaRa", Nabu::Slp1.from_iast("aṃśa—karaṇa")
  end

  # Digraph determinism in reverse: aspirates and ai/au read
  # longest-match-first, never letter by letter.
  def test_reverse_digraphs_win_longest_match_first
    assert_equal "K", Nabu::Slp1.from_iast("kh")
    assert_equal "E", Nabu::Slp1.from_iast("ai")
    assert_equal "O", Nabu::Slp1.from_iast("au")
    assert_equal "~", Nabu::Slp1.from_iast("m̐")
  end

  # x → ḷ (vocalic) versus L → ḻ (Vedic retroflex): the split that keeps the
  # reverse map unambiguous where classical IAST overloads ḷ.
  def test_the_vocalic_and_retroflex_l_are_distinct
    assert_equal "ḷ", Nabu::Slp1.to_iast("x")
    assert_equal "ḻ", Nabu::Slp1.to_iast("L")
    assert_equal "x", Nabu::Slp1.from_iast("ḷ")
    assert_equal "L", Nabu::Slp1.from_iast("ḻ")
  end
end
