# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The LexLep inscription adapter (P29-3): Vienna-wiki family, fixtures =
# real api.php page envelopes retrieved 2026-07-18 (see the fixture
# README). Conformance suite + the source-specific pins: the reading
# grammar's rendered forms byte-verbatim, the object/site join, the
# metadata-only bead, the license conflict, and the WikiFetch path.
class LexlepTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("lexlep")

  def conformance_adapter
    Nabu::Adapters::Lexlep.new(delay: 0)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "lexlep"
  end

  def conformance_metadata_only?(document)
    document.metadata["text_layer"] == "none"
  end

  def adapter = conformance_adapter

  def parse_urn(urn)
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # --- manifest: the license conflict held at the restrictive reading -------

  def test_manifest_quotes_all_license_layers_and_holds_nc
    manifest = adapter.manifest
    assert_equal "nc", manifest.license_class
    assert_match(/scientific use only/, manifest.license)
    assert_match(/Creative Commons Attribution-ShareAlike 3\.0/, manifest.license)
    assert_match(/GNU Free Documentation License/, manifest.license)
    assert_match(/NonCommercial/, manifest.license, "the footer's BY-NC-SA layer is quoted too")
    assert_match(/relabel-on-reply/, manifest.license)
    assert_equal "wiki-template", manifest.parser_family
  end

  # --- discovery ------------------------------------------------------------

  def test_lepontic_maps_to_xlp_never_lepcha
    # Review pin (P29-3 merge): ISO 639-3 "lep" is Lepcha (Sino-Tibetan);
    # Lepontic is "xlp". The packet spec's "lep" slip must never ship —
    # the itant packet caught it independently (its upstream even tags
    # Lepontic as Cisalpine Gaulish xcg).
    assert_equal "xlp", Nabu::Adapters::Lexlep::LANGUAGE_MAP.fetch("Lepontic")
  end

  def test_discover_yields_one_ref_per_inscription_page
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[urn:nabu:lexlep:ao-1.1 urn:nabu:lexlep:be-1 urn:nabu:lexlep:bg-1 urn:nabu:lexlep:bi-8],
                 refs.map(&:id)
  end

  def test_discover_marks_the_unreadable_bead_metadata_only
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "urn:nabu:lexlep:be-1" }
    assert_equal "metadata_only", ref.metadata["kind"],
                 "BE·1's reading is 'unknown' — no passage to mint"
  end

  def test_discover_resolves_the_object_and_site_join_paths
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "urn:nabu:lexlep:ao-1.1" }
    assert ref.metadata["object_path"]&.end_with?("AO%C2%B71%20Aosta.json")
    assert ref.metadata["site_path"]&.end_with?("Aosta.json")
  end

  # --- parse: the reading grammar, byte-pinned ------------------------------

  def test_ao_1_1_parses_to_its_two_letter_reading
    document = parse_urn("urn:nabu:lexlep:ao-1.1")
    assert_equal "cel", document.language, "language=Celtic maps to the ISO 639-5 collective"
    assert_equal ["ap"], document.map(&:text)
    assert_equal "AO·1.1", document.title
  end

  def test_bg_1_renders_the_display_form_with_decoded_entities
    document = parse_urn("urn:nabu:lexlep:bg-1")
    assert_equal "und", document.language, "language=unknown reads und"
    assert_equal ["]?ume"], document.map(&:text)
    assert_equal "unknown", document.metadata["language_raw"]
  end

  def test_bi_8_renders_gaps_and_keeps_word_links
    document = parse_urn("urn:nabu:lexlep:bi-8")
    passage = document.first
    assert_equal "sipiu koil[ ]ios", passage.text
    assert_equal %w[sipiu koilios koilios], passage.annotations["words"],
                 "fragment tokens link their Word page (the lexicon join surface)"
  end

  def test_be_1_is_catalogued_metadata_only_never_quarantined
    document = parse_urn("urn:nabu:lexlep:be-1")
    assert_empty document.to_a
    assert_equal "none", document.metadata["text_layer"]
    assert_equal "BE·1 Münsingen", document.metadata["object"]
  end

  # --- parse: object/site join, facets, place, concordances -----------------

  def test_object_join_yields_facets_and_place
    metadata = parse_urn("urn:nabu:lexlep:ao-1.1").metadata
    assert_equal({ "value" => "bowl", "raw" => "bowl" }, metadata["facets"]["object_type"])
    assert_equal({ "value" => "pottery", "raw" => "pottery" }, metadata["facets"]["material"])
    assert_equal "Aosta", metadata["place"]["site"]
    assert_equal "Italy", metadata["place"]["country"]
    assert_equal "45.7437183", metadata["place"]["coordinate_n"],
                 "the object page's findspot coordinates win over the site's"
  end

  def test_genre_facet_rides_type_inscription
    metadata = parse_urn("urn:nabu:lexlep:bi-8").metadata
    assert_equal "funerary", metadata["facets"]["genre"]["value"]
  end

  def test_missing_object_page_is_an_honest_absence
    metadata = parse_urn("urn:nabu:lexlep:bi-8").metadata
    assert_equal "BI·8 Cerrione", metadata["object"]
    assert_nil metadata["place"], "BI·8's object page is not in the fixture set — no invented place"
  end

  def test_concordances_become_related_keys
    metadata = parse_urn("urn:nabu:lexlep:bg-1").metadata
    assert_equal ["morandi:211", "solinas:33"], metadata["related"].sort
  end

  def test_reference_edges_flag_and_producer
    assert Nabu::Adapters::Lexlep.reference_edges?
  end

  # --- fetch (WebMock; the WikiFetch two-stage crawl) -----------------------

  def test_fetch_crawls_categories_and_reports
    api = "https://lexlep.univie.ac.at/api.php"
    stub_request(:get, api)
      .with(query: hash_including("generator" => "categorymembers"))
      .to_return(status: 200, body: JSON.generate(
        { "query" => { "pages" => { "1" => { "pageid" => 1, "ns" => 0, "title" => "AO·1.1",
                                             "lastrevid" => 11 } } } }
      ))
    stub_request(:get, api)
      .with(query: hash_including("prop" => "revisions"))
      .to_return(status: 200, body: JSON.generate(
        { "query" => { "pages" => { "1" => {
          "pageid" => 1, "ns" => 0, "title" => "AO·1.1",
          "revisions" => [{ "revid" => 11, "timestamp" => "2026-07-18T12:00:00Z",
                            "slots" => { "main" => { "*" => "{{inscription\n|reading=ap\n}}" } } }]
        } } } }
      ))

    Dir.mktmpdir do |dir|
      report = adapter.fetch(dir)
      assert_match(/fetched/, report.notes)
      assert File.file?(File.join(dir, "pages", "Inscription", "AO%C2%B71.1.json"))
      # All three categories crawled through one member stub.
      assert_requested :get, api, query: hash_including("gcmtitle" => "Category:Object"), times: 1
      assert_requested :get, api, query: hash_including("gcmtitle" => "Category:Site"), times: 1
    end
  end

  def test_fetch_wraps_wiki_errors_as_fetch_errors
    stub_request(:get, "https://lexlep.univie.ac.at/api.php")
      .with(query: hash_including("generator" => "categorymembers"))
      .to_return(status: 503)
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
    end
  end
end
