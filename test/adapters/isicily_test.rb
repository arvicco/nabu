# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# I.Sicily adapter tests (P29-4, siblings P34-0): discovery over the
# cloned inscriptions/ tree, the isicily-epidoc line grain (textpart
# paths, break="no", the kept bare <orig>, the metadata-only records),
# the lemma-layer words annotations, the concordance reference-edge
# targets, the honest language mapping, and the -translit/-en/-it
# sibling minting. Includes the shared AdapterConformance suite;
# fixtures are 12 whole real records (test/fixtures/isicily/README.md).
class IsicilyTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("isicily")

  # Plain (translations-off) discovery: the base records + the ungated
  # -translit layer siblings (the itant -dipl stance), never -en/-it.
  ALL_URNS = %w[
    urn:nabu:isicily:isic000001 urn:nabu:isicily:isic000006
    urn:nabu:isicily:isic000451 urn:nabu:isicily:isic000764
    urn:nabu:isicily:isic001510 urn:nabu:isicily:isic001620
    urn:nabu:isicily:isic001895 urn:nabu:isicily:isic002954
    urn:nabu:isicily:isic003360 urn:nabu:isicily:isic003360-translit
    urn:nabu:isicily:isic003475 urn:nabu:isicily:isic020002
    urn:nabu:isicily:isic020307 urn:nabu:isicily:isic020307-translit
  ].freeze

  # The -en/-it siblings a translations-on discovery adds (the six
  # fixtures with NON-EMPTY en prose; only ISic000006 carries it prose —
  # comment-only divs mint nothing).
  TRANSLATION_URNS = %w[
    urn:nabu:isicily:isic000001-en urn:nabu:isicily:isic000006-en
    urn:nabu:isicily:isic000006-it urn:nabu:isicily:isic000451-en
    urn:nabu:isicily:isic001620-en urn:nabu:isicily:isic001895-en
    urn:nabu:isicily:isic003475-en
  ].freeze

  def conformance_adapter
    # translations: true — the registry row's posture (P34-0); the
    # -en/-it/-translit siblings must satisfy the same contract.
    Nabu::Adapters::Isicily.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "isicily"
  end

  # ISic020002's primary edition holds only <note>traces</note> — a
  # catalogued monument with no citable text, marked by the parser itself
  # (the ogham/local-library text_layer:none precedent), never a blanket
  # override.
  def conformance_metadata_only?(document)
    document.metadata["text_layer"] == "none"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_names_the_three_concordant_license_layers
    manifest = Nabu::Adapters::Isicily.manifest
    assert_equal "isicily", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(/licence\.txt/, manifest.license, "the repo-level grant is named")
    assert_match(/Creative Commons-Attribution 4\.0 licence/, manifest.license,
                 "the per-record <licence> text is quoted verbatim")
    assert_equal "isicily-epidoc", manifest.parser_family
    assert_equal "https://github.com/ISicily/ISicily", manifest.upstream_url
  end

  def test_remote_probe_is_the_git_default_over_the_repo_url
    assert_equal :git, Nabu::Adapters::Isicily.remote_probe_strategy
    assert_equal ["https://github.com/ISicily/ISicily"], Nabu::Adapters::Isicily.upstream_repo_urls
  end

  def test_reference_edges_capability_names_its_own_producer
    assert Nabu::Adapters::Isicily.reference_edges?
    producer = Nabu::Adapters::Isicily.reference_producer(catalog: nil, journal: nil)
    assert_instance_of Nabu::LibraryReferences, producer
    assert_equal "isicily", producer.producer
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_inscription_file_sorted
    refs = Nabu::Adapters::Isicily.new.discover(FIXTURES).to_a
    assert_equal ALL_URNS, refs.map(&:id)
  end

  def test_discover_with_translations_adds_the_en_and_it_siblings
    refs = Nabu::Adapters::Isicily.new(translations: true).discover(FIXTURES).to_a
    assert_equal (ALL_URNS + TRANSLATION_URNS).sort, refs.map(&:id),
                 "non-empty en/it prose mints a sibling ref; comment-only and lang-less " \
                 "translation divs mint nothing"
  end

  def test_discover_ignores_non_record_files_in_inscriptions
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "inscriptions"))
      FileUtils.cp(File.join(FIXTURES, "inscriptions", "ISic000001.xml"),
                   File.join(dir, "inscriptions", "ISic000001.xml"))
      # The repo keeps an Oxygen project file and a schema beside the
      # records (census 2026-07-18: ISicily.xpr, tei-epidoc.rng).
      File.write(File.join(dir, "inscriptions", "ISicily.xpr"), "<project/>")
      File.write(File.join(dir, "inscriptions", "tei-epidoc.rng"), "<grammar/>")
      refs = Nabu::Adapters::Isicily.new.discover(dir).to_a
      assert_equal ["urn:nabu:isicily:isic000001"], refs.map(&:id)
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Isicily.new.discover(dir).to_a
    end
  end

  # --- line grain -------------------------------------------------------------

  def test_parses_the_zethus_epitaph_lines_with_interpuncts
    document = parse("urn:nabu:isicily:isic000001")
    assert_equal "lat", document.language
    assert_equal "Funerary inscription of Zethus", document.title
    assert_equal %w[
      urn:nabu:isicily:isic000001:1
      urn:nabu:isicily:isic000001:2
      urn:nabu:isicily:isic000001:3
    ], document.map(&:urn)
    assert_equal "Dis · manibus", document.first.text,
                 "interpunct <g> keeps its text; expan reads expanded"
    assert_equal "vixit · annis · VI", document.to_a.last.text
  end

  def test_choice_keeps_reg_and_a_self_closed_g_contributes_nothing
    document = parse("urn:nabu:isicily:isic000451")
    assert_equal ["hic positus est Euplus", "in pace qui vixit annu", "s cinque"],
                 document.map(&:text),
                 "choice/orig/reg reads reg (ic→hic); <g ref=\"#ivy-leaf\"/> is empty and vanishes; " \
                 "the lb break=\"no\" INSIDE the kept reg branch still delimits lines (annu|s)"
  end

  def test_textparts_path_the_urns_and_restart_line_numbers
    document = parse("urn:nabu:isicily:isic001895")
    assert_equal %w[
      urn:nabu:isicily:isic001895:1:1
      urn:nabu:isicily:isic001895:2:1
    ], document.map(&:urn), "line numbers restart per textpart section — the path disambiguates"
    assert_equal %w[Κοισύρα Κοισύρα], document.map(&:text)
  end

  def test_bare_orig_outside_choice_is_kept_sicel_reading_text
    document = parse("urn:nabu:isicily:isic002954")
    assert_equal 1, document.size
    passage = document.first
    assert_equal "[…]ΥΡΙΕΙΑΙΡ[…]Ι[…]", passage.text,
                 "a bare <orig> is the letters-only edited text of the Sicel corpus — dropping " \
                 "it would erase the record; gaps fuse as single markers"
    assert_equal 3, passage.annotations["leiden"]["gaps"].size
    assert_equal 3, passage.annotations["leiden"]["unclear_chars"]
  end

  def test_supplied_reads_through_and_counts
    document = parse("urn:nabu:isicily:isic000764")
    assert_equal "Hic requiescit", document.first.text
    assert_equal 13, document.first.annotations["leiden"]["supplied_chars"],
                 "non-whitespace graphemes of \"Hic requiescit\" — the letters a print edition's " \
                 "brackets would enclose"
  end

  # --- languages (script honesty) ---------------------------------------------

  def test_document_language_maps_the_main_lang_honestly
    assert_equal "xpu", parse("urn:nabu:isicily:isic001510").language
    assert_equal "osc", parse("urn:nabu:isicily:isic001620").language
    assert_equal "grc", parse("urn:nabu:isicily:isic003475").language
  end

  def test_passage_language_is_the_edition_divs_with_script_subtag
    mamertine = parse("urn:nabu:isicily:isic001620")
    assert_equal ["osc-Grek"], mamertine.map(&:language).uniq,
                 "Mamertine Oscan is carved in Greek script — the edition div's xml:lang carries " \
                 "the honest subtag and the passages keep it"
    assert_match(/μεδδειξ ουπσενσ/, mamertine.to_a[2].text)
    sicel = parse("urn:nabu:isicily:isic002954")
    assert_equal ["scx-Grek"], sicel.map(&:language).uniq
  end

  # --- the lemma layer --------------------------------------------------------

  def test_simple_lemmatized_layer_joins_words_by_n_onto_lines
    document = parse("urn:nabu:isicily:isic000001")
    assert_equal [
      { "form" => "Dis", "n" => "5", "lemma" => "Deus" },
      { "form" => "manibus", "n" => "15", "lemma" => "manes" }
    ], document.first.annotations["words"]
    assert_equal [
      { "form" => "vixit", "n" => "30", "lemma" => "vivo" },
      { "form" => "annis", "n" => "40", "lemma" => "annus" },
      { "form" => "VI", "n" => "50", "lemma" => "VI" }
    ], document.to_a.last.annotations["words"]
  end

  def test_greek_lemma_layer_joins_too
    document = parse("urn:nabu:isicily:isic003475")
    assert_equal [
      { "form" => "Μέλισα", "n" => "5", "lemma" => "Μέλισσα" },
      { "form" => "Ζωπύρου", "n" => "10", "lemma" => "Ζώπυρος" }
    ], document.first.annotations["words"]
  end

  def test_a_record_without_a_lemma_layer_carries_no_words_annotation
    document = parse("urn:nabu:isicily:isic000764")
    assert(document.none? { |passage| passage.annotations.key?("words") })
  end

  # --- metadata-only records (the 759-record corpus shape) --------------------

  def test_a_note_only_edition_parses_to_a_metadata_only_document
    document = parse("urn:nabu:isicily:isic020002")
    assert_equal 0, document.size, "the Elymian record's edition holds only <note>traces</note>"
    assert_equal "none", document.metadata["text_layer"]
    assert_equal "xly", document.language
    assert_equal({ "not_before" => -500, "not_after" => -480,
                   "raw" => "500—480 BCE",
                   "evidence" => "archaeological-context material-context lettering" },
                 document.metadata["date"], "the axis-bearing header still rides")
    assert_equal "Segesta", document.metadata.dig("place", "ancient")
    assert_equal "https://pleiades.stoa.org/places/462487", document.metadata.dig("place", "ancient_ref")
  end

  # --- header metadata --------------------------------------------------------

  def test_facets_carry_the_eagle_terms_with_their_vocabulary_refs
    metadata = parse("urn:nabu:isicily:isic000001").metadata
    assert_equal "funerary", metadata.dig("facets", "genre", "value")
    assert_equal "https://ontology.inscriptiones.org/type_of_inscription/Funerary",
                 metadata.dig("facets", "genre", "raw")
    assert_equal "marble", metadata.dig("facets", "material", "value")
    assert_equal "plaque", metadata.dig("facets", "object_type", "value")
  end

  def test_date_and_place_ride_as_document_metadata
    metadata = parse("urn:nabu:isicily:isic000001").metadata
    assert_equal({ "not_before" => 51, "not_after" => 300,
                   "raw" => "between later 1st and 3rd century CE",
                   "evidence" => "lettering textual-context" }, metadata["date"])
    assert_equal({ "region" => "Sicilia", "modern" => "Caltanissetta",
                   "modern_ref" => "http://sws.geonames.org/2525448",
                   "geo" => "37.49025, 14.06216" }, metadata["place"],
                 "the empty ancient placeName is an honest absence; geo stays verbatim")
  end

  def test_bce_dates_are_signed_years
    metadata = parse("urn:nabu:isicily:isic001510").metadata
    assert_equal(-600, metadata.dig("date", "not_before"))
    assert_equal(-401, metadata.dig("date", "not_after"))
  end

  # --- concordances → reference edges -----------------------------------------

  def test_concordances_ride_as_metadata_and_related_edge_targets
    metadata = parse("urn:nabu:isicily:isic000001").metadata
    assert_equal "491696", metadata["tm"]
    assert_equal "21900531", metadata["edcs"]
    assert_nil metadata["edr"], "empty idno elements are honest absences"
    assert_nil metadata["phi"]
    assert_equal "10.5281/zenodo.4333721", metadata["doi"]
    assert_equal %w[tm:491696 edcs:21900531], metadata["related"]
  end

  def test_an_edh_concordance_mints_a_cross_catalog_urn_target
    metadata = parse("urn:nabu:isicily:isic000764").metadata
    assert_equal "015282", metadata["edh"]
    assert_includes metadata["related"], "urn:nabu:edh:hd015282",
                    "the EDH concordance resolves INSIDE the catalog once EDH is synced — " \
                    "the provenance-distinct-witness link, not a dedup"
    assert_equal %w[tm:175800 edr:081543 urn:nabu:edh:hd015282 edcs:06100293],
                 metadata["related"]
  end

  # --- the -translit layer sibling (P34-0) ------------------------------------

  def test_transliteration_edition_mints_a_translit_sibling_line_for_line
    document = parse("urn:nabu:isicily:isic003360")
    sibling = parse("urn:nabu:isicily:isic003360-translit")
    assert_equal "scx", sibling.language,
                 "the sibling document keeps the record's mainLang identity, like its base"
    assert_equal ["urn:nabu:isicily:isic003360-translit:1"], sibling.map(&:urn),
                 "line suffixes mirror the primary edition's — suffix-equality --parallel"
    assert_equal ["scx-Latn"], sibling.map(&:language).uniq,
                 "the transliteration div's own xml:lang rides the passages"
    assert_equal(document.map { |p| p.urn.delete_prefix(document.urn) },
                 sibling.map { |p| p.urn.delete_prefix(sibling.urn) })
    assert_match(/RAROTA/, sibling.first.text)
    assert_equal "transliteration", sibling.metadata["layer"]
    assert_match(/transliteration/, sibling.title.to_s)
  end

  def test_partial_transliteration_keeps_only_its_own_lines
    sibling = parse("urn:nabu:isicily:isic020307-translit")
    assert_equal ["urn:nabu:isicily:isic020307-translit:2"], sibling.map(&:urn),
                 "upstream transliterated only line 2 of 1-2 — line 1 stays honestly absent"
    assert_equal "mchacnem", sibling.first.text
    assert_equal ["xly-Latn"], sibling.map(&:language).uniq
  end

  def test_records_without_a_citable_transliteration_mint_no_translit_ref
    refs = Nabu::Adapters::Isicily.new.discover(FIXTURES).to_a
    refute_includes refs.map(&:id), "urn:nabu:isicily:isic000001-translit",
                    "no transliteration edition, no sibling"
  end

  # --- the -en/-it translation siblings (P34-0) -------------------------------

  def test_en_translation_parses_with_the_whole_text_corresp_anchor
    document = parse("urn:nabu:isicily:isic000006-en")
    assert_equal "eng", document.language
    assert_equal "Funerary inscription for Gaius Iulius Felix and Appuleia Rogata — " \
                 "English translation", document.title
    assert_equal ["urn:nabu:isicily:isic000006-en:p1"], document.map(&:urn)
    assert_equal "Gaius Iulis Felix lived for [--] years. Appuleia Rogata lived for [--] years",
                 document.first.text
    assert_equal "1", document.first.annotations["corresp"],
                 "the whole-text prose anchors at the primary's first line — coarse-block " \
                 "honesty (the ETCSL corresp mechanism), never per-line invention"
    assert_equal "translation", document.metadata["kind"]
  end

  def test_it_translation_parses_beside_the_en_one
    document = parse("urn:nabu:isicily:isic000006-it")
    assert_equal "ita", document.language
    assert_match(/Italian translation/, document.title)
    assert_equal "Gaio Giulio Felice visse anni [--]. Appuleia Rogata visse anni [--]",
                 document.first.text
    assert_equal "1", document.first.annotations["corresp"]
  end

  def test_multi_paragraph_translation_anchors_only_its_first_paragraph
    document = parse("urn:nabu:isicily:isic001620-en")
    assert_equal %w[
      urn:nabu:isicily:isic001620-en:p1
      urn:nabu:isicily:isic001620-en:p2
    ], document.map(&:urn), "the Latinised re-rendering is a second paragraph"
    assert_equal "1", document.first.annotations["corresp"]
    refute document.to_a.last.annotations.key?("corresp"),
           "later paragraphs carry NO invented alignment — they fall honestly one-sided"
  end

  # --- identity ---------------------------------------------------------------

  def test_urn_mismatch_is_a_parse_error
    parser = Nabu::Adapters::IsicilyEpidocParser.new
    error = assert_raises(Nabu::ParseError) do
      parser.parse(File.join(FIXTURES, "inscriptions", "ISic000001.xml"),
                   urn: "urn:nabu:isicily:isic999999")
    end
    assert_match(/urn mismatch/, error.message)
  end

  private

  def parse(urn)
    # translations on so the -en/-it sibling refs resolve; base + -translit
    # refs are identical either way.
    adapter = Nabu::Adapters::Isicily.new(translations: true)
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "no ref #{urn}"
    adapter.parse(ref)
  end
end
