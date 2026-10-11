# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # The `usfm` parser family (P117-2): one USFM book per file. Pinned
  # against real Rs1Bible books (test/fixtures/vuk-danicic/) plus a few
  # general-USFM shapes the family must survive (poetry markers carrying
  # verse text, several verses on one line, footnotes).
  class UsfmParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("vuk-danicic")

    def parse(name) = Nabu::Adapters::UsfmParser.new.parse(File.join(FIXTURES, name))

    def parse_text(source)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "x.usfm")
        File.write(path, source)
        Nabu::Adapters::UsfmParser.new.parse(path)
      end
    end

    def test_header_markers_give_the_book_code_heading_and_toc
      book = parse("44-JHN.usfm")
      assert_equal "JHN", book.id, "the \\id trailing comment is not the code"
      assert_equal "John", book.heading
      assert_equal({ "1" => "The Gospel According to St. John", "2" => "John", "3" => "Jhn" }, book.toc)
    end

    def test_verses_carry_chapter_and_verse_and_skip_layout_markers
      book = parse("44-JHN.usfm")
      assert_equal 51, book.verses.size
      first = book.verses.first
      assert_equal ["1", "1", "U početku bješe riječ, i riječ bješe u Boga, i Bog bješe riječ."],
                   [first.chapter, first.verse, first.text]
      refute(book.verses.any? { |v| v.text.include?("\\") }, "no marker survives into text")
      assert_equal 13, parse("64-2JN.usfm").verses.size
      assert_equal 21, parse("31-OBA.usfm").verses.size
    end

    def test_poetry_markers_continue_the_running_verse
      book = parse_text("\\id PSA\n\\c 1\n\\q1 \\v 1 Blessed is the man\n\\q2 that walketh not\n" \
                        "\\s Heading\n\\v 2 But his delight\n")
      assert_equal ["Blessed is the man that walketh not", "But his delight"], book.verses.map(&:text)
    end

    def test_several_verses_on_one_line_and_footnotes_dropped
      book = parse_text("\\id GEN\n\\c 1\n\\p \\v 1 In the \\add beginning\\add* " \
                        "\\f + \\fr 1:1 \\ft note\\f*God. \\v 2-3 And the earth.\n")
      assert_equal([%w[1 1], %w[1 2-3]], book.verses.map { |v| [v.chapter, v.verse] })
      assert_equal "In the beginning God.", book.verses.first.text
      assert_equal "And the earth.", book.verses.last.text
    end

    def test_malformed_structure_is_a_parse_error
      assert_raises(Nabu::ParseError) { parse_text("\\id GEN\n\\v 1 orphan verse\n") }
      assert_raises(Nabu::ParseError) { parse_text("\\id GEN\n\\c\n\\v 1 x\n") }
      assert_raises(Nabu::ParseError) { parse_text("\\c 1\n\\v 1 x\n") }
    end
  end
end
