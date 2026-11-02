# frozen_string_literal: true

require "test_helper"

# The Greek syllabifier + quantity rules (P152): η/ω long and ε/ο short by
# nature; α/ι/υ (the dichrona) decided only by a mark (circumflex, iota
# subscript, macron/breve) or by an accent law; diphthongs; position (ζ ξ ψ
# double); muta cum liquida and epic correption anceps; written elision.
class ScansionGreekTest < Minitest::Test
  def syl(text) = Nabu::Scansion::Greek.syllables(text)

  def test_nature_from_the_letters
    q = syl("μῆνιν ἔθηκε").map(&:quantity)
    assert_equal :long, q[0], "μῆ: η, and circumflexed"
    assert_equal :short, q[2], "ἔ: epsilon, open"
    assert_equal :long, q[3], "θη: eta"
  end

  def test_dichrona_without_a_mark_or_an_accent_law_are_anceps
    assert_equal :anceps, syl("μυρίʼ ἔτη")[0].quantity
  end

  def test_iota_subscript_and_circumflex_lengthen_a_dichronon
    assert_equal :long, syl("θεᾷ τε")[1].quantity
    assert_equal :long, syl("πᾶν τε")[0].quantity
  end

  def test_diphthongs_and_diaeresis
    assert_equal 2, syl("οὐλος").size
    assert_equal 5, syl("εἰσαΐοντας").size, "εἰ-σα-ΐ-ον-τας: the diaeresis splits αϊ"
  end

  def test_double_consonants_make_position
    assert_equal :long, syl("ἄξονα")[0].quantity
    assert_equal :long, syl("ἄλγεα")[0].quantity
  end

  def test_muta_cum_liquida_is_anceps
    assert_equal :anceps, syl("πατρὸς ἔτη")[0].quantity
  end

  def test_epic_correption_makes_a_final_long_before_a_vowel_anceps
    assert_equal :anceps, syl("ἄνδρα μοι ἔννεπε")[2].quantity
  end

  def test_written_elision_joins_the_consonant_to_the_next_word
    # δʼ ἔσαν: δ is the onset of ἔ — no position for the syllable before
    syllables = syl("ὧς ἄρʼ ἔφη")
    assert_equal 4, syllables.size
  end

  def test_antepenult_accent_makes_a_final_dichronon_short
    # θάλασσα — accent on the antepenult forces a short final α
    # (a following word, so the α is not the line's final anceps)
    assert_equal :short, syl("θάλασσα καὶ")[2].quantity
  end

  def test_acute_on_a_long_penult_makes_the_final_dichronon_long
    # χώρα: acute (not circumflex) on long ω ⇒ the final α is long
    assert_equal :long, syl("χώρα καὶ")[1].quantity
  end

  def test_syllable_texts_split_clusters_between_nuclei
    # display texts carry base letters (marks are read, not reprinted)
    assert_equal %w[αλ γε α], syl("ἄλγεα").map(&:text)
  end

  def test_non_greek_letters_are_refused
    assert_raises(Nabu::Scansion::Unscannable) { syl("arma virumque") }
  end
end
