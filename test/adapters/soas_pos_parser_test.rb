# frozen_string_literal: true

require "test_helper"
require "stringio"

# Nabu::Adapters::SoasPosParser (P48-3): the `soas-pos` parser family — the
# SOAS "Tibetan in Digital Communication" gold POS corpus's own format,
# censused from all 8 real files (2026-07-28): one line = one editorial
# chunk of running text, each line space-separated `form|tag` tokens (every
# token exactly one `|`, no interior blank lines, LF endings). Forms are
# Unicode Tibetan syllables carrying their own tsheg/shad, so the passage
# text is the forms joined with NOTHING; the citation is the 1-based
# physical line number (the corpus's only stable address). Segmentation and
# POS are hand-corrected gold; there is NO lemma column anywhere — tokens
# mint only form/pos keys, so the source honestly mints zero lemma rows.
#
# COMPOSE VERDICT — no existing family fits: not CoNLL-U (no tabs, no
# sent_id, no 10-column lines), not any TEI/TSV family. Small bespoke
# parser, tested here first (house rule).
class SoasPosParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("soas-tibetan")
  MDZANGSBLUN = File.join(FIXTURES, "Texts", "mdzangsblun-horizontal.txt")
  MARPA = File.join(FIXTURES, "Texts", "marpa-horizontal.txt")

  def parser = Nabu::Adapters::SoasPosParser.new

  def parse(source, urn: "urn:nabu:soas-tibetan:test", **)
    parser.parse(source, urn: urn, language: "xct", **)
  end

  def test_one_passage_per_line_cited_by_physical_line_number
    document = parse(MDZANGSBLUN)
    assert_equal 3, document.count
    assert_equal %w[urn:nabu:soas-tibetan:test:1
                    urn:nabu:soas-tibetan:test:2
                    urn:nabu:soas-tibetan:test:3], document.map(&:urn)
    assert_equal [0, 1, 2], document.map(&:sequence)
  end

  def test_passage_text_is_the_forms_joined_with_nothing
    first = parse(MDZANGSBLUN).first
    assert first.text.start_with?("།མཛངས་བླུན་ཞེས་བྱ་བའི་མདོ།།བམ་པོ་དང་པོ།"),
           "Tibetan forms carry their own tsheg/shad — joining inserts nothing"
    refute_includes first.text, " ", "no separator ever leaks into the text"
    assert first.text.unicode_normalized?(:nfc)
  end

  def test_tokens_ride_as_form_pos_pairs_with_no_lemma_key
    tokens = parse(MDZANGSBLUN).first.annotations["tokens"]
    assert_equal 377, tokens.length
    assert_equal({ "form" => "།", "pos" => "punc" }, tokens[0])
    assert_equal({ "form" => "མཛངས་བླུན་", "pos" => "n.count" }, tokens[1])
    assert_equal({ "form" => "ཞེས་", "pos" => "cl.quot~quote.E" }, tokens[2],
                 "the ~-joined tag variant rides verbatim")
    assert(tokens.none? { |token| token.key?("lemma") },
           "POS-only gold — a lemma key here would fake a lemma lane")
  end

  def test_title_and_metadata_ride_through_to_the_document
    document = parse(MARPA, title: "Mar paḥi rnam thar", metadata: { "text_id" => "marpa" })
    assert_equal "Mar paḥi rnam thar", document.title
    assert_equal "marpa", document.metadata["text_id"]
    assert_equal "xct", document.language
    assert_equal 2, document.count
    assert_equal "skt", document.to_a[1].annotations["tokens"].first["pos"],
                 "the Sanskrit-mantra tag from the real marpa opening"
  end

  def test_a_token_without_a_pipe_is_a_parse_error_naming_the_line
    error = assert_raises(Nabu::ParseError) do
      parse(StringIO.new("ཞེས་|cl.quot བྱ་བ\n"))
    end
    assert_match(/line 1/, error.message)
    assert_match(/བྱ་བ/, error.message)
  end

  def test_blank_lines_are_skipped_without_shifting_physical_line_citations
    document = parse(StringIO.new("ཞེས་|cl.quot\n\nབྱ་བ|n.v.fut\n"))
    assert_equal %w[urn:nabu:soas-tibetan:test:1 urn:nabu:soas-tibetan:test:3],
                 document.map(&:urn),
                 "citation = PHYSICAL line number, stable whether or not blanks appear"
  end

  def test_an_empty_source_is_a_parse_error
    assert_raises(Nabu::ParseError) { parse(StringIO.new("")) }
  end
end
