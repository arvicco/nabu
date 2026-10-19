# frozen_string_literal: true

require "test_helper"

# PapyriTranslationParser: the translation files of the idp.data clone —
# Translations/<bucket>/<HGV>-<n>.xml (the HGV/DDbDP/APIS translations in
# EpiDoc) and the translation div an APIS/ record still carries — parsed
# into one translation document each. Passages follow the translator's
# own line milestones (<milestone unit="line" n="…"/>, under the
# textpart path), so they cite the same line numbers as the edition;
# un-milestoned prose is a block passage (p<k>). Real fixtures, whole.
class PapyriTranslationParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("ddbdp")

  def parse(relative, urn: "urn:nabu:ddbdp:x-trans-1", metadata: {})
    Nabu::Adapters::PapyriTranslationParser.new.parse(File.join(FIXTURES, relative), urn: urn, metadata: metadata)
  end

  def suffixes(document)
    document.map { |passage| passage.urn.delete_prefix(document.urn) }
  end

  def test_line_milestones_become_line_cited_passages
    document = parse("Translations/8/8875-1.xml", urn: "urn:nabu:ddbdp:bgu:1:100-trans-8875-1")
    assert_equal "deu", document.language
    assert_equal %w[:1 :2 :6 :9 :10], suffixes(document)
    assert_equal "Komôn, Sohn des Mûsaios, des Sohnes des Hêrakleitos, grüßt Pekysis, Sohn des Hôros.",
                 document.first.text
  end

  def test_inline_lemmata_and_terms_read_as_running_text
    second = parse("Translations/8/8875-2.xml").passages[1]
    assert_includes second.text, "reddish, branded on its right jaw"
    assert_includes second.text, "on the spot, just as it is, unreturnable"
    refute_match(/\s{2,}/, second.text, "whitespace collapses")
  end

  def test_textparts_ride_in_the_passage_path
    document = parse("Translations/2/2416-1.xml")
    assert_equal "eng", document.language
    assert_equal %w[:r:1 :v:5], suffixes(document)
    assert_includes document.passages.last.text, "(Addressed) To Zenon."
  end

  def test_unmilestoned_block_translation_is_one_block_passage
    document = parse("Translations/13/13581-1.xml")
    assert_equal %w[:p1], suffixes(document)
    assert_includes document.first.text, "I, Eutuchos, president (hegoumenos)"
  end

  def test_apis_record_translation_takes_its_language_from_the_lang_usage
    document = parse("APIS/berkeley/xml/berkeley.apis.253.xml")
    assert_equal "eng", document.language, "the APIS div carries no xml:lang; the record's langUsage names en"
    assert_includes document.first.text, "Wisest of wise is he"
  end

  # Upstream's two misspelt translation-language tags, folded by content
  # (88604-1 is French under xml:lang="fe").
  def test_misspelt_language_tag_folds
    assert_equal "fra", parse("Translations/88/88604-1.xml").language
  end

  def test_document_metadata_marks_the_translation_and_its_provenance
    document = parse("Translations/13/13581-1.xml", metadata: { "translation_of" => "urn:nabu:ddbdp:p.tebt:2:484v" })
    assert_equal "translation", document.metadata["kind"]
    assert_equal "urn:nabu:ddbdp:p.tebt:2:484v", document.metadata["translation_of"]
    assert_equal "APIS", document.metadata["authority"]
    assert_equal ["P.Tebt., II.484 (desc. only)"], document.metadata["bibliography"]
    refute_nil document.title
  end

  def test_parse_is_stable
    a = parse("Translations/8/8877-1.xml")
    b = parse("Translations/8/8877-1.xml")
    assert_equal a.map(&:text), b.map(&:text)
    assert_equal a.map(&:urn), b.map(&:urn)
  end

  def test_a_file_without_translation_text_is_a_parse_error
    assert_raises(Nabu::ParseError) { parse("DDbDP/8/8875.xml") }
  end
end
