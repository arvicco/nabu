# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # The estnltk-tsv family over real DIGAR token tables (test/fixtures/
  # digar-corpora/README.md): the token column read verbatim, the
  # digitizer's stamp dropped as furniture, deterministic token windows.
  class EstnltkTsvParserTest < Minitest::Test
    DIR = File.join(Nabu::TestSupport.fixtures("digar-corpora"), "processed_pdf_tsv")
    HYMN = File.join(DIR, "b17885899.pdf.txt.tsv")        # 1819 Riga hymn sheet, Fraktur, no stamp
    DOLLHOUSE = File.join(DIR, "b20396119.pdf.txt.tsv")   # 193-? picture book, stamp on every page
    JENOWEWA = File.join(DIR, "b1623912x.pdf.txt.tsv")    # 1841: image-only PDF — stamps alone
    EMPTY = File.join(DIR, "b10014949.pdf.txt.tsv")       # header-only table

    def parser = Nabu::Adapters::EstnltkTsvParser.new

    def test_the_token_column_verbatim_in_row_order
      book = parser.parse(HYMN)
      assert_equal 254, book.token_count
      assert_equal 0, book.stamps
      text = book.windows.map(&:text).join(" ")
      assert_includes text, "Enne pihti . Is . 110. 7. Asus Mnno Sjge ello , Jesus minno rööm ja illo"
      assert_includes text, "kom ( cid : 173 ) bed", "pdf2txt's glyph escape is upstream text, kept"
    end

    def test_windows_close_on_a_sentence_end_past_the_minimum_and_cover_every_row
      book = parser.parse(HYMN)
      assert_equal 2, book.windows.size
      first, second = book.windows
      assert_equal [0, 137], [first.first_row, first.last_row]
      assert first.text.end_with?("."), "a window closes on a sentence-final token"
      assert_operator first.text.split.size, :>=, Nabu::Adapters::EstnltkTsvParser::MIN_TOKENS
      assert_equal [138, 253], [second.first_row, second.last_row], "the tail closes the book"
    end

    def test_both_stamp_renderings_drop_and_are_counted
      book = parser.parse(DOLLHOUSE)
      assert_equal 11, book.stamps
      text = book.windows.map(&:text).join(" ")
      refute_includes text, "Rahvusraamatukogu digitaalarhiiv DIGAR"
      refute_includes text, Nabu::Adapters::EstnltkTsvParser::VERTICAL_STAMP.join(" "), "the vertical stamp drops too"
      assert_includes text, "Mul on nukuke Mall ja Jukuke ja veel kutsikas õige kenake ."
      assert_includes text, "R A G D v I i i w a m H i", "an OCR-mangled stamp is not matched — it stays text"
    end

    def test_a_stamp_only_table_yields_no_window
      book = parser.parse(JENOWEWA)
      assert_equal 108, book.token_count
      assert_equal 27, book.stamps
      assert_empty book.windows
    end

    def test_the_hard_cap_closes_a_window_without_a_sentence_end
      Dir.mktmpdir do |dir|
        path = File.join(dir, "b10000000.pdf.txt.tsv")
        header = File.foreach(HYMN).first
        rows = (0...450).map { |i| "#{i}\tsõna#{i}#{"\t" * 10}" }
        File.write(path, "#{header}#{rows.join("\n")}\n")
        windows = parser.parse(path).windows
        assert_equal([400, 50], windows.map { |w| w.text.split.size })
      end
    end

    def test_emptiness_is_header_only
      assert Nabu::Adapters::EstnltkTsvParser.empty?(EMPTY)
      refute Nabu::Adapters::EstnltkTsvParser.empty?(HYMN)
    end

    def test_a_table_without_the_token_column_is_a_parse_error
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bad.tsv")
        File.write(path, "\tsomething_else\n0\tx\n")
        assert_raises(Nabu::ParseError) { parser.parse(path) }
      end
    end
  end
end
