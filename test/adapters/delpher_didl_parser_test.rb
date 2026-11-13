# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # The delpher-didl family over real 16xx issues (test/fixtures/
  # delpher-newspapers/README.md): the DIDL's catalogue record, pages and
  # article table, and the articletext files.
  class DelpherDidlParserTest < Minitest::Test
    ZIP = File.join(Nabu::TestSupport.fixtures("delpher-newspapers"), "kranten_pd_16xx")
    COURANTE = File.join(ZIP, "1618/06/14/DDD_ddd_010500649_mpeg21")
    MMKB = File.join(ZIP, "1631/09/19/KRANTEN_MMKB08_MMKB08_000213603_mpeg21")
    HAERLEM = File.join(ZIP, "1685/12/22/DDD_ddd_011225333_mpeg21")

    def parser = Nabu::Adapters::DelpherDidlParser.new

    def test_the_issue_record
      issue = parser.read(File.join(COURANTE, "didl.xml"))
      assert_equal "ddd:010500649:mpeg21", issue.record_id
      fields = issue.fields
      assert_equal "Courante uyt Italien, Duytslandt, &c.", fields["paper"]
      assert_equal "1618-06-14", fields["date"]
      assert_equal "Amsterdam", fields["place"], "the dcx:creation spatial is the place of publication"
      assert_equal "Landelijk", fields["distribution"], "the untyped spatial is the distribution scope"
      assert_equal "Caspar van Hilten", fields["publisher"]
      assert_equal ["nl"], fields["languages"]
      assert_equal "830620397", fields["ppn"]
      assert_equal "National Library of Sweden KBS", fields["holding"]
      assert_equal "161X-", fields["title_run"]
    end

    def test_language_codes_are_downcased_and_alternative_titles_collected
      fields = parser.read(File.join(MMKB, "didl.xml")).fields
      assert_equal ["nl"], fields["languages"], "the MMKB08 record writes NL"
      assert_equal ["Ook bekend als Courante uyt Italien en(de) Duytsch-landt, &c.",
                    "Courante uyt Italien en(de) Duytsch-landt, &c."], fields["alternative_titles"]
      assert_nil fields["issue_number"]
    end

    def test_pages_carry_their_ocr_confidence
      assert_equal [1.0], parser.read(File.join(COURANTE, "didl.xml")).pages.map(&:ocr_confidence)
      pages = parser.read(File.join(HAERLEM, "didl.xml")).pages
      assert_equal [1, 2], pages.map(&:number)
      assert_equal [0.673, 0.677], pages.map(&:ocr_confidence)
    end

    def test_articles_are_read_once_in_order_with_file_subject_and_pages
      articles = parser.read(File.join(HAERLEM, "didl.xml")).articles
      assert_equal (1..8).map { |n| format("%04d", n) }, articles.map(&:number),
                   "the page Items repeat articles as nested Items — read once"
      runner = articles[3]
      assert_equal "DDD_011225333_0004_articletext.xml", runner.file
      assert_equal [1, 2], runner.pages, "a0004 runs over both pages"
      assert_equal "advertentie", articles.last.subject
      assert_equal "Advertentie", articles.last.title
    end

    def test_articletext_title_and_paragraphs
      text = parser.read_article(File.join(COURANTE, "DDD_010500649_0001_articletext.xml"))
      assert_equal "VVt Venetien den 1.Iunij, Anno 1618.", text.title
      assert_equal 1, text.paragraphs.size
      assert text.paragraphs.first.start_with?("VVt Venetien den 1. Iunij, Anno 1618. DEn 25. Passato")
      assert_nil parser.read_article(File.join(HAERLEM, "DDD_011225333_0008_articletext.xml")).title
    end

    def test_malformed_files_raise_parse_errors
      Dir.mktmpdir do |dir|
        bad = File.join(dir, "didl.xml")
        File.write(bad, "<didl:DIDL xmlns:didl='urn:mpeg:mpeg21:2002:02-DIDL-NS'><didl:Item>")
        assert_raises(Nabu::ParseError) { parser.read(bad) }
        File.write(bad, "<other/>")
        assert_raises(Nabu::ParseError) { parser.read_article(bad) }
      end
    end
  end
end
