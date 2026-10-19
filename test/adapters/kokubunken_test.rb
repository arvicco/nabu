# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # kokubunken — NIJL's own TEI lane (P108-4): the 嘉禄二年本
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

    # -- the person pointers (both branches) --------------------------------

    def test_kokin_poems_carry_their_poet_ref_and_the_document_lists_the_authors
      poem1 = kokin.passages.find { |p| p.urn.end_with?(":n1") }
      assert_equal "kokubunken:在原元方", poem1.annotations["poet_ref"], "the l@resp pointer, our namespace"
      assert_equal [{ "ref" => "kokubunken:在原元方", "name" => "在原元方", "role" => "作者" },
                    { "ref" => "kokubunken:紀貫之", "name" => "紀貫之", "role" => "作者" }],
                   kokin.metadata["persons"], "the 作者 persName surface beside its corresp ref"
      assert_equal %w[在原元方 紀貫之], kokin.metadata["authors"]
      assert_equal %w[kokubunken:在原元方 kokubunken:紀貫之], kokin.metadata["author_ids"]
      refute_includes kokin.metadata["author_ids"], "kokubunken:藤原定家",
                      "persons named in prose or colophons are mentions, never authors"
    end

    def test_manyo_poems_carry_the_poet_of_their_corresp_division
      poem1 = manyo.passages.find { |p| p.urn.end_with?(":m1") }
      assert_equal "kokubunken:雄略天皇", poem1.annotations["poet_ref"]
      assert_equal "雄略天皇", poem1.annotations["poet"]
      poem4 = manyo.passages.find { |p| p.urn.end_with?(":m4") }
      assert_equal "kokubunken:中皇命", poem4.annotations["poet_ref"]
      assert_equal %w[雄略天皇 舒明天皇 中皇命], manyo.metadata["authors"]
      assert_equal({ "ref" => "kokubunken:舒明天皇", "name" => "舒明天皇" }, manyo.metadata["persons"][1],
                   "the division names no role — none is invented")
    end

    def test_documents_carry_language_and_titles
      assert_equal "jpn", kokin.language
      assert_equal "ojp", manyo.language, "the Man'yōshū text is Old Japanese whatever the copy date"
    end
  end
end
