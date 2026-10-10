# frozen_string_literal: true

require "test_helper"

module Adapters
  # The `page-xml` parser family (P116-1): PAGE 2013 (PcGts) ground-truth
  # pages as Transkribus exports them — regions in the page's ReadingOrder,
  # lines in their own readingOrder index, the line-level TextEquiv as the
  # text, and the Transkribus `custom` tag language (abbrev / unclear /
  # textStyle) as offset-addressed spans. Pinned against three real pages
  # of the Prague Bible 1488 GT (test/fixtures/prague-bible-1488/page/).
  class PageXmlParserTest < Minitest::Test
    FIXTURES = File.join(Nabu::TestSupport.fixtures("prague-bible-1488"), "page")

    def parse(name) = Nabu::Adapters::PageXmlParser.new.parse(File.join(FIXTURES, name))

    def test_page_metadata_comes_from_the_transkribus_header
      page = parse("0023_DTL_547662-0024.xml")
      assert_equal 23, page.page_nr
      assert_equal "GT", page.status
      assert_equal "0023_DTL_547662-0024.jpeg", page.image_filename
      assert_equal "5363448", page.doc_id
    end

    def test_regions_follow_the_reading_order_and_lines_their_own_index
      page = parse("0023_DTL_547662-0024.xml")
      assert_equal %w[tr_1 r], page.regions.map(&:id)
      first = page.regions.first.lines.first
      assert_equal 0, first.index
      assert_equal "Prwnie knihy", first.text
      assert_equal "ſtawil ho w ragi rozkoſſij · aby dielal a", page.regions.first.lines[1].text
      assert_equal([48, 46], page.regions.map { |region| region.lines.size })
    end

    def test_the_region_level_text_equiv_is_never_read_as_a_line
      # The export's region-level TextEquiv is EMPTY (<Unicode></Unicode>
      # after the last line of every region) — only line TextEquivs count.
      page = parse("0501_DTL_547662-0502.xml")
      assert_equal([1, 47, 47], page.regions.map { |region| region.lines.size })
      assert(page.regions.flat_map(&:lines).none? { |line| line.text.empty? })
      assert_equal "Knihy", page.regions.first.lines.first.text
    end

    def test_region_type_rides_when_the_structure_tag_is_present
      page = parse("0217_DTL_547662-0218.xml")
      assert_equal %w[paragraph paragraph], page.regions.map(&:type)
      assert_nil parse("0023_DTL_547662-0024.xml").regions.first.type
    end

    def test_abbrev_spans_carry_offset_length_form_and_expansion
      page = parse("0217_DTL_547662-0218.xml")
      line = page.regions.first.lines.find { |l| l.id == "region_1734259517264_16_tl_23" }
      abbrev = line.spans.find { |span| span.tag == "abbrev" }
      assert_equal 5, abbrev.offset
      assert_equal 11, abbrev.length
      assert_equal "Izrahelſkemu", abbrev.attributes["expansion"]
      assert_equal line.text[5, 11], abbrev.form
      style = line.spans.find { |span| span.tag == "textStyle" }
      assert_equal "true", style.attributes["superscript"]
    end

    def test_unclear_spans_have_no_attributes_beyond_the_range
      page = parse("0217_DTL_547662-0218.xml")
      unclear = page.regions.flat_map(&:lines).flat_map(&:spans).select { |span| span.tag == "unclear" }
      refute_empty unclear
      assert(unclear.all? { |span| span.attributes.empty? && !span.form.empty? })
    end

    def test_reading_order_is_not_a_span
      page = parse("0501_DTL_547662-0502.xml")
      assert(page.regions.flat_map(&:lines).flat_map(&:spans).none? { |s| s.tag == "readingOrder" })
    end

    def test_custom_attribute_grammar
      tags = Nabu::Adapters::PageXmlParser.custom_tags(
        "readingOrder {index:13;} abbrev {offset:0; length:7; continued:true;expansion:buduczieho;} " \
        "textStyle {offset:6; length:1;superscript:true;}"
      )
      assert_equal [["readingOrder", { "index" => "13" }],
                    ["abbrev", { "offset" => "0", "length" => "7", "continued" => "true",
                                 "expansion" => "buduczieho" }],
                    ["textStyle", { "offset" => "6", "length" => "1", "superscript" => "true" }]], tags
    end

    def test_malformed_xml_raises_parse_error
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bad.xml")
        File.write(path, "<PcGts><Page>")
        assert_raises(Nabu::ParseError) { Nabu::Adapters::PageXmlParser.new.parse(path) }
      end
    end

    def test_a_file_without_a_page_element_raises_parse_error
      Dir.mktmpdir do |dir|
        path = File.join(dir, "mets.xml")
        File.write(path, "<?xml version=\"1.0\"?><mets/>")
        assert_raises(Nabu::ParseError) { Nabu::Adapters::PageXmlParser.new.parse(path) }
      end
    end
  end
end
