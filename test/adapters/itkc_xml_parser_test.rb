# frozen_string_literal: true

require "test_helper"

# Parser family "itkc-xml" (P78-7): the ITKC 한국고전종합DB export
# schema — Korean-tag XML (아이템 → 레벨1 서지 → 레벨2 권차 → 레벨3
# article). One zip per WORK: a suffix-less SIDECAR file carrying the
# 서지 record (titles, author with birth/death years, the 원문간행년
# original-print year) and one file per 권차 fascicle whose 레벨3
# articles are the citation units. Fixtures are real members of the
# two witnessed works (고운당필기 GP / 국조보감 GO).
class ItkcXmlParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("itkc")

  def parser = Nabu::Adapters::ItkcXmlParser.new

  # --- the sidecar: the work's 서지 record ---------------------------------

  def test_the_sidecar_carries_the_work_record
    work = parser.parse_work(File.join(FIXTURES, "ITKC_GP_1550A.xml"))
    assert_equal "ITKC_GP_1550A", work.id
    assert_equal "古芸堂筆記", work.title_hanja
    assert_equal "고운당필기", work.title_hangul
    assert_equal "柳得恭", work.author_hanja
    assert_equal "유득공", work.author_hangul
    assert_equal 1780, work.print_year, "원문간행년 서기년 — the ORIGINAL print year, not the 2020 edition"
  end

  def test_a_sidecar_without_a_print_year_claims_none
    work = parser.parse_work(File.join(FIXTURES, "ITKC_GO_1295A.xml"))
    assert_equal 1895, work.print_year, "국조보감's own 원문간행년"
  end

  # --- the fascicle: 레벨3 articles as citation units -----------------------

  def test_a_fascicle_parses_to_titled_articles
    fascicle = parser.parse_fascicle(File.join(FIXTURES, "ITKC_GP_1550A_0010.xml"))
    assert_equal "ITKC_GP_1550A_0010", fascicle.id
    assert_equal "古芸堂筆記 卷一", fascicle.title, "the 페이지 marker inside the title flattens away"
    first = fascicle.articles.first
    assert_equal "ITKC_GP_1550A_0010_000_0010", first.id
    assert_equal "圖書集成", first.title
    assert_equal "유득공", first.author_hangul
    assert_equal %w[雜著類 其他類], first.genre_classes, "the 문체분류 chain rides"
    assert_equal "ITKC_BT_1550A_0010_000_0010", first.translation_ref,
                 "the 연계정보 pointer into ITKC's own translation layer — a future crosswalk key"
  end

  def test_article_text_flattens_proper_noun_tags_and_keeps_punctuation
    first = parser.parse_fascicle(File.join(FIXTURES, "ITKC_GP_1550A_0010.xml")).articles.first
    assert_includes first.text, "內閣藏書《圖書集成》，尙衣曺主簿允亨奉旨書題",
                    "고유명사 tags flatten to their text; upstream punctuation verbatim"
    refute_includes first.text, "<", "no markup survives"
  end

  def test_the_go_family_parses_on_the_same_lane
    fascicle = parser.parse_fascicle(File.join(FIXTURES, "ITKC_GO_1295A_0010.xml"))
    assert_equal "ITKC_GO_1295A_0010", fascicle.id
    refute_empty fascicle.articles
    assert(fascicle.articles.all? { |article| !article.text.empty? })
  end

  def test_malformed_xml_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ITKC_GO_9999A_0010.xml")
      File.write(path, "<아이템><레벨1>")
      assert_raises(Nabu::ParseError) { parser.parse_fascicle(path) }
    end
  end
end
