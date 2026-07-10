# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# AsprParser (P12-2): streaming parser for the single OTA 3009 TEI file
# holding the complete Anglo-Saxon Poetic Records (test/fixtures/aspr). The
# file is flat `<div rend="linenumber" xml:id="A4.1">` poem divs — the xml:id
# is the canonical Cameron number — each `<head>` + optional `<bibl>` + flat
# `<l>` verse lines with `<caesura/>` mid-line markers. One line = one
# passage, cited by 1-based ordinal (which equals the printed ASPR line
# number: Beowulf's div carries exactly 3,182 `<l>`); the div to extract is
# the caller's choice (the Aspr adapter mints one document per poem — the
# Vulgate single-file-many-docs pattern).
class AsprParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("aspr"), "3009.xml")

  DIV_IDS = %w[A3.34.15 A3.34.22 A4.1 A16 A32.1 A32.2 A43.5 A43.10].freeze

  def parser
    Nabu::Adapters::AsprParser.new
  end

  # -- texts (the discover pass) ---------------------------------------------

  def test_texts_lists_div_ids_and_titles_in_file_order
    texts = parser.texts(FIXTURE)
    assert_equal DIV_IDS, texts.map(&:id)
    assert_equal "Beowulf", texts.find { |t| t.id == "A4.1" }.title
    assert_equal "Cædmon's Hymn, Northumbrian Version", texts.find { |t| t.id == "A32.1" }.title
  end

  def test_texts_keeps_both_titles_of_the_collision_pair
    texts = parser.texts(FIXTURE)
    pair = texts.select { |t| t.title == "For Loss of Cattle" }
    assert_equal %w[A43.5 A43.10], pair.map(&:id),
                 "identical <head> titles must map to distinct Cameron ids (why title-slugs were rejected)"
  end

  # -- parse -------------------------------------------------------------------

  def test_parse_extracts_one_passage_per_line_with_ordinal_urns
    document = parse_div("A4.1", urn: "urn:nabu:aspr:A4.1", title: "Beowulf")
    assert_equal 24, document.size
    assert_equal "urn:nabu:aspr:A4.1:1", document.first.urn
    assert_equal "urn:nabu:aspr:A4.1:24", document.to_a.last.urn
    assert_equal "Hwæt! We Gardena in geardagum,", document.first.text
    assert_equal "leode gelæsten; lofdædum sceal", document.to_a.last.text
    assert_equal (0..23).to_a, document.map(&:sequence)
  end

  def test_parse_keeps_unclear_text_inline
    document = parse_div("A4.1", urn: "urn:nabu:aspr:A4.1", title: "Beowulf")
    line4 = document.find { |p| p.urn.end_with?(":4") }
    assert_equal "Oft Scyld Scefing sceaþena þreatum,", line4.text,
                 "<unclear> spans are reading text and stay inline"
  end

  def test_parse_extracts_only_the_requested_div
    document = parse_div("A32.1", urn: "urn:nabu:aspr:A32.1", title: "Cædmon's Hymn, Northumbrian Version")
    assert_equal 9, document.size
    assert_equal "Nu scylun hergan hefaenricaes uard,", document.first.text
    assert(document.all? { |p| p.urn.start_with?("urn:nabu:aspr:A32.1:") })
  end

  def test_parse_distinguishes_the_dialect_witnesses
    northumbrian = parse_div("A32.1", urn: "urn:nabu:aspr:A32.1", title: "Cædmon's Hymn, Northumbrian Version")
    west_saxon = parse_div("A32.2", urn: "urn:nabu:aspr:A32.2", title: "Cædmon's Hymn, West-Saxon Version")
    assert_equal "Nu scylun hergan hefaenricaes uard,", northumbrian.first.text
    assert_equal "Nu sculon herigean heofonrices weard,", west_saxon.first.text
  end

  def test_parse_keeps_rune_and_glyph_text_inline
    riddle = parse_div("A3.34.15", urn: "urn:nabu:aspr:A3.34.15", title: "Riddles 75")
    assert_equal 2, riddle.size
    assert_equal "D N L H.", riddle.to_a.last.text, "<foreign xml:lang=\"rune\"> text is kept"

    proverb = parse_div("A16", urn: "urn:nabu:aspr:A16", title: "A Proverb from Winfrid's Time")
    assert_equal "Oft daedlata domę foręldit,", proverb.first.text,
                 "<g> glyph text joins its host word with no space injected"
  end

  def test_parse_ignores_div_level_gap_without_shifting_ordinals
    document = parse_div("A3.34.22", urn: "urn:nabu:aspr:A3.34.22", title: "Riddles 82")
    assert_equal 5, document.size, "the div-level <gap/> between lines is not a line"
    assert_equal ["Wiht is", "gongende, greate swilgeð,", "fell ne flæsc, fotum gong/",
                  "/eð,", "sceal mæla gehwam"], document.map(&:text)
  end

  def test_parse_never_leaks_head_or_bibl_into_passages
    document = parse_div("A4.1", urn: "urn:nabu:aspr:A4.1", title: "Beowulf")
    document.each do |passage|
      # Probe with tokens only <head>/<bibl> could contribute — NOT the word
      # "Beowulf", which the poem itself legitimately reads at line 18.
      refute_match(/Dobbie|ASPR|New York/, passage.text,
                   "head/bibl metadata leaked into passage #{passage.urn}")
    end
  end

  def test_parse_output_is_nfc
    document = parse_div("A43.5", urn: "urn:nabu:aspr:A43.5", title: "For Loss of Cattle")
    document.each { |p| assert p.text.unicode_normalized?(:nfc) }
  end

  def test_parse_is_stable_across_two_passes
    first = parse_div("A4.1", urn: "urn:nabu:aspr:A4.1", title: "Beowulf")
    second = parse_div("A4.1", urn: "urn:nabu:aspr:A4.1", title: "Beowulf")
    assert_equal first.map(&:urn), second.map(&:urn)
    assert_equal first.map(&:text), second.map(&:text)
  end

  # -- damage ------------------------------------------------------------------

  def test_parse_raises_parse_error_for_an_absent_div
    error = assert_raises(Nabu::ParseError) do
      parse_div("A99.9", urn: "urn:nabu:aspr:A99.9", title: "No Such Poem")
    end
    assert_match(/A99\.9/, error.message)
  end

  def test_parse_raises_parse_error_on_malformed_xml
    Dir.mktmpdir do |dir|
      path = File.join(dir, "3009.xml")
      File.write(path, "<TEI><text><body><div rend=\"linenumber\" xml:id=\"A1\"><l>oops")
      assert_raises(Nabu::ParseError) do
        parser.parse(path, div_id: "A1", urn: "urn:nabu:aspr:A1", language: "ang", title: "Oops")
      end
    end
  end

  private

  def parse_div(div_id, urn:, title:)
    parser.parse(FIXTURE, div_id: div_id, urn: urn, language: "ang", title: title)
  end
end
