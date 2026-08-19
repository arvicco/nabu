# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# ReF adapter tests (P80-5): the Reference Corpus of Early New High German
# (1350–1650), v1.0.2 from Zenodo (concept DOI 10.5281/zenodo.5704572 →
# record 5793616), CC BY-SA 4.0 — the first cora-xml registrant. Fixtures
# are four structural trims of real deposit texts (test/fixtures/ref/
# README.md); fetch runs against a WebMock stub of the Zenodo artifact URL
# with the sha pin overridden to the stub tarball's own sha (the rem/iecor
# drill, tar.gz flavor).
class RefTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("ref")

  TAR_URL = "https://zenodo.org/api/records/5793616/files/ReF-v1.0.2.tar.gz/content"

  DOC_URNS = %w[
    urn:nabu:ref:f011
    urn:nabu:ref:f166
    urn:nabu:ref:f240
    urn:nabu:ref:f313
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Ref.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "ref"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_ref_source
    manifest = Nabu::Adapters::Ref.manifest
    assert_equal "ref", manifest.id
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/cc-by-4\.0/, manifest.license,
                 "the Zenodo record-field conflict is recorded honestly in the license text")
    assert_equal "attribution", manifest.license_class
    assert_equal "https://zenodo.org/records/5793616", manifest.upstream_url
    assert_equal "cora-xml", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_text_file
    refs = Nabu::Adapters::Ref.new.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id), "urn = downcased upstream F-sigle, sorted"
    assert(refs.all? { |r| r.source_id == "ref" && r.metadata["language"] == "de" })
  end

  def test_discover_titles_come_from_the_cora_header_name
    titles = Nabu::Adapters::Ref.new.discover(FIXTURES).to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Die Geometria. Deutsch", titles["urn:nabu:ref:f011"]
    assert_equal "Farbrezepte für Garne", titles["urn:nabu:ref:f166"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Ref.new.discover(dir).to_a
    end
  end

  # --- parse: passages --------------------------------------------------------

  def test_parse_mints_one_passage_per_physical_line
    doc = parse("urn:nabu:ref:f011")
    assert_equal 13, doc.passages.size, "the F011 trim keeps page 001r's 13 print lines"
    first = doc.passages.first
    assert_equal "urn:nabu:ref:f011:001r.01", first.urn, "<page><side>.<line label>"
    assert_equal "AUs der geometrey ettliche nuczpere ſtucklē die her", first.text
    assert_equal "de", first.language
  end

  def test_named_columns_join_the_citation
    doc = parse("urn:nabu:ref:f313")
    urns = doc.passages.map(&:urn)
    assert_includes urns, "urn:nabu:ref:f313:003r.19", "unnamed column: folio.line"
    assert_includes urns, "urn:nabu:ref:f313:003va.01", "named column joins the folio"
  end

  def test_upstream_duplicate_line_labels_take_the_house_b2_disambiguator
    doc = parse("urn:nabu:ref:f240")
    urns = doc.passages.map(&:urn)
    assert_includes urns, "urn:nabu:ref:f240:090.08"
    assert_includes urns, "urn:nabu:ref:f240:090.08:b2",
                    "adjacent duplicate labels (censused: 5,729 across 40 files) — " \
                    "never quarantine, never merge"
    assert_equal urns.uniq, urns
  end

  def test_passages_carry_the_token_records
    first = parse("urn:nabu:ref:f011").passages.first
    tokens = first.annotations["tokens"]
    assert_equal "aus", tokens.first["lemma"]
    assert_equal "APPR", tokens.first["pos"]
    assert_equal "manual", tokens.first["anno_type"]
  end

  # --- parse: document metadata ----------------------------------------------

  def test_document_metadata_carries_the_header_lanes
    doc = parse("urn:nabu:ref:f011")
    md = doc.metadata
    assert_equal "F011", md["sigle"]
    assert_equal "ref-mlu", md["subcorpus"], "the deposit directory is the subcorpus"
    assert_equal "ReF.MLU", md["corpus"], "the header's own corpus line, verbatim"
    assert_equal "1487/88", md["date"]
    assert_equal "Regensburg", md["place"]
    assert_equal %w[oberdeutsch ostoberdeutsch nordbairisch], md["dialects"],
                 "the language-type → language-region → language-area chain, coarse to fine"
    assert_equal "Druck", md["medium"]
    refute md.key?("text-place"), "null placeholders never ride"
  end

  def test_shifttag_and_comment_censuses_ride_document_metadata
    f240 = parse("urn:nabu:ref:f240").metadata
    assert_equal({ "lat" => 4 }, f240["shifttags"])
    assert_equal 12, f240["comments"], "swallowed transcriber apparatus is censused, never silent"
    refute parse("urn:nabu:ref:f011").metadata.key?("shifttags"), "empty census stays silent"
  end

  def test_a_non_fnhd_language_header_quarantines_the_document
    Dir.mktmpdir do |dir|
      doctored = File.read(File.join(FIXTURES, "ref-mlu", "F011.xml"))
                     .sub("language: fnhd", "language: nhd")
      FileUtils.mkdir_p(File.join(dir, "ref-mlu"))
      File.write(File.join(dir, "ref-mlu", "F011.xml"), doctored)
      ref = Nabu::Adapters::Ref.new.discover(dir).first
      error = assert_raises(Nabu::ParseError) { Nabu::Adapters::Ref.new.parse(ref) }
      assert_match(/fnhd/, error.message)
    end
  end

  # --- the lemma flow ---------------------------------------------------------

  def test_lemmas_reach_the_passage_lemmas_index_as_silver_for_de
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(slug: "ref", name: "ReF",
                                        adapter_class: "Nabu::Adapters::Ref",
                                        license_class: "attribution")
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(Nabu::Adapters::Ref.new, workdir: FIXTURES, full: true)
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext,
                                  lemma_tiers: registry.lemma_tiers)

    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE].where(lemma_folded: "geometrie").all
    refute_empty rows, "F011's t3 lemma (geometrie) reaches the lemma index"
    assert_includes rows.map { |r| r[:surface_forms] }.join(", "), "geometrey",
                    "attested by the pristine diplomatic surface"
    assert(rows.all? { |r| r[:language] == "de" && r[:tier] == "silver" },
           "largely auto annotation — silver tier (the sources.yml lemma_tier row), " \
           "unlike ReM/ReN's gold")
  ensure
    fulltext&.disconnect
  end

  # --- fetch (the rem/iecor drill, tar.gz flavor) -----------------------------

  def test_fetch_downloads_verifies_the_pin_and_unpacks
    body = tarball_body
    stub_request(:get, TAR_URL)
      .to_return(status: 200, body: body,
                 headers: { "Content-Type" => "application/gzip",
                            "Last-Modified" => "Mon, 20 Dec 2021 14:28:13 GMT" })
    Dir.mktmpdir do |dir|
      adapter = Nabu::Adapters::Ref.new(pin: Digest::SHA256.hexdigest(body))
      report = adapter.fetch(dir)
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert File.exist?(File.join(dir, "ref-mlu", "F011.xml")),
             "the single top dir strips; subcorpus dirs land under the workdir"
      refs = adapter.discover(dir).to_a
      assert_equal ["urn:nabu:ref:f011"], refs.map(&:id)
    end
  end

  def test_fetch_rejects_a_sha_drift_loudly
    body = tarball_body
    stub_request(:get, TAR_URL)
      .to_return(status: 200, body: body,
                 headers: { "Content-Type" => "application/gzip" })
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Ref.new.fetch(dir) }
      assert_match(/pin/, error.message)
      assert_empty Dir.children(dir), "a failed pin never touches the tree"
    end
  end

  # --- helpers ----------------------------------------------------------------

  def parse(urn)
    adapter = Nabu::Adapters::Ref.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    adapter.parse(ref)
  end

  # A real-fixture tarball shaped like the deposit: ReF-v1.0.2/ref-mlu/F011.xml.
  def tarball_body
    Dir.mktmpdir do |staging|
      dir = File.join(staging, "ReF-v1.0.2", "ref-mlu")
      FileUtils.mkdir_p(dir)
      FileUtils.cp(File.join(FIXTURES, "ref-mlu", "F011.xml"), dir)
      tarball = File.join(staging, "ref.tar.gz")
      Nabu::Shell.run("tar", "-czf", tarball, "ReF-v1.0.2", chdir: staging)
      File.binread(tarball)
    end
  end
end
