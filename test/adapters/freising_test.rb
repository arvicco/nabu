# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Freising adapter tests (P13-11): the eZISS TEI P4 critical edition of the
# Brižinski spomeniki under the ND posture — license_class research_private,
# owner-approved 2026-07-11. The fixtures pin the (monument × layer) document
# design: critical transcription = the primary document, diplomatic/phonetic
# + six translations as line-aligned siblings, passage = manuscript line with
# the "BS I, fol. 78r, l. 1" citation. The MCP tests are the packet's
# exclusion EVIDENCE: the real manifest's license_class wired through source
# row → indexer → tools, default-hidden, include_restricted opt-in.
class FreisingTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("freising")

  ZIP_URL = "https://nl.ijs.si/e-zrc/bs-text.zip"

  BS1_FAMILY = %w[
    urn:nabu:freising:bs1
    urn:nabu:freising:bs1-dt
    urn:nabu:freising:bs1-pt
    urn:nabu:freising:bs1-tr-eng
    urn:nabu:freising:bs1-tr-ger
    urn:nabu:freising:bs1-tr-ita
    urn:nabu:freising:bs1-tr-lat
    urn:nabu:freising:bs1-tr-pol
    urn:nabu:freising:bs1-tr-slv
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Freising.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "freising"
  end

  # --- manifest: the ND posture -------------------------------------------------

  def test_manifest_carries_the_by_nd_license_and_research_private_class
    manifest = Nabu::Adapters::Freising.manifest
    assert_equal "freising", manifest.id
    assert_match(/CC BY-ND 2\.5 SI/, manifest.license)
    assert_match(/Priznanje avtorstva-Brez predelav 2\.5 Slovenija/, manifest.license,
                 "the bs.xml <availability> grant, verbatim")
    assert_equal "research_private", manifest.license_class,
                 "ND = private transformation only; never on a redistribution surface"
    assert_equal ZIP_URL, manifest.upstream_url
    assert_equal "freising-tei", manifest.parser_family
  end

  # --- discover: (monument x layer) ---------------------------------------------

  def test_discover_mints_one_ref_per_monument_and_layer
    refs = Nabu::Adapters::Freising.new.discover(FIXTURES).to_a
    assert_equal 27, refs.size, "3 monuments x 9 layers"
    assert_equal BS1_FAMILY, refs.map(&:id).grep(/bs1/),
                 "critical primary + dt/pt/tr siblings, sorted"
    assert(refs.all? { |r| r.source_id == "freising" })
  end

  def test_discover_titles_name_monument_and_layer
    titles = Nabu::Adapters::Freising.new.discover(FIXTURES).to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Brižinski spomeniki I — critical transcription", titles["urn:nabu:freising:bs1"]
    assert_equal "Brižinski spomeniki II — diplomatic transcription", titles["urn:nabu:freising:bs2-dt"]
    assert_equal "Brižinski spomeniki III — English translation", titles["urn:nabu:freising:bs3-tr-eng"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Freising.new.discover(dir).to_a
    end
  end

  # --- parse: the famous opening and the citation design --------------------------

  def test_the_critical_primary_opens_with_glagolite_po_naz_redka_zloueza
    document = parse_urn("urn:nabu:freising:bs1")
    assert_equal "sl", document.language
    opening = document.first
    assert_equal "urn:nabu:freising:bs1:1", opening.urn
    assert_equal "GLAGOLITE PO NAZ REDKA ZLOUEZA:", opening.text
    assert_equal "BS I, fol. 78r, l. 1", opening.annotations["citation"]
    assert_equal "78r", opening.annotations["folio"]
    assert_equal "bsCT.1.001", opening.annotations["tei_id"]
  end

  def test_monument_one_has_38_passages_lines_continuous_across_folios
    document = parse_urn("urn:nabu:freising:bs1")
    assert_equal 38, document.size, "39 manuscript lines minus the empty line 36"
    numbers = document.map { |p| Integer(p.urn.split(":").last, 10) }
    assert_equal (1..39).to_a - [36], numbers
    line25 = document.find { |p| p.urn.end_with?(":25") }
    assert_equal "BS I, fol. 78v, l. 25", line25.annotations["citation"],
                 "the folio turns, the line numbering runs on"
  end

  def test_the_latin_tail_of_bs1_carries_language_lat_per_line
    document = parse_urn("urn:nabu:freising:bs1")
    latin = document.find { |p| p.urn.end_with?(":37") }
    assert_equal "lat", latin.language
    assert latin.text.start_with?("Confitentibus tibi Domine"),
           "the closing Latin prayer inside the sl document"
  end

  def test_the_diplomatic_sibling_is_the_manuscript_witness
    document = parse_urn("urn:nabu:freising:bs1-dt")
    assert_equal "GLAGOLITE PO NAƷ REDKA ZLOUEZA·", document.first.text,
                 "scribal Ʒ and interpunct, not the critical Z and colon"
  end

  def test_the_sl_fold_makes_the_witness_findable_by_modern_spelling
    document = parse_urn("urn:nabu:freising:bs2-dt")
    assert_includes document.first.text, "naſ", "long ſ kept in the pristine text"
    assert_includes document.first.text_normalized, "nas neze",
                    "ſ folds to s in the search form (conventions §9 sl rule)"
  end

  def test_translations_are_line_aligned_siblings
    critical = parse_urn("urn:nabu:freising:bs1")
    english = parse_urn("urn:nabu:freising:bs1-tr-eng")
    assert_equal "eng", english.language
    assert_equal "SAY AFTER US [THESE] FEW WORDS", english.first.text
    assert_equal suffixes(critical), suffixes(english),
                 "identical line keys across layers — suffix-equality alignment needs no stored links"
  end

  def test_monument_two_cites_its_own_folio
    document = parse_urn("urn:nabu:freising:bs2")
    assert_equal "BS II, fol. 158v, l. 1", document.first.annotations["citation"]
  end

  # --- MCP exclusion EVIDENCE (the packet's contract point) -----------------------
  #
  # The real chain, end to end: Freising.manifest.license_class →
  # Store::Source row → Loader → Indexer → MCP::Tools. Verified, not assumed.

  def test_research_private_freising_is_hidden_from_nabu_search_by_default
    with_loaded_corpus do |tools|
      body = JSON.parse(tools.call("nabu_search", { "query" => "glagolite" })[:content][0][:text])
      assert_empty body.fetch("matches"),
                   "the famous opening exists in the index but research_private is default-excluded"
      refute_match(/GLAGOLITE/i, JSON.generate(body.fetch("matches")), "no ND text leaks")
    end
  end

  def test_include_restricted_opts_in_to_the_nd_text_per_call
    with_loaded_corpus do |tools|
      body = JSON.parse(tools.call("nabu_search",
                                   { "query" => "glagolite", "include_restricted" => true })[:content][0][:text])
      urns = body.fetch("matches").map { |h| h.fetch("urn") }
      assert_includes urns, "urn:nabu:freising:bs1:1"
      hit = body.fetch("matches").find { |h| h.fetch("urn") == "urn:nabu:freising:bs1:1" }
      assert_equal "research_private", hit.fetch("license_class"),
                   "the hit names its class so the caller can honor it"
    end
  end

  def test_nabu_show_withholds_the_nd_passage_by_default_and_reveals_on_opt_in
    with_loaded_corpus do |tools|
      withheld = tools.call("nabu_show", { "urn" => "urn:nabu:freising:bs1:1" })
      refute withheld[:isError]
      assert_match(/research_private/, withheld[:content][0][:text])
      refute_match(/GLAGOLITE/, withheld[:content][0][:text], "the text itself does not leak")

      body = JSON.parse(tools.call("nabu_show", { "urn" => "urn:nabu:freising:bs1:1",
                                                  "include_restricted" => true })[:content][0][:text])
      assert_equal "GLAGOLITE PO NAZ REDKA ZLOUEZA:", body.fetch("text")
      assert_equal "research_private", body.fetch("license_class")
    end
  end

  # --- fetch (WebMock only, no network) --------------------------------------------

  def test_fetch_downloads_and_unpacks_the_text_only_zip
    stub_zip
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Freising.new
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 27, adapter.discover(workdir).to_a.size,
                   "the unpacked bs/tei tree is discoverable in place"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Freising.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ------------------------------------------------------

  def test_probe_heads_the_zip_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Freising.remote_probe_strategy
    targets = Nabu::Adapters::Freising.http_probe_targets
    assert_equal 1, targets.size
    assert_equal ZIP_URL, targets[0].zip_url
    assert_nil targets[0].metadata_url, "the license lives inside the TEI header"
  end

  # --- registry round-trip ---------------------------------------------------------------

  def test_registry_resolves_freising_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["freising"]
    refute_nil entry, "freising must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Freising, entry.adapter_class
    refute entry.enabled, "freising stays disabled until the owner-fired first real sync"
    assert_equal Nabu::Adapters::Freising.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Freising.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def suffixes(document)
    document.map { |p| p.urn.split(":").last }
  end

  # Load the whole fixture corpus through the REAL manifest license_class —
  # the wiring under evidence — then hand the MCP tools over.
  def with_loaded_corpus
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(
      slug: "freising", name: "Freising", adapter_class: "Nabu::Adapters::Freising",
      license_class: Nabu::Adapters::Freising.manifest.license_class, enabled: true
    )
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(Nabu::Adapters::Freising.new, workdir: FIXTURES, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
    yield Nabu::MCP::Tools.new(catalog: catalog, fulltext: fulltext)
  ensure
    fulltext&.disconnect
  end

  # Zip the checked-in fixture tree under the upstream's single top dir
  # (bs/, with tei/ inside) and stub the download URL.
  def stub_zip
    Dir.mktmpdir do |dir|
      staging = File.join(dir, "bs", "tei")
      FileUtils.mkdir_p(staging)
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "tei", "*.xml")), staging)
      zip_path = File.join(dir, "bs-text.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "bs", chdir: dir)
      stub_request(:get, ZIP_URL).to_return(
        status: 200, body: File.binread(zip_path),
        headers: { "Content-Type" => "application/zip",
                   "Last-Modified" => "Fri, 06 Apr 2007 12:00:00 GMT" }
      )
    end
  end
end
