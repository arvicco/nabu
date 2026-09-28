# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # kokubunken — NIJL's own TEI lane (P108-4, Q89.3): the 嘉禄二年本
  # 古今和歌集 transcription and the 廣瀬本/元暦校本 Man'yōshū TEI
  # (a DIFFERENT manuscript line from held ONCOJ's base — the
  # two-editions doctrine), both CC BY 4.0 README-verbatim. One
  # adapter, two shape branches keyed by filename.
  class KokubunkenTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("kokubunken")

    def conformance_adapter = Nabu::Adapters::Kokubunken.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "kokubunken"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def kokin = documents.find { |d| d.urn.include?("kokin") } || flunk("kokin missing")
    def manyo = documents.find { |d| d.urn.include?("manyo-hirose") } || flunk("hirose missing")

    # -- the kokin branch ---------------------------------------------------

    def test_kokin_poems_are_passages_with_poet_and_headnote
      poem1 = kokin.passages.find { |p| p.urn.end_with?(":n1") } || flunk("poem n1 missing")
      assert_includes poem1.text, "年の内に"
      assert_includes poem1.text, "春はきにけり"
      assert_equal "在原元方", poem1.annotations["poet"]
      assert_includes poem1.annotations["kotobagaki"], "たちける"
    end

    def test_kokin_preface_phrases_are_passages_reading_the_lemma
      kana = kokin.passages.find { |p| p.urn.end_with?(":kana1-7") } || flunk("kana1-7 missing")
      assert_includes kana.text, "おに神", "app takes the lem (the 国 base text)"
      refute_includes kana.text, "鬼神", "the rdg variant never leaks into the text"
      assert_includes kana.annotations["rdg"], "おにかみ", "the variant rides the annotation"
    end

    # -- the manyo branch ---------------------------------------------------

    def test_manyo_tanka_serve_the_manyogana_base_layer
      poem4 = manyo.passages.find { |p| p.urn.end_with?(":m4") } || flunk("manyo0004 missing")
      assert_includes poem4.text, "玉剋春内乃大野尓"
      refute_match(/[ァ-ヶ]/, poem4.text, "the kun katakana layer stays out of the base text")
      assert_includes poem4.annotations["kun"], "キ", "the kun reading rides the annotation"
      assert_equal "4", poem4.annotations["kokka_taikan"]
    end

    def test_manyo_choka_parse_from_their_ab_shape
      poem1 = manyo.passages.find { |p| p.urn.end_with?(":m1") } || flunk("manyo0001 missing")
      refute_empty poem1.text
      assert_equal "1", poem1.annotations["kokka_taikan"]
    end

    def test_documents_carry_language_and_titles
      assert_equal "jpn", kokin.language
      assert_equal "ojp", manyo.language, "the Man'yōshū text is Old Japanese whatever the copy date"
    end
  end
end
