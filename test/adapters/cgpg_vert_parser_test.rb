# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Adapters::CgpgVertParser — the cgpg-vert family: CGPG's Sketch
# Engine vertical files (one <w id="PDF Page P, Line L - word id N"> block
# per token, five tab-separated columns: form, folded form, lemma, folded
# lemma, POS). Fixtures are trimmed real volume files (see the fixture
# README): whole PDF pages, CRLF line ends and every upstream quirk kept.
class CgpgVertParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("cgpg")

  def parse(name, urn: "urn:nabu:cgpg:test")
    Nabu::Adapters::CgpgVertParser.new.parse(
      File.join(FIXTURES, name), urn: urn, language: "grc", title: "t", metadata: { "k" => "v" }
    )
  end

  def test_one_passage_per_pdf_page_keyed_by_the_page_number
    document = parse("PG008_tagged_text.txt")
    assert_equal ["urn:nabu:cgpg:test:p57", "urn:nabu:cgpg:test:p343"], document.passages.map(&:urn)
    assert_equal [0, 1], document.passages.map(&:sequence)
    assert_equal([57, 343], document.passages.map { |p| p.annotations["pdf_page"] })
  end

  def test_page_text_keeps_the_ocr_line_layout
    passage = parse("PG101_tagged_text.vert").passages.first
    lines = passage.text.split("\n")
    assert_equal 52, lines.size, "one text line per upstream Line number"
    assert_equal "«Ἐπειδὴ τοίνυν οἱ παρὰ τοῦ βασιλέως τότε πολλὰ", lines.first
    assert_equal "αὐτῷ τὴν τῆς ἱεραρχίας καταβαλόμενος ἀρχὴν, ἀκόλουθον", lines.last
    assert_equal "Ἰγνατίου λαβεῖν, γεν", lines[2].split.last(3).join(" "),
                 "a line-end word break stays split, as OCR'd — canonical means canonical"
  end

  def test_tokens_carry_form_lemma_and_pos
    tokens = parse("PG101_tagged_text.vert").passages.first.annotations["tokens"]
    assert_equal 388, tokens.size
    assert_equal({ "form" => "«Ἐπειδὴ", "lemma" => "ἐπειδή", "pos" => "I+Conj", "line" => 1 }, tokens.first)
    assert_equal({ "form" => "βασιλέως", "lemma" => "βασιλεύς", "pos" => "N+Com", "line" => 1 }, tokens[5])
  end

  # Upstream's three token quirks (whole-deposit census 2026-11-02):
  # an analysis-less punctuation token (∅ in every analysis column) keeps
  # its surface but mints no lemma; an empty-form token (form column empty,
  # 2,229 deposit-wide) contributes nothing; a spreadsheet-error line
  # ("#NOM?", 66 deposit-wide — the token and its </w> lost upstream) is
  # dropped. Both losses are censused in document metadata.
  def test_quirk_tokens_are_kept_dropped_or_censused
    document = parse("PG008_tagged_text.txt")
    tokens = document.passages.first.annotations["tokens"]
    guillemet = tokens.find { |token| token["form"] == "»" }
    assert_equal({ "form" => "»", "line" => 17 }, guillemet, "∅ analysis → no lemma/pos keys")
    refute(document.passages.flat_map { |p| p.annotations["tokens"] }.any? { |t| t["form"].to_s.empty? })
    refute_includes document.passages.last.text, "#NOM?"
    assert_equal 1, document.metadata["empty_form_tokens"]
    assert_equal 1, document.metadata["lost_tokens"]
    assert_equal "v", document.metadata["k"], "caller metadata merges"
  end

  # The page-level read the work carve composes (a plan work takes a set of
  # pages out of one volume): every page keyed by its PDF page number, with
  # the same text and tokens a whole-volume parse mints, and the token
  # losses censused PER PAGE so a work sums only its own.
  def test_pages_reads_every_page_with_its_own_loss_census
    volume = Nabu::Adapters::CgpgVertParser.new.pages(File.join(FIXTURES, "PG008_tagged_text.txt"))
    assert_equal "PG 8 - AI processed", volume.doc_id
    assert_equal [57, 343], volume.pages.keys
    first, last = volume.pages.values_at(57, 343)
    assert_equal [1, 0], [first.empty_form_tokens, last.empty_form_tokens]
    assert_equal [0, 1], [first.lost_tokens, last.lost_tokens]
    whole = parse("PG008_tagged_text.txt").passages
    assert_equal whole.map(&:text), [first.text, last.text]
    assert_equal(whole.map { |p| p.annotations["tokens"] }, [first.tokens, last.tokens])
  end

  def test_the_doc_id_rides_metadata
    assert_equal "PG 153 - AI processed", parse("PG153_tagged_text.vert").metadata["doc_id"]
  end

  def test_text_is_nfc
    parse("PG153_tagged_text.vert").passages.each do |passage|
      assert_equal passage.text.unicode_normalize(:nfc), passage.text
    end
  end

  def test_a_second_doc_element_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "two.vert")
      body = File.binread(File.join(FIXTURES, "PG153_tagged_text.vert"))
      File.binwrite(path, body + body)
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::CgpgVertParser.new.parse(path, urn: "u", language: "grc", title: "t")
      end
      assert_match(/second <doc>/, error.message)
    end
  end

  def test_a_file_with_no_tokens_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "empty.vert")
      File.binwrite(path, "<doc id=\"PG 1 - AI processed\">\r\n</doc>\r\n")
      assert_raises(Nabu::ParseError) do
        Nabu::Adapters::CgpgVertParser.new.parse(path, urn: "u", language: "grc", title: "t")
      end
    end
  end
end
