# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "zlib"
require "json"

module Adapters
  # The ia-hocr-text parser family: an archive.org item's hOCR
  # derivative PAIR — <stem>_hocr_searchtext.txt.gz (the OCR text, one line
  # per hOCR paragraph) + <stem>_hocr_pageindex.json.gz (per hOCR page
  # [text_start, text_end, hocr_start, hocr_end], text offsets in
  # CHARACTERS) — read back into pages. Fixture: Miklosich, Das Imperfect
  # in den slavischen Sprachen (1874), both files whole and verbatim.
  class IaHocrTextTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("slavistics-pd")
    STEM = File.join(FIXTURES, "dasimperfectinde00mikl", "dasimperfectinde00mikl")

    def pages
      Nabu::Adapters::IaHocrText.read_pages(searchtext_path: "#{STEM}_hocr_searchtext.txt.gz",
                                            pageindex_path: "#{STEM}_hocr_pageindex.json.gz")
    end

    def test_every_hocr_page_is_read_with_its_one_based_ordinal
      read = pages
      assert_equal 34, read.size, "the page index lists 34 hOCR pages"
      assert_equal (1..34).to_a, read.map(&:ordinal)
    end

    def test_blank_pages_read_as_empty_text
      read = pages
      assert_equal "", read[0].text, "page 1 is a blank leaf (index [0, 0, …])"
      assert_equal "", read[2].text
      assert_equal(30, read.count { |page| !page.text.empty? })
    end

    def test_page_text_is_the_offset_slice_with_horizontal_whitespace_squeezed
      title = pages[3]
      assert_equal 4, title.ordinal
      assert title.text.start_with?("i\nPG 159 .M5 Copy 1\nDAS IMPERFECT\nIN DEN\nSLAYISCHEN SPRACHEN\nVON\n" \
                                    "FR. MIKLOSICH"),
             "upstream's double spaces fold to one; the OCR's misreadings (SLAYISCHEN) stay verbatim"
      assert_includes pages[4].text, "Sitzungsberichte der phil.-hist. Classe der kais. Akademie"
    end

    def test_text_is_nfc
      pages.each { |page| assert page.text.unicode_normalized?(:nfc) }
    end

    def test_wordlike_share_measures_the_ocr_honestly
      share = Nabu::Adapters::IaHocrText.wordlike_share(pages.map(&:text))
      assert_in_delta 0.79, share, 0.005
      assert_in_delta 0.5, Nabu::Adapters::IaHocrText.wordlike_share(["Wort ^%$"]), 0.001
      assert_nil Nabu::Adapters::IaHocrText.wordlike_share([""])
    end

    def test_stem_paths_name_the_two_derivatives
      paths = Nabu::Adapters::IaHocrText.paths(File.join("w", "item"), "1. Lautlehre (1879)")
      assert_equal File.join("w", "item", "1. Lautlehre (1879)_hocr_searchtext.txt.gz"), paths.fetch(:searchtext)
      assert_equal File.join("w", "item", "1. Lautlehre (1879)_hocr_pageindex.json.gz"), paths.fetch(:pageindex)
    end

    def test_an_offset_past_the_text_is_a_parse_error
      with_pair("abc\n", [[0, 2, 0, 1], [2, 9, 1, 2]]) do |text, index|
        error = assert_raises(Nabu::ParseError) do
          Nabu::Adapters::IaHocrText.read_pages(searchtext_path: text, pageindex_path: index)
        end
        assert_match(/page 2/, error.message)
      end
    end

    def test_overlapping_offsets_are_a_parse_error
      with_pair("abcdef", [[0, 4, 0, 1], [2, 6, 1, 2]]) do |text, index|
        assert_raises(Nabu::ParseError) do
          Nabu::Adapters::IaHocrText.read_pages(searchtext_path: text, pageindex_path: index)
        end
      end
    end

    def test_a_malformed_index_or_gzip_is_a_parse_error
      with_pair("abc", { "pages" => [] }) do |text, index|
        assert_raises(Nabu::ParseError) do
          Nabu::Adapters::IaHocrText.read_pages(searchtext_path: text, pageindex_path: index)
        end
      end
      Dir.mktmpdir do |dir|
        bad = File.join(dir, "x_hocr_searchtext.txt.gz")
        File.write(bad, "not gzip")
        assert_raises(Nabu::ParseError) do
          Nabu::Adapters::IaHocrText.read_pages(searchtext_path: bad, pageindex_path: "#{STEM}_hocr_pageindex.json.gz")
        end
      end
    end

    private

    def with_pair(text, index)
      Dir.mktmpdir do |dir|
        text_path = File.join(dir, "x_hocr_searchtext.txt.gz")
        index_path = File.join(dir, "x_hocr_pageindex.json.gz")
        Zlib::GzipWriter.open(text_path) { |gz| gz.write(text) }
        Zlib::GzipWriter.open(index_path) { |gz| gz.write(JSON.generate(index)) }
        yield text_path, index_path
      end
    end
  end
end
