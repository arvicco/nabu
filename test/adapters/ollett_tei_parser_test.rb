# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The `ollett-tei` parser family (P118-3): Andrew Ollett's Kannada and
# Prakrit TEI editions, exercised on trimmed REAL upstream files from both
# fixture trees (test/fixtures/kannada-texts, test/fixtures/prakrit-texts —
# recipes in each README). The adapters' own tests cover discovery,
# exclusion and the per-source metadata refinements.
class OllettTeiParserTest < Minitest::Test
  KANNADA = Nabu::TestSupport.fixtures("kannada-texts")
  PRAKRIT = Nabu::TestSupport.fixtures("prakrit-texts")

  PAMPA = File.join(KANNADA, "tei", "Pampa", "pampa-ādipurāṇaṁ-a1.xml")
  JANNA = File.join(KANNADA, "tei", "Janna", "janna-anantanāthapurāṇaṁ-a1.xml")
  HONNAMMA = File.join(KANNADA, "tei", "Honnamma", "honnamma-hadibadeyadharma-iso-s1-9.xml")
  KABHABHU = File.join(KANNADA, "tei", "Nāgavarma II", "nāgavarma-karṇāṭakabhāṣābhūṣaṇam-s1-4.xml")
  GAUDAVAHO = File.join(PRAKRIT, "tei", "Vākpatirāja", "GaüḍVa-1-3.xml")
  DESINAMAMALA = File.join(PRAKRIT, "tei", "Hēmacandra", "DēNāMā-1-2.xml")
  TARA = File.join(PRAKRIT, "tei", "Bappabhaṭṭi", "Tārā-1-3.xml")
  NANDI = File.join(PRAKRIT, "tei", "Śvētāmbarāgama", "Agam_44_Chuliyaa_01_Moolam_Nandisuyam_003787-s1-3.xml")
  AYARA = File.join(PRAKRIT, "tei", "Śvētāmbarāgama", "Agam_01_Angsuttam_01_Moolam_Aayaro_003701-s1-2.xml")
  SETU = File.join(PRAKRIT, "tei", "Pravarasēna", "Sētu.xml")
  ACARA = File.join(PRAKRIT, "quarantine", "ācāraniryukti-1-66.xml")

  BY_SA_4 = { %r{creativecommons\.org/licenses/by-sa/4\.0} => "CC BY-SA 4.0" }.freeze

  def parser(allowed: %w[kan-Latn san-Latn pra-Latn pka-Latn], grants: BY_SA_4)
    Nabu::Adapters::OllettTeiParser.new(allowed: allowed, grants: grants)
  end

  def parse(path, default_language: "kan-Latn", **)
    parser(**).parse(path, urn: "urn:t", default_language: default_language)
  end

  def passage(document, citation)
    document.find { |p| p.urn == "urn:t:#{citation}" } || flunk("no passage #{citation}: #{document.map(&:urn)}")
  end

  # -- citation: the cRefPattern path, ordinals, trailers -----------------

  def test_div_path_plus_lg_n_is_the_citation
    doc = parse(PAMPA)
    assert_equal(%w[1.1 1.2 1.3 1.42 1.p1 1.43 1.84 1.tr1 tr1], doc.map { |p| p.urn.delete_prefix("urn:t:") })
    first = passage(doc, "1.1")
    assert_equal "attribute", first.annotations["addressing"]
    assert_equal "ordinal", passage(doc, "1.p1").annotations["addressing"]
  end

  def test_verse_lines_join_by_newline_never_inventing_word_breaks
    text = passage(parse(PAMPA), "1.1").text
    lines = text.split("\n")
    assert_equal 4, lines.size
    assert_equal "śrīdēvēndramunīndravanditaguṇavrātaṁ jagatsvāmi saṁ", lines.first
    assert_equal "dādibrahmanagādhabōdhaniḷayaṁ durvārasaṁsāravi", lines[1]
  end

  def test_lb_break_no_joins_and_plain_lb_spaces_prose
    text = passage(parse(PAMPA), "1.p1").text
    assert_includes text, "tīrthamahimasamarthanamuṁ"
    assert_includes text, "dēśanivēśōpadēśamuṁ nagarasampatparivarṇanamuṁ"
    refute_includes text, "\n"
  end

  # -- meter, labels, pages, heads ------------------------------------------

  def test_meter_rides_from_lg_met
    doc = parse(PAMPA)
    assert_equal "śārdūlavikrīḍitaṁ", passage(doc, "1.1").annotations["met"]
    assert_equal "kandaṁ", passage(doc, "1.42").annotations["met"]
    assert_nil passage(doc, "1.p1").annotations["met"]
  end

  def test_metrical_label_supplies_meter_for_an_unmetered_stanza
    doc = parse(JANNA)
    tripadi = passage(doc, "1.17")
    assert_equal "tripadi", tripadi.annotations["met"]
    assert_equal "tripadi", tripadi.annotations["label"]
    prose = passage(doc, "1.p1")
    assert_equal "va.", prose.annotations["label"], "the vacana label marks prose — a label, never a meter"
    assert_nil prose.annotations["met"]
    refute_includes prose.text, "va."
  end

  def test_pages_and_div_heads_ride_annotations
    doc = parse(PAMPA)
    assert_equal "3", passage(doc, "1.1").annotations["page"]
    assert_equal "9", passage(doc, "1.42").annotations["page"]
    assert_equal "prathamāśvāsaṁ", passage(doc, "1.42").annotations["head"]
  end

  def test_edition_keyed_page_breaks_ride_separately
    doc = parse(TARA, default_language: "pra-Latn")
    assert_equal({ "b" => "1A", "bh" => "2" }, passage(doc, "2").annotations["pages"])
    assert_equal "1", passage(doc, "2").annotations["page"]
  end

  def test_footnotes_drop_out_of_the_reading_text
    text = passage(parse(JANNA), "1.4").text
    assert_includes text, "nīgenagupādēyaṁ para brahmamiṁ"
    refute_includes text, "ka. bare."
  end

  # -- chāyā, apparatus, base text --------------------------------------------

  def test_chaya_moves_to_annotations_and_lemma_reading_is_the_text
    doc = parse(GAUDAVAHO, default_language: "pra-Latn")
    first = passage(doc, "1")
    assert_equal "pra-Latn", first.language
    assert_equal "āryā", first.annotations["met"]
    assert_equal "maṅgalācaraṇam", first.annotations["label"]
    assert_match(/\Aprathamamēva dhavalakr̥tōpavītamamburuhagōcaraṁ namata/, first.annotations["chaya"])
    refute_includes first.text, "prathamamēva"
    v109 = passage(doc, "109").text
    assert_includes v109, "kōḍi-kaṭṭhaṇutthallō", "app keeps its lemma"
    refute_includes v109, "ghaṭṭa", "rdg readings drop"
  end

  def test_base_text_quotes_mark_the_mula_and_collisions_disambiguate
    doc = parse(DESINAMAMALA, default_language: "pra-Latn")
    base = passage(doc, "2.1.1")
    assert base.annotations["base_text"]
    example = passage(doc, "2.1.1:b2")
    assert_equal "example", example.annotations["type"]
    assert_nil example.annotations["base_text"]
    assert_equal "ordinal", passage(doc, "1.1.p1").annotations["addressing"]
  end

  # -- language ------------------------------------------------------------

  def test_element_language_switches_and_lists_join_items
    doc = parse(KABHABHU)
    assert_equal "san-Latn", doc.language
    assert_equal "san-Latn", passage(doc, "1.4.p1").language
    examples = passage(doc, "1.4.p3")
    assert_equal "kan-Latn", examples.language
    assert_equal "a; ā; ā3", examples.text
    assert_equal({ "kan-Latn" => 2, "san-Latn" => 11 }, doc.metadata["text_languages"])
  end

  def test_n_less_sections_do_not_reset_ordinals
    doc = parse(TARA, default_language: "pra-Latn")
    commentary = doc.select { |p| p.language == "san-Latn" }.map { |p| p.urn.delete_prefix("urn:t:") }
    assert_equal %w[v1 p1 p2], commentary
  end

  def test_override_by_siglum_wins_over_the_text_tag
    doc = parser.parse(HONNAMMA, urn: "urn:t", default_language: "kan-Latn",
                                 language_overrides: { "HaDha" => "kan-Latn" })
    assert_equal "kan-Latn", doc.language
    assert_equal "kan-Latn", passage(doc, "1.1").language
    shloka = passage(doc, "9.v1")
    assert_equal "san-Latn", shloka.language, "an explicitly tagged Sanskrit stanza keeps its tag"
    assert_equal "ślōka", shloka.annotations["label"]
  end

  def test_without_the_override_the_upstream_tag_rides
    assert_equal "san-Latn", parse(HONNAMMA).language
  end

  def test_unknown_language_code_quarantines
    error = assert_raises(Nabu::ParseError) { parse(KABHABHU, allowed: %w[san-Latn]) }
    assert_match(/unknown language code "kan-Latn"/, error.message)
  end

  def test_back_matter_cites_under_a_back_prefix
    doc = parse(NANDI, default_language: "pra-Latn")
    assert_equal "pka-Latn", doc.language
    back = passage(doc, "back.2.2")
    assert_equal "parisiṭṭhaṁ-1-aṇunnānandī", back.annotations["head"]
    assert_match(/\Akimaṇunnā/, back.text)
  end

  def test_an_lg_of_lgs_is_a_container
    doc = parse(SETU, default_language: "pra-Latn",
                      grants: { %r{creativecommons\.org/licenses/by-sa/3\.0} => "CC BY-SA 3.0" })
    assert_equal(%w[1.1 1.2 1.3 1.4 1.tr1], doc.map { |p| p.urn.delete_prefix("urn:t:") })
    assert_equal "āikulaaṁ", passage(doc, "1.1").annotations["label"]
    assert_equal 2, passage(doc, "1.1").annotations["lines"]
  end

  # -- header + license gate -----------------------------------------------

  def test_header_metadata_and_verbatim_grant
    doc = parse(GAUDAVAHO, default_language: "pra-Latn")
    meta = doc.metadata
    assert_equal "Gaüḍavahaṁ", doc.title
    assert_equal "GaüḍVa", meta["siglum"]
    assert_equal "CC BY-SA 4.0", meta["license"]
    assert_equal "Prakrit Digital Texts Project. Distributed under a Creative Commons " \
                 "Attribution-ShareAlike 4.0 license.", meta["license_statement"]
    assert_equal "https://creativecommons.org/licenses/by-sa/4.0/", meta["license_url"]
    assert_equal({ "title" => "Gaüḍavahō by Vākpatirāja", "editors" => ["N. G. Suru"],
                   "publisher" => "Prakrit Text Society", "pub_place" => "Ahmedabad", "date" => "1975",
                   "series" => "Prakrit Text Series", "idnos" => { "oclc" => "24153300" } }, meta["source_edition"])
  end

  def test_editor_names_read_forename_first
    editors = parse(DESINAMAMALA, default_language: "pra-Latn").metadata.dig("source_edition", "editors")
    assert_equal ["Richard Pischel"], editors
  end

  def test_template_comment_availability_fails_the_license_gate
    error = assert_raises(Nabu::ParseError) { parse(AYARA, default_language: "pra-Latn") }
    assert_match(/license gate: no grant/, error.message)
  end

  def test_a_grant_outside_the_recognized_set_fails_the_gate
    error = assert_raises(Nabu::ParseError) { parse(SETU, default_language: "pra-Latn") }
    assert_match(/license gate: unrecognized grant/, error.message)
  end

  def test_not_well_formed_upstream_file_quarantines
    error = assert_raises(Nabu::ParseError) { parse(ACARA, default_language: "pra-Latn") }
    assert_match(/malformed XML/, error.message)
  end

  def test_two_parses_are_identical
    first = parse(DESINAMAMALA, default_language: "pra-Latn").map { |p| [p.urn, p.text, p.annotations] }
    assert_equal(first, parse(DESINAMAMALA, default_language: "pra-Latn").map { |p| [p.urn, p.text, p.annotations] })
  end
end
