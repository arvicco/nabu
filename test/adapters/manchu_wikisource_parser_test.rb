# frozen_string_literal: true

require "test_helper"
require "json"

module Adapters
  # The manchu-wikisource parser family over REAL Multilingual Wikisource
  # pages (the mnc-wikisource fixture envelopes): the Manchu header, the
  # MongolUnicode wrappers, <poem>/<br> verse, tables, numbered lists,
  # apparatus headings and the long-paragraph sentence split.
  class ManchuWikisourceParserTest < Minitest::Test
    PAGES = File.join(Nabu::TestSupport.fixtures("mnc-wikisource"), "pages")

    def parse(pageid)
      envelope = JSON.parse(File.read(File.join(PAGES, "#{pageid}.json")))
      Nabu::Adapters::ManchuWikisourceParser.new.parse(envelope.fetch("wikitext"))
    end

    def test_the_manchu_header_is_captured_never_text
      result = parse(84_446)
      assert_equal "ᠴᡳᠩ ᡤᡠᡵᡠᠨ ᡳ ᡧᡝᠩᡯᡠ", result.header["author"], "the page's own U+202F suffix connector"
      assert_equal "芝徑雲隄", result.header["notes"]
      refute(result.lines.any? { |line| line.text.include?("ᡧᡝᠩᡯᡠ") })
    end

    def test_poem_lines_inside_the_mongol_unicode_wrapper_are_the_text
      lines = parse(84_446).lines.map(&:text)
      assert_equal 8, lines.size
      assert_equal "ᠮᡠᡴᡝ ᠪᡝ ᡥᠠᡶᡳᡨᠠᠮᡝ ᡩᠠᠯᠠᠨ ᠠᡵᠠᡶᡳ᠈", lines.first
    end

    def test_table_cells_become_lines_and_dotted_fillers_drop
      lines = parse(64_127).lines
      assert_equal "1. fudzi hendume: tacimbime erinderi urebuci,inu urgun wakao?", lines.first.text
      assert_equal "1. 子曰:学而时习之、不亦说乎?", lines[1].text
      assert(lines.none? { |line| line.text.include?("....") })
      assert_equal "leolen gisurne (论语) - tacingga ujui fiyelen (学而第一)", lines.first.section
    end

    def test_a_translation_section_is_apparatus
      lines = parse(64_132).lines
      assert_equal "amba age si aibici jihe?", lines.first.text
      assert(lines.none? { |line| line.text.match?(/\p{Han}/) }, "the modern Chinese translation drops")
      assert(lines.all? { |line| line.section == "Text" })
    end

    def test_an_external_links_section_is_apparatus
      lines = parse(168_826).lines
      assert_equal "elhe taifin i orin jakūci aniya nadan biyai orin duin.", lines.last.text
    end

    def test_a_thirty_thousand_character_paragraph_splits_at_the_manchu_full_stop
      lines = parse(260_168).lines
      assert_operator lines.size, :>, 100
      assert(lines.all? { |line| line.text.length < 2_000 })
      assert(lines[0..-2].all? { |line| line.text.end_with?("᠉") })
    end

    def test_the_case_suffix_hack_renders_as_narrow_no_break_space
      text = Nabu::Adapters::ManchuWikisourceParser.new.send(:resolve_html, "ᠮᠠᠨᠵᡠ&nbsp;&zwj;ᡳ")
      assert_equal "ᠮᠠᠨᠵᡠ ᡳ", text
    end
  end
end
