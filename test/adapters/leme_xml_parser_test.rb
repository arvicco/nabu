# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The leme-xml parser family (LEME's own XML, not TEI), run against the
# real leme fixtures: Baldwin 1549 (whole, a well-formed DOCTYPE), Aubrey
# 1719 (whole, the DOCTYPE whose entity values are lost), Martinez 1593
# (trimmed: no DOCTYPE, a BOM, undeclared entities, <page> written as a
# container) and Cotton's essay (whole, no word-entry markup).
class LemeXmlParserTest < Minitest::Test
  PARSER = Nabu::Adapters::LemeXmlParser

  def path(key) = File.join(Nabu::TestSupport.fixtures("leme"), "xml", "#{key}.xml")

  def parse(key, context: {}) = PARSER.new.parse(path(key), context: context)

  def entry(key, id) = parse(key).entries.find { |e| e.entry_id == id }

  def test_entry_ids_are_ordinals_in_file_order
    result = parse("102611")
    assert_equal (1..15).map { |n| "e#{n}" }, result.entries.map(&:entry_id)
    assert_equal "1393", result.leme_no
  end

  def test_headword_drops_trailing_punctuation_and_key_raw_keeps_the_print
    amana = entry("102611", "e1")
    assert_equal "AMana,", amana.key_raw
    assert_equal "AMana", amana.headword
    assert_equal "signifieth Truth", amana.gloss
    assert_equal "AMana, signifieth Truth.", amana.body
  end

  def test_inline_terms_read_in_the_explanation
    sanir = parse("102611").entries.last
    assert_equal "Sanir", sanir.headword
    assert_equal "Sanir, the name of Hermon, as the Amorites call it.", sanir.body
  end

  def test_the_form_language_maps_and_the_shelf_takes_the_majority
    result = parse("102611")
    assert_equal "hbo", result.language, "Baldwin's glossary interprets 'the Hebrue wurdes' (LEME het)"
    assert(result.entries.all? { |e| e.language == "hbo" })
    assert_equal "en", result.entries.first.annotations["xpln_lang"]
    refute result.entries.first.annotations.key?("language"), "an entry in the shelf language names none"
    assert_equal "en", parse("124555").language
  end

  def test_unmapped_codes_read_und_with_the_leme_code_kept
    assert_equal "und", PARSER.language_for("tbd")
    assert_equal "en", PARSER.language_for(nil), "a lang-less form reads LEME's English default"
    assert_equal "en", PARSER.language_for("")
    assert_equal "spa", PARSER.language_for("sp")
    assert_equal "ang", PARSER.language_for("oe")
  end

  def test_a_lost_entity_subset_reads_through_the_snapshot
    result = parse("124555")
    assert_equal 1, result.census["broken_entity_subset"]
    assert_equal 11, result.entries.size
    assert_equal "Yarrow, yare", result.entries.first.headword
  end

  def test_soft_hyphen_line_splits_join_as_leme_displays_them
    foreslowe = parse("124555").entries.find { |e| e.headword == "To foreslowe the Time" }
    assert_equal "To foreslowe the Time, (i.e.) to be remiss, to be backward, and lose an Opportunity.",
                 foreslowe.body
  end

  def test_editor_notes_pages_and_sections_ride_annotations
    eve = parse("124555").entries.find { |e| e.headword == "Eve" }
    assert_equal ['"eve" not found in OED in this sense.'], eve.annotations["editor_notes"]
    assert_equal "402", eve.annotations["page"]
    assert_equal "Appendix", eve.annotations["section"]
    refute_includes eve.body, "OED", "LEME's own notes stay out of the printed text"
    place = parse("124555").entries.find { |e| e.headword == "Place" }
    assert_equal "403", place.annotations["page"]
  end

  def test_a_file_without_doctype_resolves_entities_and_neutralizes_unknown_ones
    result = parse("131265")
    assert_equal 13, result.entries.size
    assert_equal "207", result.leme_no
    assert_equal 1, result.census["unknown_entity:syh"]
    elil = result.entries.find { |e| e.body.include?("Ælul") }
    refute_nil elil, "&AElig; (undeclared in this file) reads through the snapshot"
    offend = result.entries.find { |e| e.body.include?("offen&syh;") }
    refute_nil offend, "an entity known to nobody stays literal text"
  end

  def test_sub_entries_ride_their_own_body_lines_and_lexemes_annotate
    abib = parse("131265").entries.first
    assert_equal "hbo", abib.language
    lines = abib.body.lines(chomp: true)
    assert_equal "אָבׅיב The moneth Abib. An eare of corne.", lines.first
    assert_equal "אֵב Greene.", lines[1]
    assert_equal ["ear(n)", "corn(n)"], abib.annotations["lexemes"]
    assert_equal "3", abib.annotations["page"]
    assert_equal "A", abib.annotations["group"]
  end

  def test_a_page_container_closing_inside_an_entry_reads_as_a_milestone
    amen = parse("131265").entries.find { |e| e.body.include?("nourisher") }
    refute_nil amen
    assert_includes amen.body, "A nourisher, common people."
    assert_equal "10", amen.annotations["page"]
  end

  def test_context_rides_every_entry
    result = parse("102611", context: { "lexicon_year" => "1549" })
    assert(result.entries.all? { |e| e.annotations["lexicon_year"] == "1549" })
  end

  def test_a_file_without_word_entries_parses_to_none
    assert_empty parse("102105").entries
  end

  def test_output_is_nfc_outside_the_exempt_languages
    %w[102611 124555 131265].each do |key|
      parse(key).entries.each do |e|
        next if Nabu::Normalize.nfc_exempt?(e.language)

        assert e.body.unicode_normalized?(:nfc), "#{key} #{e.entry_id}"
      end
    end
  end

  def test_malformed_xml_is_a_parse_error
    Dir.mktmpdir do |dir|
      bad = File.join(dir, "bad.xml")
      File.write(bad, "<root><leme no=\"1\"><wordentry type=\"h\"><form>A</form></leme></root>")
      assert_raises(Nabu::ParseError) { PARSER.new.parse(bad) }
    end
  end
end
