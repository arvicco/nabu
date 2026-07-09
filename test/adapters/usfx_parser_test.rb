# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# UsfxParser (P11-5): streaming parser for one USFX bible file — the eBible.org
# milestone dialect the Clementine Vulgate ships in (test/fixtures/vulgate).
# USFX is MILESTONE markup: `<book id="GEN"><h>Genesis</h>` then `<c id="1"/>`
# chapter milestones and `<v id="1"/>text<ve/>` verse spans; verse text is the
# character data between the milestones. One verse = one passage; the book to
# extract is the caller's choice (the Vulgate adapter mints one document per
# book from one whole-bible file).
class UsfxParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("vulgate"), "lat-clementine.usfx.xml")

  def parser
    Nabu::Adapters::UsfxParser.new
  end

  # -- books (the discover pass) ---------------------------------------------

  def test_books_lists_ids_and_headings_in_file_order
    books = parser.books(FIXTURE)
    assert_equal %w[GEN MRK JHN], books.map(&:id)
    assert_equal %w[Genesis Marcus Joannes], books.map(&:heading)
  end

  # -- parse -------------------------------------------------------------------

  def test_parse_extracts_one_passage_per_verse_with_chapter_verse_urns
    document = parse_book("GEN", urn: "urn:nabu:vulgate:gen", title: "Genesis")
    assert_equal 31, document.size
    assert_equal "urn:nabu:vulgate:gen:1.1", document.first.urn
    assert_equal "urn:nabu:vulgate:gen:1.31", document.to_a.last.urn
    assert_equal "In principio creavit Deus cælum et terram.", document.first.text
  end

  def test_parse_spans_chapter_boundaries
    document = parse_book("MRK", urn: "urn:nabu:vulgate:mrk", title: "Marcus")
    assert_equal 73, document.size # Mark 1 (45 vv) + Mark 2 (28 vv)
    suffixes = document.map { |p| p.urn.delete_prefix("urn:nabu:vulgate:mrk:") }
    assert_includes suffixes, "1.45"
    assert_includes suffixes, "2.1"
    # The alignment-hub anchor verse, verbatim from the fixture.
    mark23 = document.find { |p| p.urn.end_with?(":2.3") }
    assert_equal "Et venerunt ad eum ferentes paralyticum, qui a quatuor portabatur.", mark23.text
  end

  def test_parse_extracts_only_the_requested_book
    document = parse_book("JHN", urn: "urn:nabu:vulgate:jhn", title: "Joannes")
    assert_equal 18, document.size
    assert_equal "In principio erat Verbum, et Verbum erat apud Deum, et Deus erat Verbum.",
                 document.first.text
    assert(document.all? { |p| p.urn.start_with?("urn:nabu:vulgate:jhn:") })
  end

  def test_parse_keeps_upstream_orthography_and_is_nfc
    document = parse_book("GEN", urn: "urn:nabu:vulgate:gen", title: "Genesis")
    verse2 = document.to_a[1]
    # Ligatures and spaced punctuation are upstream reality — kept verbatim.
    assert_includes verse2.text, "tenebræ"
    assert_includes verse2.text, "abyssi :"
    assert(document.all? { |p| p.text.unicode_normalized?(:nfc) })
  end

  def test_parse_sets_document_identity
    document = parse_book("GEN", urn: "urn:nabu:vulgate:gen", title: "Genesis")
    assert_equal "urn:nabu:vulgate:gen", document.urn
    assert_equal "lat", document.language
    assert_equal "Genesis", document.title
    assert_equal FIXTURE, document.canonical_path
  end

  def test_parse_of_an_absent_book_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      parse_book("PSA", urn: "urn:nabu:vulgate:psa", title: "Psalmi")
    end
    assert_match(/PSA/, error.message)
  end

  def test_parse_of_malformed_xml_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.usfx.xml")
      File.write(path, "<usfx><book id=\"GEN\"><v id=\"1\"/>unclosed")
      assert_raises(Nabu::ParseError) do
        parser.parse(path, book: "GEN", urn: "urn:nabu:vulgate:gen", language: "lat", title: "Genesis")
      end
    end
  end

  private

  def parse_book(book, urn:, title:)
    parser.parse(FIXTURE, book: book, urn: urn, language: "lat", title: title)
  end
end
