# frozen_string_literal: true

require "test_helper"

# The Latin syllabifier + quantity rules (P152, the scansion lane): position,
# diphthongs, vowel-before-vowel, consonantal i/u, elision — and NOTHING
# guessed from natural length (an open syllable whose vowel length the rules
# cannot know stays anceps for the meter to decide). Constructed cases with
# textbook scansions.
class ScansionLatinTest < Minitest::Test
  def quantities(text) = Nabu::Scansion::Latin.syllables(text).map(&:quantity)

  def texts(text) = Nabu::Scansion::Latin.syllables(text).map(&:text)

  def test_position_and_diphthong_rules
    # Ar-ma vi-rum-que ca-no Tro-iae qui pri-mus a-bo-ris
    syl = Nabu::Scansion::Latin.syllables("Arma virumque cano, Troiae qui primus ab oris")
    assert_equal 15, syl.size
    q = syl.map(&:quantity)
    assert_equal :long, q[0], "Ar: r+m closes the syllable (position)"
    assert_equal :long, q[3], "rum: m+qu (position)"
    assert_equal :long, q[7], "Tro: intervocalic consonantal i is double (Troi-iae)"
    assert_equal :long, q[8], "iae: the ae diphthong"
    assert_equal :anceps, q[1], "ma: open, natural length unknown — never guessed"
    assert_equal :anceps, q[14], "the line's final syllable is anceps"
  end

  def test_elision_drops_the_final_vowel_and_vowel_plus_m
    # li-to-ra mul-t(um) il-l(e) et ter-ris ia-cta-tus et al-to
    syl = Nabu::Scansion::Latin.syllables("litora, multum ille et terris iactatus et alto")
    assert_equal 14, syl.size
    assert(syl.any?(&:elided_before), "an elision is recorded on the surviving syllable")
    assert_equal :long, syl[3].quantity, "mul: l+t survive the elided -um"
  end

  def test_vowel_before_vowel_is_short_inside_a_word
    syl = Nabu::Scansion::Latin.syllables("violentaque")
    assert_equal :short, syl[0].quantity, "vi-o: vocalis ante vocalem corripitur"
  end

  def test_muta_cum_liquida_is_anceps_within_a_word
    syl = Nabu::Scansion::Latin.syllables("patris")
    assert_equal :anceps, syl[0].quantity, "pa-tr: muta cum liquida may or may not make position"
  end

  def test_a_final_consonant_before_an_initial_consonant_makes_position
    syl = Nabu::Scansion::Latin.syllables("et tibi")
    assert_equal :long, syl[0].quantity
  end

  def test_qu_is_a_single_consonant_and_x_a_double_one
    assert_equal :anceps, Nabu::Scansion::Latin.syllables("aqua est")[0].quantity
    assert_equal :long, Nabu::Scansion::Latin.syllables("rex est")[0].quantity
  end

  def test_consonantal_u_in_u_only_editions
    # uirumque = virumque; nouus = no-vus; seruus = ser-vus
    assert_equal 3, Nabu::Scansion::Latin.syllables("uirumque").size
    assert_equal 2, Nabu::Scansion::Latin.syllables("nouus").size
    assert_equal 2, Nabu::Scansion::Latin.syllables("seruus").size
    assert_equal 2, Nabu::Scansion::Latin.syllables("suus").size, "su-us stays vocalic"
  end

  def test_the_interjection_o_is_never_elided
    assert_equal 3, Nabu::Scansion::Latin.syllables("o ego").size, "o | e-go: hiatus after the interjection"
  end

  def test_diaeresis_splits_a_would_be_diphthong
    assert_equal 3, Nabu::Scansion::Latin.syllables("poëta").size
    assert_equal 2, Nabu::Scansion::Latin.syllables("poena").size
  end

  def test_foreign_script_is_refused_not_scanned
    assert_raises(Nabu::Scansion::Unscannable) do
      Nabu::Scansion::Latin.syllables("quamquam difficile est se noscere; γνῶθι σεαυτόν")
    end
  end

  def test_proper_names_escape_vocalis_ante_vocalem
    # Aenēās: a capitalized word past the line's first is a name, often
    # Greek, where the native shortening does not hold
    syl = Nabu::Scansion::Latin.syllables("et pater Aeneas iam")
    assert_equal :anceps, syl[4].quantity
    assert_equal :short, Nabu::Scansion::Latin.syllables("et pater aeneas iam")[4].quantity
  end

  def test_greek_hiatus_pairs_and_closed_word_lists
    assert_equal 7, Nabu::Scansion::Latin.syllables("quid Troes potuere").size, "Tro-es, not a diphthong"
    assert_equal 5, Nabu::Scansion::Latin.syllables("frigidus aer").size, "a-er"
    assert_equal 6, Nabu::Scansion::Latin.syllables("clamet io forti").size, "i-o, the interjection"
    assert_equal 3, Nabu::Scansion::Latin.syllables("ei mihi").size, "ei mi-hi"
    assert_equal 2, Nabu::Scansion::Latin.syllables("heus tu").size
    assert_equal 3, Nabu::Scansion::Latin.syllables("disiectam").size, "dis-iec-tam"
    assert_equal :anceps, Nabu::Scansion::Latin.syllables("fies tu")[0].quantity, "fī-ēs"
  end

  def test_grammar_defaults_ride_only_on_anceps_word_final_syllables
    syl = Nabu::Scansion::Latin.syllables("cano Troiae qui primus ab oris")
    assert_equal :long, syl[1].default, "final -o"
    assert_equal :long, syl[4].default, "a vowel-final monosyllable"
    assert_equal :short, syl[6].default, "final -us"
    assert_nil syl[0].default, "word-internal open syllables get none"
    assert_nil syl[3].default, "a long syllable needs none"
    elided = Nabu::Scansion::Latin.syllables("multum ille")
    assert(elided.none?(&:default), "an elided ending gets none (and the line-final anceps none)")
  end

  def test_texts_are_reported_per_surviving_syllable
    assert_equal %w[ar ma], texts("arma")
  end
end
