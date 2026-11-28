# frozen_string_literal: true

require "test_helper"
require "json"
require "nabu/adapters/orkhon_wikisource_parser"

module Adapters
  # The orkhon-wikisource parser family over the real (trimmed) Turkish
  # Wikisource pages in test/fixtures/tr-wikisource/.
  class OrkhonWikisourceParserTest < Minitest::Test
    PAGES = File.join(Nabu::TestSupport.fixtures("tr-wikisource"), "pages")

    def parse(pageid)
      wikitext = JSON.parse(File.read(File.join(PAGES, "#{pageid}.json"), encoding: "UTF-8")).fetch("wikitext")
      Nabu::Adapters::OrkhonWikisourceParser.new.parse(wikitext)
    end

    def test_a_row_is_six_cells_with_the_alignment_attribute_stripped
      row = parse(5093).rows.first
      assert_equal %w[G1 kt-1-g-13-01], [row.cite, row.row_id]
      assert row.runiform.start_with?("𐱅𐰭𐰼𐰃: 𐱅𐰏: 𐱅𐰭𐰼𐰃𐰓𐰀:"), row.runiform
      refute_includes row.runiform, "style="
      assert row.transliteration.start_with?("tHri: tg: tHride: BOLMŞ:")
      assert row.transcription.start_with?("TeŊRİ: TeG: TeŊRİDE: BOLMuŞ:")
      assert row.translation.start_with?("Tanrı gibi gökte olmuş Türk Bilge Kağan")
      assert_equal "Güney Yüzü", row.face
      assert_nil row.stone
    end

    def test_faces_carry_the_caption_and_its_declared_line_count
      faces = parse(5093).faces
      assert_equal ["Güney Yüzü", "Kuzeydoğu Yüzü"], faces.map(&:face)
      south = faces.first
      assert_equal "Kül Tigin taşı, 1. yüz (güney) 13 dizi", south.caption
      assert_equal [13, 2], [south.declared_lines, south.lines], "the fixture keeps 2 of the face's 13 rows"
      assert_equal [1, 1], [faces.last.declared_lines, faces.last.lines]
    end

    def test_tonyukuk_headings_nest_the_face_under_its_stone
      rows = parse(5096).rows
      assert_equal %w[1-B1 1-B2 2-B1], rows.map(&:cite)
      assert_equal ["Birinci Taş", "Birinci Taş", "İkinci Taş"], rows.map(&:stone)
      assert_equal ["Batı Yüzü"] * 3, rows.map(&:face)
    end

    def test_lacuna_rows_and_the_apparatus
      result = parse(5095)
      assert_equal %w[B7 B8 B9 GB1], result.rows.map(&:cite)
      b8 = result.rows[1]
      assert_equal ["[...]:", "[...]:", "[...]:", "[...]"],
                   [b8.runiform, b8.transliteration, b8.transcription, b8.translation]
      assert_equal ["Orhun Yazıtları Bilge Kağan Anıtı. " \
                    "https://web.archive.org/web/20200424174719/https://www.turkbitig.com/bilgekagan.html"],
                   result.bibliography
    end

    def test_header_and_kaynak_bibliography
      result = parse(5093)
      assert_equal({ "başlık" => "Orhun Yazıtları (Kül Tigin)", "vikipedi" => "Kül Tigin Yazıtı" }, result.header)
      assert_equal ["Ata, Aysu (2011). Orhun Türkçesi. Anadolu Üniversitesi. ISBN 978-975-06-1020-2",
                    "Tekin, Talat (1995). Orhon Yazıtları, Kül Tigin, Bilge Kağan, Tunyukuk. Simurg Yayınevi. " \
                    "ISBN 975-7172-04-9. https://altaica.ru/LIBRARY/Tekin%20Talat/Tekin_Orhon%20Yazitlari%201998.pdf"],
                   result.bibliography
    end

    def test_the_landing_page_has_no_rows
      assert_empty parse(5338).rows
    end

    def test_a_reshaped_row_raises
      wikitext = "{| class=\"wikitable\"\n|-\n| G1\n| kt-1\n| 𐱅𐰭𐰼𐰃:\n|}\n"
      error = assert_raises(Nabu::ParseError) { Nabu::Adapters::OrkhonWikisourceParser.new.parse(wikitext) }
      assert_includes error.message, "3 cells, expected 6"
    end
  end
end
