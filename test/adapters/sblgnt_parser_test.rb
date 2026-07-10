# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# SblgntParser (P11-5): the verse-per-line TSV of Faithlife/SBLGNT's
# data/sblgnt/text/*.txt files (test/fixtures/sblgnt). First line = Greek
# book title; then "Book C:V<TAB>verse text" per verse. One verse = one
# passage, urn <doc-urn>:<C>.<V>; the ⸀⸂⸃ apparatus sigla embedded in the
# upstream text are kept verbatim.
class SblgntParserTest < Minitest::Test
  TEXT_DIR = File.join(Nabu::TestSupport.fixtures("sblgnt"), "data", "sblgnt", "text")
  MARK = File.join(TEXT_DIR, "Mark.txt")
  THIRD_JOHN = File.join(TEXT_DIR, "3John.txt")

  def parser
    Nabu::Adapters::SblgntParser.new
  end

  # -- title peek (the discover pass) ------------------------------------------

  def test_title_reads_the_first_line
    assert_equal "ΚΑΤΑ ΜΑΡΚΟΝ", parser.title(MARK)
    assert_equal "ΙΩΑΝΝΟΥ Γ", parser.title(THIRD_JOHN)
  end

  # -- parse --------------------------------------------------------------------

  def test_parse_extracts_one_passage_per_verse_with_chapter_verse_urns
    document = parse_file(MARK, urn: "urn:nabu:sblgnt:mark", title: "ΚΑΤΑ ΜΑΡΚΟΝ")
    assert_equal 57, document.size # Mark 1:1-45 + 2:1-12
    assert_equal "urn:nabu:sblgnt:mark:1.1", document.first.urn
    assert_equal "urn:nabu:sblgnt:mark:2.12", document.to_a.last.urn
  end

  def test_parse_keeps_apparatus_sigla_and_strips_the_trailing_space
    document = parse_file(MARK, urn: "urn:nabu:sblgnt:mark", title: "ΚΑΤΑ ΜΑΡΚΟΝ")
    assert_equal "Ἀρχὴ τοῦ εὐαγγελίου Ἰησοῦ ⸀χριστοῦ.", document.first.text
    mark23 = document.find { |p| p.urn.end_with?(":2.3") }
    assert_includes mark23.text, "παραλυτικὸν"
  end

  def test_parse_carries_the_native_citation_in_annotations
    document = parse_file(MARK, urn: "urn:nabu:sblgnt:mark", title: "ΚΑΤΑ ΜΑΡΚΟΝ")
    assert_equal "Mark 1:1", document.first.annotations["citation"]
  end

  def test_parse_round_trips_a_whole_book
    document = parse_file(THIRD_JOHN, urn: "urn:nabu:sblgnt:3john", title: "ΙΩΑΝΝΟΥ Γ")
    assert_equal 15, document.size
    assert_equal "urn:nabu:sblgnt:3john:1.15", document.to_a.last.urn
    assert_includes document.to_a.last.text, "Εἰρήνη σοι"
  end

  def test_parse_sets_document_identity_and_nfc
    document = parse_file(MARK, urn: "urn:nabu:sblgnt:mark", title: "ΚΑΤΑ ΜΑΡΚΟΝ")
    assert_equal "urn:nabu:sblgnt:mark", document.urn
    assert_equal "grc", document.language
    assert_equal "ΚΑΤΑ ΜΑΡΚΟΝ", document.title
    assert(document.all? { |p| p.text.unicode_normalized?(:nfc) })
  end

  def test_parse_of_a_malformed_line_raises_parse_error_naming_the_line
    Dir.mktmpdir do |dir|
      path = File.join(dir, "Bad.txt")
      File.write(path, "ΤΙΤΛΟΣ\nMark 1:1\tἈρχὴ\nnot a verse line\n")
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: "urn:nabu:sblgnt:bad", language: "grc", title: "x")
      end
      assert_match(/Bad.txt:3/, error.message)
    end
  end

  def test_parse_of_a_title_only_file_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "Empty.txt")
      File.write(path, "ΤΙΤΛΟΣ\n")
      assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: "urn:nabu:sblgnt:empty", language: "grc", title: "x")
      end
    end
  end

  private

  def parse_file(path, urn:, title:)
    parser.parse(path, urn: urn, language: "grc", title: title)
  end
end
