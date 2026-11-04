# frozen_string_literal: true

require "test_helper"

module Adapters
  # The ninjal-txt family over trimmed real NINJAL transcription files
  # (test/fixtures/ninjal-textdb/README.md): the two line shapes the
  # Kirishitan sets ship — PAGED (a "（page）" header, then "n<TAB>text"
  # lines numbered within the page: amhk, amis) and CITED ("PPP.LL<TAB>text"
  # with "///" page/column breaks: cmhab) — each file's own BOM and line
  # terminator (amhk-r is bare-CR) decoded at the boundary.
  class NinjalTxtParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("ninjal-textdb")
    Parser = Nabu::Adapters::NinjalTxtParser

    def parse(rel, shape:) = Parser.parse(File.binread(File.join(FIXTURES, rel)), shape: shape, path: rel)

    def test_paged_lines_carry_page_and_line_from_a_bare_cr_file_with_bom
      result = parse("amhk/amhk-r-001/amhk-r-001.txt", shape: :paged)
      first = result.lines.first
      assert_equal %w[扉 1 NIFONNO], [first.page, first.line, first.text]
      assert_equal "天草版平家物語（ローマ字翻字テキスト）", result.title, "the BOM is stripped from the title line"
      assert_equal %w[扉 序1 序2 序3 3 8], result.lines.map(&:page).uniq
      opening = result.lines.find { |line| line.page == "3" && line.line == "9" }
      assert_equal "VManojô.Qẽgueônobŏ,Feiqe no yurai ga qi", opening.text
    end

    # Upstream mis-keys four line numbers in the Feiqe (8.15 printed as "1",
    # and three more — censused): the number stays verbatim, the repeat's
    # key takes "-b" (the oncoj duplicate-id precedent), in both layers alike.
    def test_a_repeated_line_number_keeps_its_number_and_takes_a_b_key
      romanized = parse("amhk/amhk-r-001/amhk-r-001.txt", shape: :paged).lines.select { |l| l.page == "8" }
      repeat = romanized[14]
      assert_equal ["1", "8.1-b"], [repeat.line, repeat.key]
      assert_equal "cono coto ua nanto to,votazzune attareba,Ta-", repeat.text
      assert_equal "8.1", romanized.first.key
      kana = parse("amhk/amhk-k-001/amhk-k-001.txt", shape: :paged).lines.select { |l| l.page == "8" }
      assert_equal "8.1-b", kana[14].key
    end

    def test_the_footer_colophon_is_mined
      result = parse("amhk/amhk-r-001/amhk-r-001.txt", shape: :paged)
      assert_equal "大英図書館蔵本（Or.59.aa.1)", result.base_text
      assert_equal %w[片山久留美 渡辺由貴 金子愛 藤原慧悟 堀麻美 堀川千晶], result.transcribers
      assert_includes result.history, "2019年3月25日公開"
    end

    def test_the_kana_layer_shares_the_romanization_keys
      romanized = parse("amis/amis-r-001/amis-r-001.txt", shape: :paged)
      kana = parse("amis/amis-k-001/amis-k-001.txt", shape: :paged)
      assert_equal romanized.lines.map(&:key), kana.lines.map(&:key)
      assert_equal "ＥＳＯＰＯの", kana.lines.first.text
    end

    def test_cited_lines_split_the_page_label_and_skip_the_break_markers
      result = parse("cmhab/cmhab-r-001/cmhab-r-001.txt", shape: :cited)
      assert_equal ["[*001]", "01", "CONTEMPTVS"], [result.lines.first.page, result.lines.first.line,
                                                    result.lines.first.text]
      assert_equal ["[*001]", "001", "205[=206]", "[445]a", "[445]b"], result.lines.map(&:page).uniq
      refute(result.lines.any? { |line| line.text == "///" })
      assert_equal "ヘルツォーク・アウグスト図書館蔵本（Shelfmark: 57.13 Eth.)", result.base_text
      assert_equal %w[オースタカンプ・スヱン ノイツラ・ゾフィー 宮川創], result.transcribers
    end

    def test_a_stray_body_line_is_a_parse_error
      bytes = File.binread(File.join(FIXTURES, "amis/amis-r-001/amis-r-001.txt"))
                  .sub("1\tESOPONO", "ESOPONO without its number")
      assert_raises(Nabu::ParseError) { Parser.parse(bytes, shape: :paged, path: "x") }
    end

    def test_invalid_utf8_is_a_parse_error
      assert_raises(Nabu::ParseError) { Parser.parse("\xFF\xFE".b, shape: :paged, path: "x") }
    end
  end
end
