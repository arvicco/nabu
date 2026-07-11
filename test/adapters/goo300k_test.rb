# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Goo300k adapter tests (P13-9): the gold reference corpus of historical
# Slovene (CLARIN.SI hdl 11356/1025, CC BY 4.0) — Early Modern Slovene print
# from Dalmatin's 1584 Biblia, TEI P5 in the IMP schema, one document per
# root file with xi:included page files. The fixtures pin the orig-canonical
# text policy (Bohorič ſ kept, reg/lemma/MSD as annotations), the
# document-global ab citations, the cross-page part="F" block, and the gold
# lemma flow into passage_lemmas. No network: fetch runs against a WebMock
# stub of the real CLARIN.SI bitstream URL.
class Goo300kTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("goo300k")

  ZIP_URL = "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1025/goo300k-tei.zip"

  DOC_URNS = %w[
    urn:nabu:goo300k:zrc_00001-1584
    urn:nabu:goo300k:zrc_00002-1695
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Goo300k.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "goo300k"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_goo300k_source
    manifest = Nabu::Adapters::Goo300k.manifest
    assert_equal "goo300k", manifest.id
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(/Creative Commons - Attribution 4\.0 International/, manifest.license,
                 "the deposit-page grant, verbatim")
    assert_equal "attribution", manifest.license_class
    assert_equal ZIP_URL, manifest.upstream_url
    assert_equal "imp-tei", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_document_root_file
    refs = Nabu::Adapters::Goo300k.new.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id),
                 "sigil-year identity from the root filename, lowercased, sorted; " \
                 "pages/ and the corpus root never match"
    assert(refs.all? { |r| r.source_id == "goo300k" && r.metadata["language"] == "sl" })
  end

  def test_discover_titles_come_from_the_sourcedesc_bibl
    titles = Nabu::Adapters::Goo300k.new.discover(FIXTURES).to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Biblija (vzorec) — Dalmatin, Jurij, 1584", titles["urn:nabu:goo300k:zrc_00001-1584"]
    assert_equal "Sveti priročnik (vzorec) — Janez Svetokriški, 1695", titles["urn:nabu:goo300k:zrc_00002-1695"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Goo300k.new.discover(dir).to_a
    end
  end

  # --- parse ---------------------------------------------------------------------

  def test_parse_walks_the_included_pages_in_order
    document = parse_urn("urn:nabu:goo300k:zrc_00001-1584")
    assert_equal "sl", document.language
    assert_equal %w[ab.1 ab.2 ab.10], document.map { |p| p.urn.split(":").last },
                 "page 001's ab.1-ab.2 then page 002's ab.10 — document-global upstream ids"
    assert_equal %w[pb.001 pb.001 pb.002], document.map { |p| p.annotations["page"] },
                 "each passage cites its facsimile page"
  end

  def test_passage_text_is_the_historical_orig_surface
    document = parse_urn("urn:nabu:goo300k:zrc_00001-1584")
    demo = document.find { |p| p.urn.end_with?(":ab.2") }
    assert demo.text.start_with?(
      "INu on je ſvoje dvanajſt Iogre k' ſebi poklizal, inu je nym oblaſt dal " \
      "zhes nezhiſte Duhuve, de bi teiſte"
    ), "Dalmatin 1584 in Bohorič orthography, verbatim (canonical means canonical); " \
       "got: #{demo.text[0, 120]}"
  end

  def test_the_sl_fold_makes_bohoric_text_findable_by_modern_spelling
    demo = parse_urn("urn:nabu:goo300k:zrc_00001-1584").find { |p| p.urn.end_with?(":ab.2") }
    assert_includes demo.text_normalized, "svoje dvanajst iogre",
                    "ſ folds to s in the search form (conventions §9 sl rule)"
    refute_includes demo.text_normalized, "ſ"
  end

  def test_gold_tokens_ride_in_annotations
    demo = parse_urn("urn:nabu:goo300k:zrc_00001-1584").find { |p| p.urn.end_with?(":ab.2") }
    jogre = demo.annotations["tokens"].find { |t| t["lemma"] == "joger" }
    assert_equal(
      { "form" => "Iogre", "reg" => "jogre", "lemma" => "joger", "msd" => "Ncm",
        "gloss" => "apostol, učenec", "gloss_bibl" => "[sskj]" },
      jogre, "modernization + gold lemma/MSD + the archaic-vocabulary gloss, # ref prefix stripped"
    )
  end

  def test_a_cross_page_continuation_block_is_its_own_passage
    document = parse_urn("urn:nabu:goo300k:zrc_00001-1584")
    continuation = document.find { |p| p.urn.end_with?(":ab.10") }
    refute_nil continuation, "the part=\"F\" ab on page 002 keeps its own upstream id — never merged"
  end

  # --- the gold lemma flow (owner decision: goo300k feeds the lemma index) ------

  def test_gold_lemmas_reach_the_passage_lemmas_index
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(slug: "goo300k", name: "goo300k",
                                        adapter_class: "Nabu::Adapters::Goo300k",
                                        license_class: "attribution")
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(Nabu::Adapters::Goo300k.new, workdir: FIXTURES, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE].where(lemma_folded: "joger").all
    assert_equal 1, rows.size, "the gold lemma joger (archaic: apostle) is indexed"
    assert_equal "joger", rows[0][:lemma_raw]
    assert_equal "Iogre", rows[0][:surface_forms], "attested by the pristine Bohorič surface"
    assert rows[0][:urn].end_with?(":ab.2")

    folded = fulltext[Nabu::Store::Indexer::LEMMA_TABLE].where(lemma_folded: "svoj").all
    assert_equal %w[ſvoje ſvojga], folded.flat_map { |r| r[:surface_forms].split(", ") }.uniq.sort,
                 "the index folds the lemma, the surface evidence stays pristine (long ſ kept)"
  ensure
    fulltext&.disconnect
  end

  # --- fetch (WebMock only, no network) -------------------------------------------

  def test_fetch_downloads_and_unpacks_the_single_zip
    stub_zip
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Goo300k.new
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id),
                   "the unpacked tree is discoverable in place (single top dir becomes the tree)"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Goo300k.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ----------------------------------------------------

  def test_probe_heads_the_bitstream_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Goo300k.remote_probe_strategy
    targets = Nabu::Adapters::Goo300k.http_probe_targets
    assert_equal 1, targets.size
    assert_equal ZIP_URL, targets[0].zip_url
    assert_nil targets[0].metadata_url, "the license lives on the record page + bundle README"
    assert_equal Nabu::ZipFetch::STATE_FILE, targets[0].state_file
  end

  # --- registry round-trip -------------------------------------------------------------

  def test_registry_resolves_goo300k_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["goo300k"]
    refute_nil entry, "goo300k must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Goo300k, entry.adapter_class
    refute entry.enabled, "goo300k stays disabled until the owner-fired first real sync"
    assert_equal Nabu::Adapters::Goo300k.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Goo300k.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # Zip the checked-in fixture tree under the upstream's single top-level
  # dir (goo300k-tei/) and stub the bitstream URL with the recorded response
  # shape.
  def stub_zip
    Dir.mktmpdir do |dir|
      staging = File.join(dir, "goo300k-tei")
      FileUtils.mkdir_p(staging)
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*.xml")), staging)
      FileUtils.cp_r(File.join(FIXTURES, "pages"), staging)
      zip_path = File.join(dir, "goo300k-tei.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "goo300k-tei", chdir: dir)
      stub_request(:get, ZIP_URL).to_return(
        status: 200, body: File.binread(zip_path),
        headers: { "Content-Type" => "application/zip", "Last-Modified" => "Tue, 05 May 2015 19:13:00 GMT" }
      )
    end
  end
end
