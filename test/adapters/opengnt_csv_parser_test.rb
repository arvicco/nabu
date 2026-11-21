# frozen_string_literal: true

require "test_helper"

# The opengnt-csv family against real rows of the trimmed fixture CSV.
class OpengntCsvParserTest < Minitest::Test
  CSV_PATH = File.join(Nabu::TestSupport.fixtures("opengnt"), "OpenGNT_version3_3.csv")

  def parser = Nabu::Adapters::OpengntCsvParser.new

  def lines = File.readlines(CSV_PATH)

  def test_the_real_header_is_the_pinned_header
    assert_nil parser.check_header!(lines.first, label: "fixture")
  end

  def test_a_drifted_header_fails_loudly
    drifted = lines.first.sub("OTquotation\t", "")
    error = assert_raises(Nabu::ParseError) { parser.check_header!(drifted, label: "fixture") }
    assert_match(/header drift/, error.message)
  end

  def test_book_number_reads_the_verse_ref_column
    assert_equal 40, parser.book_number(lines[1], label: "fixture")
  end

  def test_words_decode_kept_columns_and_drop_empty_ones
    word = parser.words(lines[1], label: "fixture").first
    assert_equal [40, 1, 1], [word.book, word.chapter, word.verse]
    assert_equal({ "id" => "000001", "form" => "Βίβλος", "lemma" => "βίβλος", "rmac" => "N-NSF",
                   "strong" => "G976", "ln" => "LN-33.38" }, word.token)
  end

  def test_verse_text_attaches_punctuation_and_drops_layout_marks
    verse = lines.select { |l| l.include?("〔41｜1｜3〕") }.join
    text = parser.verse_text(parser.words(verse, label: "fixture"))
    assert_equal "Φωνὴ βοῶντος ἐν τῇ ἐρήμῳ· Ἑτοιμάσατε τὴν ὁδὸν Κυρίου, εὐθείας ποιεῖτε τὰς τρίβους αὐτοῦ,",
                 Nabu::Normalize.nfc(text)
  end

  def test_a_short_packed_column_is_a_parse_error
    broken = lines[1].sub("〔βιβλοϲ｜", "〔")
    error = assert_raises(Nabu::ParseError) { parser.words(broken, label: "fixture") }
    assert_match(/sub-columns/, error.message)
  end

  def test_a_row_with_a_missing_column_is_a_parse_error
    broken = lines[1].split("\t").drop(1).join("\t")
    assert_raises(Nabu::ParseError) { parser.words(broken, label: "fixture") }
  end
end
