# frozen_string_literal: true

require "test_helper"

# The ntvmr-tei parser family against the real NTVMR transcript/get answers
# in test/fixtures/ntvmr/transcripts/ (retrieved 2026-11-23, README there):
# 10052 = P52 (pageID=ALL, two folios, part="F"/"I" fragments at the page
# edges, supplied source="na28"), 20189 = 0189 (pageID=ALL, two pages, a
# verse and a word split across the page break, nomina sacra, punctuation),
# 20001 = 01 Sinaiticus cut to Philemon (indexContent=Phlm — OSIS ab n, four
# correcting hands in app/rdg).
class NtvmrTeiParserTest < Minitest::Test
  PARSER = Nabu::Adapters::NtvmrTeiParser
  DIR = File.expand_path("../fixtures/ntvmr/transcripts", __dir__)

  def parse(doc_id) = PARSER.parse(File.read(File.join(DIR, "#{doc_id}.xml")), label: doc_id)

  def verse(doc_id, tail) = parse(doc_id).verses.find { |v| v.urn_tail == tail } || flunk("no #{tail} in #{doc_id}")

  def test_the_header_mines_the_holding_hands_and_the_cc_by_statement
    header = parse("20001").header
    assert_equal "01", header.ga
    assert_equal ["United Kingdom", "London", "British Library", "Add. 43725"],
                 [header.country, header.settlement, header.repository, header.idno]
    assert_equal %w[firsthand corrector2 corrector2a corrector2b], header.hands
    assert_equal "This work is licensed under a Creative Commons Attribution 4.0 Unported License",
                 header.license_statement
    assert_equal "https://creativecommons.org/licenses/by/4.0/", header.license_url
    assert_equal "(C) 2026 Institut für Neutestamentliche Textforschung.", header.copyright
    assert_equal "grc", header.language
  end

  def test_p52_verses_read_restorations_through_and_keep_the_extant_reading
    result = parse("10052")
    assert_equal %w[john.18.31 john.18.32 john.18.33 john.18.37 john.18.38], result.verses.map(&:urn_tail)
    v31 = result.verses.first
    assert_equal "οι ιουδαιοι ημειν ουκ εξεστιν αποκτειναι ουδενα", v31.text
    assert_equal "οι ιουδαι[…]ι ημε[…] ουδενα", v31.annotations["extant"],
                 "every supplied stretch collapses to one […], across word boundaries"
    assert_equal({ "supplied_chars" => 23, "unclear_chars" => 2 }, v31.annotations["leiden"])
    assert_equal ["001r"], v31.annotations["pages"]
    assert_equal "JOHN 18.31", v31.citation
  end

  def test_tokens_carry_the_hub_citation_and_only_non_default_marks
    tokens = verse("10052", "john.18.31").annotations["tokens"]
    assert_equal({ "form" => "οι", "citation_part" => "JOHN 18.31" }, tokens.first)
    assert_equal({ "form" => "ιουδαιοι", "citation_part" => "JOHN 18.31", "supplied" => "partial", "unclear" => 1 },
                 tokens[1])
    assert_equal({ "form" => "ουκ", "citation_part" => "JOHN 18.31", "supplied" => "word" }, tokens[3])
    assert_equal 7, tokens.size
  end

  def test_a_verse_split_by_the_page_break_merges_and_joins_its_split_word
    v12 = verse("20189", "acts.5.12")
    assert_equal 2, v12.annotations["parts"]
    assert_equal %w[15 16], v12.annotations["pages"]
    assert_includes v12.text, "και ησαν ομοθυμαδον παντες",
                    "w part=I (ομοθυμα) + w part=F (δον) across the page are one word"
  end

  def test_nomina_sacra_stay_as_written_and_punctuation_attaches
    v3 = verse("20189", "acts.5.3")
    assert_includes v3.text, "σε το πνα το αγιον· και", "the contracted πνα, the overline dropped; · as written"
    token = v3.annotations["tokens"].find { |t| t["form"] == "πνα" }
    assert_equal "nomen-sacrum", token["abbreviation"]
    assert_equal "partial", token["supplied"], "the α is supplied from NA28 inside the abbreviation"
  end

  def test_osis_keys_read_and_corrections_keep_the_first_hand
    result = parse("20001")
    assert_equal 25, result.verses.size
    assert_equal "phlm.1.1", result.verses.first.urn_tail
    assert_equal "PHILEM 1.1", result.verses.first.citation
    v6 = verse("20001", "phlm.1.6")
    assert_includes v6.text, "οπως η κοινωνια της", "the first hand's κοινωνια stands in the text"
    assert_equal [{ "readings" => [{ "hand" => "firsthand", "type" => "orig", "reading" => "κοινωνια" },
                                   { "hand" => "corrector2", "type" => "corr", "reading" => "διακονια" }] },
                  { "readings" => [{ "hand" => "firsthand", "type" => "orig", "reading" => "" },
                                   { "hand" => "corrector2", "type" => "corr", "reading" => "ιν" }] }],
                 v6.annotations["corrections"]
    assert(v6.annotations["tokens"].find { |t| t["form"] == "κοινωνια" }["corrected"])
  end

  def test_an_ab_without_a_verse_key_falls_back_to_the_page_grain
    xml = File.read(File.join(DIR, "10052.xml")).gsub(/ n="B04K18V3[12]"/, "")
    result = PARSER.parse(xml, label: "keyless")
    assert_equal %w[p001r john.18.33 john.18.37 john.18.38], result.verses.map(&:urn_tail)
    page = result.verses.first
    assert_nil page.key
    assert_equal "001r", page.annotations["page"]
    assert page.text.start_with?("οι ιουδαιοι ημειν"), "both keyless verses of folio 1r join its page passage"
    refute(page.annotations["tokens"].any? { |t| t.key?("citation_part") })
    assert_equal 1, result.page_passages
  end

  def test_an_error_answer_is_not_a_transcription
    error = assert_raises(Nabu::ParseError) { parse("20059") }
    assert_match(/error answer/, error.message)
  end

  def test_a_document_without_a_tei_header_raises_parse_error
    error = assert_raises(Nabu::ParseError) { PARSER.parse("<html><body>Service unavailable</body></html>", label: "x") }
    assert_match(/no teiHeader/, error.message)
  end

  def test_the_book_table_is_the_na_order_with_the_hub_tokens
    assert_equal 27, PARSER::BOOKS.size
    assert_equal %w[Phlm phlm PHILEM], PARSER::BOOKS.fetch(18)
    assert_equal %w[Acts acts ACTS], PARSER::BOOKS.fetch(5)
    assert_equal %w[Rev rev REV], PARSER::BOOKS.fetch(27)
  end
end
