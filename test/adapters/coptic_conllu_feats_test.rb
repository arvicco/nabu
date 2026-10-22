# frozen_string_literal: true

require "test_helper"

# CopticConlluFeats: the UD FEATS join from Coptic Scriptorium's CoNLL-U
# export onto the TT parse's tokens. Real fixture pair: Besa's On Lack of
# Food, the TT file and its CoNLL-U twin (both whole, same release).
class CopticConlluFeatsTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("coptic-scriptorium")
  TT = File.join(FIXTURES, "besa-letters", "besa.letters_TT", "on_lack_of_food.tt")
  CONLLU = File.join(FIXTURES, "besa-letters", "besa.letters_CONLLU", "on_lack_of_food.conllu")

  FEATS = Nabu::Adapters::CopticConlluFeats

  def units
    Nabu::Adapters::CopticTtParser.new.parse(File.read(TT), label: TT).units
  end

  def tokens(units) = units.flat_map { |unit| unit.annotations["tokens"] }

  # Word lines only — multiword range lines (1-3) and comments skipped; a
  # "_" FEATS cell is no feature (nil).
  def test_words_read_the_word_lines_with_their_feats
    words = FEATS.words(File.read(CONLLU))
    assert_equal 97, words.size
    assert_equal ["ⲉ", nil], [words[0].form, words[0].feats]
    assert_equal ["ⲧⲉⲧⲛ", "Definite=Def|Number=Plur|Person=2|PronType=Prs"], [words[1].form, words[1].feats]
  end

  # The forms are decoded the way the TT parser decodes attributes (HTML
  # entities unescaped, NFC) — the census's only spelling gaps between
  # the two exports (sahidic.ot's "ϫⲟⲩϩ&lt;ⲉ&gt;", johannes-canons' U+0387).
  def test_word_forms_unescape_and_compose_like_the_tt_attributes
    assert_equal "ϫⲟⲩϩ<ⲉ>", FEATS.form("ϫⲟⲩϩ&lt;ⲉ&gt;")
    assert_equal "·", FEATS.form("·"), "GREEK ANO TELEIA composes to MIDDLE DOT, as in the TT"
  end

  def test_an_aligned_twin_joins_feats_onto_the_tokens
    parsed = units
    assert_equal :joined, FEATS.join!(parsed, FEATS.words(File.read(CONLLU)))
    u2 = tokens(parsed).find { |token| token["id"] == "u2" }
    assert_equal "Definite=Def|Number=Plur|Person=2|PronType=Prs", u2["feats"]
    u1 = tokens(parsed).find { |token| token["id"] == "u1" }
    refute u1.key?("feats"), "a \"_\" cell joins nothing"
  end

  # Exact alignment or nothing: a twin whose word sequence differs (the
  # census's two magical-papyri files drop the final token) joins NO
  # feature — a shifted join would hang every feature on the wrong word.
  def test_a_misaligned_twin_joins_nothing
    words = FEATS.words(File.read(CONLLU))
    parsed = units
    assert_equal :misaligned, FEATS.join!(parsed, words[0...-1])
    assert(tokens(parsed).none? { |token| token.key?("feats") })
  end

  # sahidica.nt ships 227 of its loose CoNLL-U files as "\n\n"
  # placeholders: no words, the honest absence.
  def test_a_placeholder_or_missing_twin_is_absent
    parsed = units
    assert_equal :absent, FEATS.join!(parsed, FEATS.words("\n\n"))
    assert_equal :absent, FEATS.join!(parsed, nil)
    assert(tokens(parsed).none? { |token| token.key?("feats") })
  end
end
