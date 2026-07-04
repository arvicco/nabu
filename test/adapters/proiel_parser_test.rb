# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tempfile"

# ProielParser unit tests against the real PROIEL fixture (P3-4) — a trimmed
# cic-off.xml (Cicero, De officiis): 4 divs / 18 sentences, full <annotation>
# dictionaries and full <source> header intact. Covers sentence=passage
# minting from upstream sentence ids, surface-text reconstruction from the
# presentation attributes, token annotations, empty-token handling, and the
# cross-check / malformed-input error paths.
class ProielParserTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/proiel/cic-off-head15.xml", __dir__)
  URN = "urn:nabu:proiel:cic-off"

  def parser
    Nabu::Adapters::ProielParser.new
  end

  def parse
    parser.parse(FIXTURE, urn: URN, language: "lat", title: "De officiis")
  end

  # --- document + passage minting -----------------------------------------

  def test_document_fields
    document = parse
    assert_equal URN, document.urn
    assert_equal "lat", document.language
    assert_equal "De officiis", document.title
    assert_equal FIXTURE, document.canonical_path
  end

  def test_eighteen_sentences_become_eighteen_passages
    assert_equal 18, parse.size
  end

  def test_first_passage_urn_uses_the_real_upstream_sentence_id
    first = parse.first
    assert_equal "#{URN}:86000", first.urn
    assert_equal 0, first.sequence
  end

  def test_passage_urns_follow_the_non_contiguous_upstream_ids_in_document_order
    # Upstream sentence ids are stable db keys, NOT contiguous/document-order
    # (note 88119/88118 interleaved among the 86xxx ids). Minted verbatim.
    urns = parse.map(&:urn)
    assert_includes urns, "#{URN}:88119"
    assert_includes urns, "#{URN}:88118"
    assert_equal "#{URN}:86001", urns[1]
  end

  # --- surface text reconstruction ----------------------------------------

  def test_first_sentence_text_reconstructs_from_presentation_attributes
    text = parse.first.text
    assert text.start_with?("Quamquam te, Marce fili, annum iam audientem Cratippum, idque "),
           "unexpected first-sentence prefix: #{text[0, 80].inspect}"
    # 'que' fuses onto 'id' (no presentation-after on 'id') — spacing is driven
    # by the presentation attrs, not element boundaries.
    assert_includes text, "Cratippum, idque Athenis"
    # Ends on the last real token's form + its presentation-after ('. '), stripped.
    assert text.end_with?("orationis facultate."), "unexpected tail: #{text[-40..].inspect}"
  end

  def test_text_normalized_is_the_minted_search_form
    first = parse.first
    assert_equal Nabu::Normalize.search_form(first.text, language: "lat"), first.text_normalized
    assert first.text_normalized.unicode_normalized?(:nfc)
    assert first.text.start_with?("Quamquam")
    assert first.text_normalized.start_with?("quamquam")
  end

  # The lat rule (v→u, j→i) reaches PROIEL passages through Passage minting:
  # sentence 86001 reads "videmur" in the fixture, "uidemur" in the search form.
  def test_latin_search_form_folds_v_to_u
    passage = parse.find { |p| p.urn.end_with?(":86001") }
    refute_nil passage
    assert_includes passage.text, "videmur", "pristine text keeps the editor's v"
    assert_includes passage.text_normalized, "uidemur"
  end

  def test_presentation_before_is_honoured
    # Sentence 88119 wraps 'nihil' in a paren via presentation-before="(".
    passage = parse.find { |p| p.urn.end_with?(":88119") }
    refute_nil passage
    assert_includes passage.text, "(nihil"
  end

  # --- token annotations ---------------------------------------------------

  def test_first_token_annotations_spot_check
    tokens = parse.first.annotations.fetch("tokens")
    first = tokens.first
    assert_equal "quamquam", first["lemma"]
    assert_equal "G-", first["part_of_speech"]
    assert_equal "1.1", first["citation_part"]
    assert_equal "Quamquam", first["form"]
    assert_equal "---------n", first["morphology"]
    assert_equal "adv", first["relation"]
  end

  def test_sentence_level_citation_and_status_annotations
    annotations = parse.first.annotations
    assert_equal "1.1", annotations["citation"]
    assert_equal "reviewed", annotations["status"]
  end

  def test_nil_token_attributes_are_dropped
    # The sentence-final verb 'censeo' (id 1196727) carries no head-id.
    tokens = parse.first.annotations.fetch("tokens")
    censeo = tokens.find { |token| token["form"] == "censeo" }
    refute_nil censeo
    refute censeo.key?("head_id"), "absent head-id must be dropped, not nil-valued"
  end

  # --- empty tokens --------------------------------------------------------

  def test_empty_tokens_are_kept_in_annotations_but_absent_from_text
    passage = parse.first
    tokens = passage.annotations.fetch("tokens")
    empties = tokens.select { |token| token.key?("empty_token_sort") }
    refute_empty empties, "the first sentence has empty tokens (1231782–1231785)"
    empties.each do |token|
      refute token.key?("form"), "empty tokens carry no form"
    end
    # Empty tokens' ids never leak into the surface text.
    refute_includes passage.text, "1231782"
  end

  # --- error paths ---------------------------------------------------------

  def test_language_mismatch_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      parser.parse(FIXTURE, urn: URN, language: "grc", title: "De officiis")
    end
    assert_match(/language mismatch/, error.message)
  end

  def test_source_id_not_matching_urn_tail_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      parser.parse(FIXTURE, urn: "urn:nabu:proiel:wrong-work", language: "lat")
    end
    assert_match(/source id mismatch/, error.message)
  end

  def test_missing_sentence_id_raises_parse_error_naming_file_and_position
    xml = File.read(FIXTURE).sub('<sentence id="86000" status="reviewed">', '<sentence status="reviewed">')
    with_tempfile(xml) do |path|
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: URN, language: "lat")
      end
      assert_match(/missing its @id/, error.message)
      assert_includes error.message, path
    end
  end

  def test_zero_sentences_raises_parse_error
    xml = File.read(FIXTURE).gsub(%r{<sentence\b.*?</sentence>}m, "")
    with_tempfile(xml) do |path|
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: URN, language: "lat")
      end
      assert_match(/no <sentence> elements found/, error.message)
    end
  end

  def test_malformed_xml_raises_parse_error
    with_tempfile("<proiel><source id=\"cic-off\"") do |path|
      assert_raises(Nabu::ParseError) { parser.parse(path, urn: URN, language: "lat") }
    end
  end

  # --- io + streaming discipline ------------------------------------------

  def test_parses_from_an_open_io_with_explicit_canonical_path
    io = StringIO.new(File.read(FIXTURE))
    document = parser.parse(io, urn: URN, language: "lat", canonical_path: "cic-off.xml")
    assert_equal 18, document.size
    assert_equal "cic-off.xml", document.canonical_path
  end

  def test_io_without_path_requires_canonical_path
    io = StringIO.new(File.read(FIXTURE))
    assert_raises(ArgumentError) { parser.parse(io, urn: URN, language: "lat") }
  end

  def test_implementation_streams_and_never_builds_a_full_document_dom
    # PROIEL sources reach ~29 MB; the parser must go through
    # Nokogiri::XML::Reader, never a whole-document DOM. Assert on code
    # structure (runtime spying would contort the design, per the packet spec).
    source = File.read(File.expand_path("../../lib/nabu/adapters/proiel_parser.rb", __dir__))
    refute_match(/Nokogiri::XML(\.parse)?\s*\(/, source, "must not DOM-parse the document")
    refute_match(/Nokogiri::XML::Document/, source, "must not build a full XML document")
    assert_match(/Nokogiri::XML::Reader/, source, "must stream via Nokogiri::XML::Reader")
  end

  private

  def with_tempfile(content)
    Tempfile.create(["proiel", ".xml"]) do |file|
      file.write(content)
      file.flush
      yield file.path
    end
  end
end
