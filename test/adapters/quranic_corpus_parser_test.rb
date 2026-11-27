# frozen_string_literal: true

require "test_helper"

# The quranic-corpus-tsv family against real lines of the trimmed fixture
# (the Quranic Arabic Corpus morphology v0.4: LOCATION FORM TAG FEATURES,
# one row per segment, Buckwalter ASCII, CRLF).
class QuranicCorpusParserTest < Minitest::Test
  FILE = File.join(Nabu::TestSupport.fixtures("quranic-corpus"), "quranic-corpus-morphology-0.4.txt")

  def parser = Nabu::Adapters::QuranicCorpusParser.new

  def lines = @lines ||= File.binread(FILE).force_encoding(Encoding::UTF_8).lines

  def rows(prefix) = lines.select { |line| line.start_with?("(#{prefix}") }

  def segments(prefix) = rows(prefix).map { |line| parser.segment(line, label: "fixture") }

  def test_the_preamble_is_the_two_notices_and_the_column_header
    preamble = lines.take_while { |line| !parser.row?(line) }
    assert_equal 57, preamble.size
    assert_nil parser.check_preamble!(preamble, label: "fixture")
    assert_equal "LOCATION\tFORM\tTAG\tFEATURES\r\n", preamble.last
  end

  def test_a_preamble_without_the_notice_or_header_fails_loudly
    preamble = lines.take_while { |line| !parser.row?(line) }
    no_notice = preamble.reject { |line| line.include?("Quranic Arabic Corpus (morphology, version 0.4)") }
    assert_match(/notice/, assert_raises(Nabu::ParseError) { parser.check_preamble!(no_notice, label: "f") }.message)
    drifted = preamble[0..-2] + ["LOCATION\tFORM\tTAG\r\n"]
    assert_match(/header/, assert_raises(Nabu::ParseError) { parser.check_preamble!(drifted, label: "f") }.message)
    stray = preamble[0..-2] + ["not a comment\r\n", preamble.last]
    assert_match(/preamble/, assert_raises(Nabu::ParseError) { parser.check_preamble!(stray, label: "f") }.message)
  end

  def test_a_row_decodes_location_and_keeps_the_strings_verbatim
    segment = parser.segment("(1:1:3:2)\tr~aHoma`ni\tADJ\tSTEM|POS:ADJ|LEM:r~aHoma`n|ROOT:rHm|MS|GEN\r\n",
                             label: "fixture")
    assert_equal [1, 1, 3, 2], [segment.sura, segment.verse, segment.word, segment.segment]
    assert_equal({ "id" => "1:1:3:2", "form" => "r~aHoma`ni", "tag" => "ADJ",
                   "features" => "STEM|POS:ADJ|LEM:r~aHoma`n|ROOT:rHm|MS|GEN",
                   "lemma" => "r~aHoma`n", "root" => "rHm" }, segment.token)
  end

  def test_a_prefix_carries_no_lemma_or_root
    token = segments("1:1:1:1").first.token
    assert_equal({ "id" => "1:1:1:1", "form" => "bi", "tag" => "P", "features" => "PREFIX|bi+" }, token)
  end

  # (109:6:4:2) — upstream's empty FORM for the elided 1S suffix pronoun:
  # the segment stays a token (form ""), contributing nothing to the text.
  def test_an_empty_form_segment_is_kept_as_a_token
    token = segments("109:6:4:2").first.token
    assert_equal({ "id" => "109:6:4:2", "form" => "", "tag" => "PRON", "features" => "SUFFIX|PRON:1S" }, token)
  end

  def test_verse_text_joins_segments_into_words_and_words_with_spaces
    assert_equal "bisomi {ll~ahi {lr~aHoma`ni {lr~aHiymi", parser.verse_text(segments("1:1:"))
    assert_equal "lakumo diynukumo waliYa diyni", parser.verse_text(segments("109:6:"))
    assert_equal "walamo yakun l~ahu, kufuwFA >aHadN[", parser.verse_text(segments("112:4:")),
                 "the extended-Buckwalter marks (, and [) stay verbatim"
  end

  def test_malformed_rows_are_parse_errors
    [
      "(1:1:1)\tbi\tP\tPREFIX|bi+\r\n",
      "(1:1:1:1)\tbi\tP\r\n",
      "(1:1:1:1)\tbi\tP\tPREFIX|bi+\textra\r\n",
      "(0:1:1:1)\tbi\tP\tPREFIX|bi+\r\n"
    ].each do |line|
      assert_raises(Nabu::ParseError, line) { parser.segment(line, label: "fixture") }
    end
  end

  def test_sura_of_reads_the_location_only
    assert_equal 112, parser.sura_of(rows("112:1:1:1").first, label: "fixture")
  end
end
