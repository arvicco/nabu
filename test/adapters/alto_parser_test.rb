# frozen_string_literal: true

require "test_helper"
require "nabu/adapters/alto_parser"

# Nabu::Adapters::AltoParser — eScriptorium's ALTO v4 export, read from
# real OpenITI MAKHZAN pages (test/fixtures/makhzan/README.md).
class AltoParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("makhzan")

  def page(rel) = Nabu::Adapters::AltoParser.parse(File.binread(File.join(FIXTURES, rel)), label: rel)

  def test_lines_in_document_order_with_their_page_ordinals
    leiden = page("Doc102/102_14122.xml")
    assert_equal 19, leiden.lines.size
    first = leiden.lines.first
    assert_equal 1, first.ordinal
    assert_equal "eSc_line_f9be8fc5", first.id
    assert_equal "وكيمني اهل كشف ايلدي ، وكيمي مجذب وسالك ، وكيمني سالك", first.text
    assert_equal (1..19).to_a, leiden.lines.map(&:ordinal)
  end

  def test_page_language_image_and_the_exports_metadata_tags
    majmua = page("Doc3178/3178_748159.xml")
    assert_equal "mul", majmua.language
    assert_equal "3178_748159.png", majmua.file_name
    assert_equal "ara,ota,fas", majmua.tags["Language"]
    assert_equal "Or. 1094", majmua.tags["Call No"]
    assert_equal "naskh_varied", majmua.tags["Script"]
    refute majmua.tags.key?("Vetting"), "an empty OtherTag carries no value"
  end

  def test_block_types_resolve_through_tagrefs
    bustan = page("Doc3262/3262_759523.xml")
    assert_equal "eSc_textblock_9eb51434", bustan.lines.first.block_id
    assert_equal "ota", bustan.language
  end

  def test_an_empty_line_keeps_its_ordinal_with_blank_text
    xml = <<~XML
      <alto xmlns="http://www.loc.gov/standards/alto/ns-v4#"><Tags><OtherTag ID="BT2" LABEL="Main"/></Tags>
      <Layout><Page LANG="ota"><PrintSpace><TextBlock ID="b" TAGREFS="BT2">
      <TextLine ID="l1"/><TextLine ID="l2"><String CONTENT="  بر  "/><SP/><String CONTENT="ايكي"/></TextLine>
      </TextBlock></PrintSpace></Page></Layout></alto>
    XML
    lines = Nabu::Adapters::AltoParser.parse(xml, label: "inline").lines
    assert_equal ["", "بر ايكي"], lines.map(&:text)
    assert_equal [1, 2], lines.map(&:ordinal)
    assert_equal %w[Main Main], lines.map(&:block_type)
  end

  def test_malformed_xml_is_a_parse_error
    assert_raises(Nabu::ParseError) { Nabu::Adapters::AltoParser.parse("<alto><Layout>", label: "broken") }
  end
end
