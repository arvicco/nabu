# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tempfile"

# EpidocParser unit tests against the real Perseus fixtures (P2-2). The four
# editions cover the parser's hard cases: flat single-level line citation
# (Homeric Hymns 13/14), nested chapter/verse citation (2 John), and a
# structural non-citeable div wrapping flat line citation (Ausonius).
class EpidocParserTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/perseus", __dir__)

  HH13_PATH = File.join(FIXTURES, "greekLit/data/tlg0013/tlg013/tlg0013.tlg013.perseus-grc2.xml")
  HH14_PATH = File.join(FIXTURES, "greekLit/data/tlg0013/tlg014/tlg0013.tlg014.perseus-grc2.xml")
  JOHN2_PATH = File.join(FIXTURES, "greekLit/data/tlg0031/tlg024/tlg0031.tlg024.perseus-grc2.xml")
  AUSONIUS_PATH = File.join(FIXTURES, "latinLit/data/stoa0045/stoa013/stoa0045.stoa013.perseus-lat2.xml")

  HH13_URN = "urn:cts:greekLit:tlg0013.tlg013.perseus-grc2"
  HH14_URN = "urn:cts:greekLit:tlg0013.tlg014.perseus-grc2"
  JOHN2_URN = "urn:cts:greekLit:tlg0031.tlg024.perseus-grc2"
  AUSONIUS_URN = "urn:cts:latinLit:stoa0045.stoa013.perseus-lat2"

  def parser
    Nabu::Adapters::EpidocParser.new
  end

  def parse_hh13
    parser.parse(HH13_PATH, urn: HH13_URN, language: "grc", title: "Hymn 13 To Demeter")
  end

  def parse_hh14
    parser.parse(HH14_PATH, urn: HH14_URN, language: "grc", title: "Hymn 14 to the Mother of the Gods")
  end

  def parse_john2
    parser.parse(JOHN2_PATH, urn: JOHN2_URN, language: "grc", title: "2 John")
  end

  def parse_ausonius
    parser.parse(AUSONIUS_PATH, urn: AUSONIUS_URN, language: "lat", title: "Genethliacon ad Ausonium Nepotem")
  end

  # --- HH13: minimal flat line citation ------------------------------------

  def test_hh13_document_fields
    doc = parse_hh13

    assert_equal HH13_URN, doc.urn
    assert_equal "grc", doc.language
    assert_equal "Hymn 13 To Demeter", doc.title
    assert_equal HH13_PATH, doc.canonical_path
  end

  def test_hh13_passages_urns_and_sequence
    doc = parse_hh13

    assert_equal 3, doc.size
    assert_equal ["#{HH13_URN}:1", "#{HH13_URN}:2", "#{HH13_URN}:3"], doc.passages.map(&:urn)
    assert_equal [0, 1, 2], doc.passages.map(&:sequence)
  end

  def test_hh13_text_extraction
    doc = parse_hh13

    assert_includes doc.passages[0].text, "Δημήτηρ"
    # Line 2 has no mixed content: exact match proves whitespace handling
    # (trailing space in the fixture stripped, nothing else touched).
    assert_equal "αὐτὴν καὶ κούρην, περικαλλέα Περσεφόνειαν.", doc.passages[1].text
    doc.passages.each do |passage|
      assert_equal "grc", passage.language
      assert_empty passage.annotations
      refute_match(/\s\s/, passage.text, "whitespace runs must be collapsed")
      assert_equal passage.text, passage.text.strip
    end
  end

  def test_hh13_text_normalized_is_downcased_nfc
    doc = parse_hh13

    doc.passages.each do |passage|
      assert_equal Nabu::Normalize.nfc(passage.text.downcase), passage.text_normalized
    end
    assert_includes doc.passages[0].text_normalized, "δημήτηρ"
  end

  def test_hh13_parses_from_an_open_io
    doc = File.open(HH13_PATH) { |io| parser.parse(io, urn: HH13_URN, language: "grc") }

    assert_equal 3, doc.size
    assert_equal HH13_PATH, doc.canonical_path # picked up from IO#path
  end

  def test_io_without_path_requires_canonical_path
    io = StringIO.new(File.read(HH13_PATH))

    assert_raises(ArgumentError) { parser.parse(io, urn: HH13_URN, language: "grc") }

    io.rewind
    doc = parser.parse(io, urn: HH13_URN, language: "grc", canonical_path: HH13_PATH)

    assert_equal 3, doc.size
  end

  # --- HH14: second document of the same scheme -----------------------------

  def test_hh14_passage_count_matches_the_fixture
    doc = parse_hh14

    # The fixture contains exactly six <l> elements, n="1".."6".
    assert_equal 6, doc.size
    assert_equal (1..6).map { |n| "#{HH14_URN}:#{n}" }, doc.passages.map(&:urn)
    assert_equal (0..5).to_a, doc.passages.map(&:sequence)
    assert_includes doc.passages[1].text, "Μοῦσα λίγεια"
  end

  # --- 2 John: two-level chapter/verse citation ------------------------------

  def test_2john_two_level_citation
    doc = parse_john2

    assert_equal 13, doc.size
    assert_equal (1..13).map { |n| "#{JOHN2_URN}:1.#{n}" }, doc.passages.map(&:urn)
    assert_equal (0..12).to_a, doc.passages.map(&:sequence)
  end

  def test_2john_text_extraction_collapses_internal_whitespace
    doc = parse_john2
    first = doc.passages.first

    # The verse text spans multiple physical lines in the fixture; internal
    # runs must collapse to single spaces and the <milestone unit="para"/> at
    # the start must not leave leading whitespace.
    assert first.text.start_with?("Ο ΠΡΕΣΒΥΤΕΡΟΣ")
    assert_includes first.text, "καὶ τοῖς τέκνοις αὐτῆς, οὓς ἐγὼ ἀγαπῶ ἐν ἀληθείᾳ"
    refute_match(/\s\s/, first.text)

    verse7 = doc.passages.find { |p| p.urn.end_with?(":1.7") }

    assert_includes verse7.text, "ἀντίχριστος"
  end

  # --- Ausonius: flat line citation despite a structural section div --------

  def test_ausonius_lines_are_cited_flat_ignoring_the_section_div
    doc = parse_ausonius

    assert_equal 28, doc.size
    # The div[@subtype="section" n="21"] is structural, NOT a citation level:
    # per the refsDecl, lines are cited by @n alone (":1", not ":21.1").
    assert_equal (1..28).map { |n| "#{AUSONIUS_URN}:#{n}" }, doc.passages.map(&:urn)
    assert_equal "carmina prima tibi eum iam puerilibus annis", doc.passages.first.text
    assert_equal "lat", doc.language
    assert(doc.passages.all? { |p| p.language == "lat" })
  end

  # --- Editorial noise --------------------------------------------------------

  def test_note_subtrees_are_dropped_from_passage_text
    # No fixture carries a <note> inside a citation unit, so exercise the
    # dropping rule by string-surgery on a fixture copy (never a hand-written
    # fixture file).
    xml = File.read(HH13_PATH)
              .sub("κούρην,", "κούρην,<note>editorial <bibl>noise</bibl></note>")

    with_tempfile(xml) do |path|
      doc = parser.parse(path, urn: HH13_URN, language: "grc")

      assert_equal "αὐτὴν καὶ κούρην, περικαλλέα Περσεφόνειαν.", doc.passages[1].text
      refute_includes doc.passages[1].text, "noise"
    end
  end

  # --- NFC, belt and braces across all four fixtures -------------------------

  def test_every_passage_of_every_fixture_is_nfc_and_non_empty
    [parse_hh13, parse_hh14, parse_john2, parse_ausonius].each do |doc|
      refute_empty doc.passages
      doc.passages.each do |passage|
        refute_empty passage.text
        assert passage.text.unicode_normalized?(:nfc), "#{passage.urn} text is not NFC"
        assert passage.text_normalized.unicode_normalized?(:nfc), "#{passage.urn} text_normalized is not NFC"
      end
    end
  end

  # --- Error cases -----------------------------------------------------------

  def test_urn_mismatch_raises_parse_error_naming_the_file
    wrong_urn = "urn:cts:greekLit:tlg9999.tlg999.perseus-grc2"
    error = assert_raises(Nabu::ParseError) do
      parser.parse(HH13_PATH, urn: wrong_urn, language: "grc")
    end

    assert_includes error.message, File.basename(HH13_PATH)
    assert_includes error.message, wrong_urn
    assert_includes error.message, HH13_URN # the urn actually found in div[@type="edition"]/@n
  end

  def test_missing_refsdecl_raises_parse_error
    # String-surgery on a fixture copy (never a hand-written fixture file):
    # strip every refsDecl block from the header.
    xml = File.read(HH13_PATH).gsub(%r{<refsDecl.*?</refsDecl>}m, "")

    refute_includes xml, "cRefPattern" # surgery sanity check

    with_tempfile(xml) do |path|
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: HH13_URN, language: "grc")
      end

      assert_includes error.message, File.basename(path)
      assert_match(/cRefPattern|refsDecl/, error.message)
    end
  end

  def test_malformed_xml_raises_parse_error
    xml = File.read(HH13_PATH)
    truncated = xml[0, xml.index("<l n=\"2\"")] # cut mid-document: unclosed elements

    with_tempfile(truncated) do |path|
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: HH13_URN, language: "grc")
      end

      assert_includes error.message, File.basename(path)
      assert_match(/malformed XML/i, error.message)
    end
  end

  def test_document_with_zero_citable_units_raises_parse_error
    # Remove every <l> element: structurally valid TEI, but nothing citable.
    xml = File.read(HH13_PATH).gsub(%r{<l n="\d+">.*?</l>}m, "")

    with_tempfile(xml) do |path|
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: HH13_URN, language: "grc")
      end

      assert_includes error.message, File.basename(path)
      assert_match(/no citable passages/i, error.message)
    end
  end

  # --- Streaming proof --------------------------------------------------------

  def test_implementation_streams_and_never_builds_a_full_document_dom
    # Perseus has >5 MB editions; the parser must go through
    # Nokogiri::XML::Reader, never a whole-document DOM. Runtime spying would
    # contort the design (packet spec), so this asserts on code structure: the
    # implementation contains no full-document parse entry point.
    source = File.read(File.expand_path("../../lib/nabu/adapters/epidoc_parser.rb", __dir__))

    refute_match(/Nokogiri::XML(\.parse)?\s*\(/, source, "must not DOM-parse the document")
    refute_match(/Nokogiri::XML::Document/, source, "must not build a full XML document")
    assert_match(/Nokogiri::XML::Reader/, source, "must stream via Nokogiri::XML::Reader")
  end

  private

  def with_tempfile(content)
    Tempfile.create(["epidoc", ".xml"]) do |file|
      file.write(content)
      file.flush
      yield file.path
    end
  end
end
