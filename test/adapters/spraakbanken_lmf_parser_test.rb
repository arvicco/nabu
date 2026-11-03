# frozen_string_literal: true

require "test_helper"

# The Språkbanken Karp LMF dictionary parser family (Söderwall,
# Söderwall's supplement, Schlyter — the fsv-lexica shelves), run against
# the trimmed-real fsv-lexica fixtures.
class SpraakbankenLmfParserTest < Minitest::Test
  def fixture(rel) = File.join(Nabu::TestSupport.fixtures("fsv-lexica"), rel)

  def entries(rel) = Nabu::Adapters::SpraakbankenLmfParser.new(language: "sv").entries(fixture(rel))

  def entry(rel, id) = entries(rel).find { |e| e.entry_id == id }

  def test_entries_are_keyed_by_the_lemgram_in_file_order
    ids = entries("soederwall/soederwall.xml").map(&:entry_id)
    assert_equal %w[fsvm--a..nn.1 fsvm--aterlösilse..nn.1 fsvm--avisning..nn.1], ids
  end

  def test_the_headword_is_the_lemgram_baseform_not_the_noisy_printed_line
    argha = entry("soederwall-supp/soederwall-supp.xml", "fsvm--argha..e.1")
    assert_equal "argha", argha.headword
    assert_equal "fsvm--argha..e.1", argha.key_raw
    assert_match(/\Aargha v fördefva försämra\./, argha.body, "the printed head line stays verbatim in the body")
    assert_equal "hemuls eþer", entry("schlyter/schlyter.xml", "fsvm--hemuls__eþer..nn.1").headword
  end

  def test_body_carries_head_line_forms_and_senses_with_entities_decoded
    a = entry("soederwall/soederwall.xml", "fsvm--a..nn.1")
    lines = a.body.lines(chomp: true)
    assert_equal "a", lines[0]
    assert_equal "aa . · pl. · äär MB 1:294, (Cod. B) 543; su 85),", lines[1]
    assert_match(/\Aå, mindre älf\. KL 312, 329 \./, lines[2])
    assert_includes a.body, "\" ther war aff blodh badhe ström ok a \""
    refute_includes a.body, "&quot;"
  end

  def test_gloss_is_the_first_definition_up_to_its_first_sentence_end
    assert_equal "å, mindre älf", entry("soederwall/soederwall.xml", "fsvm--a..nn.1").gloss
    assert_equal "anvisning, hänvisning", entry("schlyter/schlyter.xml", "fsvm--avisning..nn.1").gloss
    assert_equal "alkali, lutsalt", entry("soederwall-supp/soederwall-supp.xml", "fsvm--alkali..e.1").gloss
  end

  def test_an_entry_without_any_text_keeps_its_head_line_and_no_gloss
    bare = entry("soederwall/soederwall.xml", "fsvm--aterlösilse..nn.1")
    assert_equal "aterlösilse", bare.body
    assert_nil bare.gloss
  end

  def test_part_of_speech_tags_are_mined_into_annotations
    assert_equal({ "pos" => ["nn"] }, entry("schlyter/schlyter.xml", "fsvm--a..nn.1").annotations)
    assert_equal({}, entry("soederwall-supp/soederwall-supp.xml", "fsvm--argha..e.1").annotations)
  end

  def test_folded_headword_and_nfc
    entries("schlyter/schlyter.xml").each do |e|
      assert e.body.unicode_normalized?(:nfc)
      assert_equal Nabu::Normalize.search_form(e.headword, language: "sv"), e.headword_folded
    end
  end

  def test_malformed_xml_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.xml")
      File.write(path, "<LexicalResource><Lexicon><LexicalEntry><Lemma></LexicalEntry>")
      assert_raises(Nabu::ParseError) { Nabu::Adapters::SpraakbankenLmfParser.new(language: "sv").entries(path) }
    end
  end
end
