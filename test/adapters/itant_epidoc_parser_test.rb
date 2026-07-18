# frozen_string_literal: true

require "test_helper"

# ItantEpidocParser (P29-2): one Corpus_ItAnt EpiDoc TEI record — Sabellic/
# Lepontic epigraphy, the RiigEpidocParser sibling. Fixtures are whole real
# records (test/fixtures/itant/README.md); every expectation below was
# censused against the upstream bytes first.
class ItantEpidocParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("itant")

  OSCAN_2 = File.join(FIXTURES, "Oscan_inscriptions_newEditions", "ItAnt_Oscan_2.xml")
  OSCAN_492 = File.join(FIXTURES, "Oscan_inscriptions_newEditions", "ItAnt_Oscan_492.xml")
  OSCAN_576 = File.join(FIXTURES, "Oscan_inscriptions_newEditions", "ItAnt_Oscan_576.xml")
  LEPONTIC_1 = File.join(FIXTURES, "CelticOfItaly_inscriptions_newEditions", "ItAnt_Lepontic_1.xml")

  def parser
    Nabu::Adapters::ItantEpidocParser.new
  end

  # --- identity + language ----------------------------------------------------

  def test_urn_is_minted_from_the_tei_xml_id
    document = parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-2")
    assert_equal "urn:nabu:itant:oscan-2", document.urn
    assert_equal "Inscription ItAnt Oscan 2", document.title
  end

  def test_a_mismatched_caller_urn_is_a_parse_error
    error = assert_raises(Nabu::ParseError) { parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-3") }
    assert_match(/urn mismatch/, error.message)
  end

  def test_document_language_is_the_script_tagged_langusage_ident
    assert_equal "osc-Ital-x-oscetr", parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-2").language
    assert_equal "xcg-Ital-x-xcglep",
                 parser.parse(LEPONTIC_1, urn: "urn:nabu:itant:lepontic-1").language,
                 "upstream tags Lepontic as Cisalpine Gaulish (xcg), which passes through honestly"
  end

  # --- the interpretative edition walk ---------------------------------------

  def test_oscan_2_mints_one_line_per_lb_across_both_faces
    document = parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-2")
    assert_equal %w[urn:nabu:itant:oscan-2:face_a:1 urn:nabu:itant:oscan-2:face_b:1b],
                 document.map(&:urn)
    assert_equal "pakis: heleviis. trebieís", document.first.text,
                 "name/w tokens space-separated, pc interpuncts glued to the preceding token, " \
                 "expan/abbr/ex read expanded"
    assert_equal "statis: betitis: […]", document.to_a.last.text,
                 "a lost patronymic reads as the gap marker"
  end

  def test_word_tokens_ride_annotations_with_their_onomastic_types
    document = parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-2")
    words = document.first.annotations["words"]
    assert_equal [
      { "form" => "pakis", "type" => "praenomen" },
      { "form" => "heleviis", "type" => "gentilicium" },
      { "form" => "trebieís", "type" => "patronymic" }
    ], words
    face_b = document.to_a.last.annotations["words"]
    assert_equal %w[statis betitis], face_b.map { |word| word["form"] },
                 "the gap-only patronymic token mints no word"
  end

  def test_direction_markup_rides_the_line_annotations
    document = parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-2")
    assert_equal "r-to-l", document.first.annotations["direction"]
    assert_equal "sinistrorse", document.first.annotations["ductus"]
  end

  def test_leiden_annotations_count_gaps
    document = parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-2")
    assert_nil document.first.annotations["leiden"]
    assert_equal [{ "reason" => "lost", "extent" => "unknown", "unit" => "character" }],
                 document.to_a.last.annotations["leiden"]["gaps"]
  end

  def test_ligature_choice_and_supplied_markup_resolve_to_reading_text
    document = parser.parse(OSCAN_492, urn: "urn:nabu:itant:oscan-492")
    assert_equal 1, document.size
    line = document.first
    assert_equal "urn:nabu:itant:oscan-492:face_a:1", line.urn
    assert_equal "baez. s", line.text,
                 "choice keeps corr (e, not sic v), ligature keeps its letters, the empty <ex/> " \
                 "adds nothing, supplied reads through"
    assert_equal [{ "form" => "baez", "type" => "praenomen" }, { "form" => "s", "type" => "gentilicium" }],
                 line.annotations["words"]
    assert_equal 2, line.annotations["leiden"]["supplied_chars"], "the supplied interpunct + the supplied s"
    assert_equal 1, line.annotations["leiden"]["ligatures"]
  end

  # --- the diplomatic layer ---------------------------------------------------

  def test_lepontic_interpretative_and_diplomatic_layers_are_both_citable
    interpretative = parser.parse(LEPONTIC_1, urn: "urn:nabu:itant:lepontic-1")
    assert_equal ["urn:nabu:itant:lepontic-1:side_a-A:1", "urn:nabu:itant:lepontic-1:side_a-B:2"],
                 interpretative.map(&:urn)
    assert_equal "kuaśoni pala telialui", interpretative.first.text
    assert_equal "akiui piuotialui", interpretative.to_a.last.text
    leiden = interpretative.to_a.last.annotations["leiden"]
    assert_equal 1, leiden["supplied_chars"]
    assert_equal 1, leiden["unclear_chars"]

    diplomatic = parser.parse(LEPONTIC_1, urn: "urn:nabu:itant:lepontic-1-dipl", layer: "diplomatic")
    assert_equal ["urn:nabu:itant:lepontic-1-dipl:side_a-A:1", "urn:nabu:itant:lepontic-1-dipl:side_a-B:2"],
                 diplomatic.map(&:urn)
    assert_equal "kuaśoni:pala:telialui", diplomatic.first.text, "the raw character stream, verbatim"
    assert_equal "akiuip[-]ụotialui", diplomatic.to_a.last.text
    assert_equal({ "layer" => "diplomatic" }, diplomatic.metadata)
    assert_match(/ — diplomatic\z/, diplomatic.title)
  end

  def test_an_oscan_record_has_no_diplomatic_layer
    census = parser.census(OSCAN_2)
    assert census.interpretative
    refute census.diplomatic
    census = parser.census(LEPONTIC_1)
    assert census.interpretative
    assert census.diplomatic
  end

  # --- the metadata-only case -------------------------------------------------

  def test_an_empty_edition_is_censused_uncitable
    census = parser.census(OSCAN_576)
    refute census.interpretative
    refute census.diplomatic
  end

  def test_parse_metadata_only_catalogues_the_lost_inscription
    document = parser.parse_metadata_only(OSCAN_576, urn: "urn:nabu:itant:oscan-576")
    assert_equal 0, document.size
    assert_equal "none", document.metadata["text_layer"]
    assert_equal "170664", document.metadata["tm"]
    assert_includes document.metadata["related"], "imit:aeclanum-13"
  end

  # --- header metadata --------------------------------------------------------

  def test_facets_carry_eagle_genre_aat_object_and_material_and_the_alphabet
    facets = parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-2").metadata["facets"]
    assert_equal({ "value" => "defixio", "raw" => "https://www.eagle-network.eu/voc/typeins/lod/76" },
                 facets["genre"])
    assert_equal({ "value" => "tablet", "raw" => "http://vocab.getty.edu/page/aat/300223016" },
                 facets["object_type"])
    assert_equal({ "value" => "lead", "raw" => "http://vocab.getty.edu/page/aat/300011022" },
                 facets["material"])
    assert_equal "Oscan National alphabet", facets["script"]["value"]
  end

  def test_concordances_mint_tm_and_imit_reference_targets
    metadata = parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-2").metadata
    assert_equal "170774", metadata["tm"]
    assert_equal ["ST Sa 36", "ImIt Bouianum 98", "Murano 6"], metadata["concordances"],
                 "every traditionalID rides verbatim, document order"
    assert_equal ["tm:170774", "imit:bouianum-98"], metadata["related"],
                 "edges mint for the two stable citation spaces the packet names"
  end

  def test_date_reads_the_custom_signed_year_bounds
    date = parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-2").metadata["date"]
    assert_equal(-299, date["not_before"])
    assert_equal(-200, date["not_after"])
    assert_equal "medium", date["cert"]
    assert_equal "3rd century BC", date["raw"]
  end

  def test_place_carries_the_findspot_with_pleiades_and_geonames_refs
    place = parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-2").metadata["place"]
    assert_equal "Aquilonia, Samnium", place["ancient"]
    assert_equal "Monte Vairano (Campobasso)", place["modern"]
    assert_equal "https://pleiades.stoa.org/places/438681", place["pleiades"]
    assert_equal "https://sws.geonames.org/3164966", place["geonames"]
  end

  def test_current_location_and_editors_ride_the_metadata
    metadata = parser.parse(OSCAN_2, urn: "urn:nabu:itant:oscan-2").metadata
    assert_equal "Campobasso", metadata["location"]["settlement"]
    assert_equal "Museo Sannitico", metadata["location"]["institution"]
    assert_equal ["Francesca Murano"], metadata["editors"]
  end

  # --- translations -----------------------------------------------------------

  def test_translations_extract_ita_and_eng_prose_cited_by_textpart_subtype
    translations = parser.translations(LEPONTIC_1)
    assert_equal %w[ita eng], translations.keys
    assert_equal [["text_A", "Pala per Kuaśu figlio di Telios"],
                  ["text_B", "Per Akios, figlio Piuotios"]], translations["ita"]
    assert_equal [["text_A", "Pala for Kuaśu son of Telios"],
                  ["text_B", "For Akios, son of Piuotios"]], translations["eng"]
  end

  def test_translation_divs_without_subtype_cite_by_ordinal
    translations = parser.translations(OSCAN_2)
    assert_equal [["t1", "Pacio Helevio figlio di Trebio | Stazio Betitio [figlio di ...]"]],
                 translations["ita"]
    assert_equal [["t1", "Pacius Helvius son of Trebius | Statius Betitius [son of ...]"]],
                 translations["eng"]
  end

  def test_a_record_with_empty_translation_divs_extracts_none
    assert_empty parser.translations(OSCAN_576)
  end
end
