# frozen_string_literal: true

require "test_helper"
require "zlib"

module Adapters
  # The vakk-html family against real reading-view pages (fixtures
  # retrieved 2026-10-21, gzip-stored verbatim): a one-page manuscript
  # (1510 postil notes), a heading-styled multi-page print (the 1535
  # catechism), a German metatext and a court protocol.
  class VakkPageParserTest < Minitest::Test
    TEXTS = File.join(Nabu::TestSupport.fixtures("vakk"), "texts")

    def page(kood, file = "first.html.gz")
      html = Zlib::GzipReader.open(File.join(TEXTS, kood, file), &:read).force_encoding(Encoding::UTF_8)
      Nabu::Adapters::VakkPageParser.new.parse(html)
    end

    def test_a_single_page_text_has_no_selector_and_its_sentences_and_tokens_parse
      p = page("1510-postilla")
      assert_equal "Eeltekst", p.label
      assert_empty p.page_values
      assert_nil p.selected
      assert_equal ["surnud", "Myna [...] tha syno pera tulla", "kychwsap", "dorristkch sees"], p.sentences.map(&:text)
      tha = p.sentences[1].tokens[2]
      assert_equal ["tha", "tahtma", "v", "pers.ind.pr.sg.1.", "eesti"],
                   [tha.form, tha.lemma, tha.pos, tha.morph, tha.lang]
      pera = p.sentences[1].tokens[4]
      assert_equal ["perra", "järel, järele", "adp"], [pera.lemma, pera.gloss, pera.pos]
      gap = p.sentences[1].tokens[1]
      assert_equal "[...]", gap.form
      assert_nil gap.lemma, "an unannotated token keeps its form only"
    end

    def test_the_selector_lists_every_page_and_marks_the_first
      p = page("1535-Koell")
      assert_equal "Lehekülg 1", p.label
      assert_equal (1..10).map(&:to_s), p.page_values
      assert_equal "1", p.selected
      g = page("1644-Gutslaff")
      assert_equal %w[49 258 362 363], g.page_values, "sparse page values ride verbatim"
    end

    def test_compound_halves_close_up_and_punctuation_attaches
      p = page("1535-Koell")
      joined = p.sentences.flat_map(&:tokens).each_cons(2).find do |a, b|
        a.form.end_with?("+") && b.form.start_with?("+")
      end
      refute_nil joined, "the fixture holds a split compound"
      sentence = p.sentences.find { |s| s.tokens.include?(joined.first) }
      merged = joined.first.form.delete_suffix("+") + joined.last.form.delete_prefix("+")
      assert_includes sentence.text, merged
      refute_match(/ [.,;:]/, page("1866-Kahkva-0001").sentences.map(&:text).join(" "),
                   "closing punctuation sits against the word before it")
    end

    def test_a_reading_view_is_recognised
      parser = Nabu::Adapters::VakkPageParser.new
      html = Zlib::GzipReader.open(File.join(TEXTS, "1665-Horn", "first.html.gz"), &:read)
      assert parser.reading_view?(html.force_encoding(Encoding::UTF_8))
      refute parser.reading_view?("<html><body>Vana kirjakeele korpus</body></html>")
    end
  end
end
