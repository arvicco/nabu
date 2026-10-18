# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# IgCyprus adapter tests: discovery over the crawled documents/ tree, the
# -transcription / -de sibling layers, the WebMock'd two-stage fetch
# (the IG listing via FileFetch + the polite per-id record crawl), the
# timeline projection and the registry row. Includes the shared
# AdapterConformance suite; fixtures are real records
# (test/fixtures/ig-cyprus/README.md).
class IgCyprusTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("ig-cyprus")

  LISTING_URL = Nabu::Adapters::IgCyprus::LISTING_URL
  RECORD_IDS = ["IG XV 1, 1", "IG XV 1, 5", "IG XV 1, 180", "IG XV 1, 237(I)", "IG XV 1, 254(1)",
                "IG XV 1, 410"].freeze
  STEMS = %w[1 5 180 237-I 254-1 410].freeze

  def conformance_adapter
    Nabu::Adapters::IgCyprus.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "ig-cyprus"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_quotes_the_in_file_grant_and_its_link_back_clause
    manifest = Nabu::Adapters::IgCyprus.manifest
    assert_equal "ig-cyprus", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "Creative Commons Attribution 4.0 International"
    assert_includes manifest.license, "All reuse or distribution of this work must contain somewhere " \
                                      "a link back to this page."
    assert_equal "ig-cyprus-epidoc", manifest.parser_family
  end

  def test_remote_probe_heads_the_listing
    targets = Nabu::Adapters::IgCyprus.http_probe_targets
    assert_equal 1, targets.size
    assert_equal LISTING_URL, targets.first.zip_url
    assert_nil targets.first.metadata_url
    assert_equal Nabu::FileFetch::STATE_FILE, targets.first.state_file
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_records_and_their_citable_layers
    refs = Nabu::Adapters::IgCyprus.new(translations: true).discover(FIXTURES).to_a
    assert_equal %w[
      urn:nabu:ig-cyprus:1 urn:nabu:ig-cyprus:1-de
      urn:nabu:ig-cyprus:180 urn:nabu:ig-cyprus:180-de urn:nabu:ig-cyprus:180-transcription
      urn:nabu:ig-cyprus:237-i urn:nabu:ig-cyprus:237-i-de urn:nabu:ig-cyprus:237-i-transcription
      urn:nabu:ig-cyprus:254-1
      urn:nabu:ig-cyprus:410 urn:nabu:ig-cyprus:410-de urn:nabu:ig-cyprus:410-transcription
      urn:nabu:ig-cyprus:5
    ], refs.map(&:id)
  end

  def test_discover_without_translations_keeps_the_transcription_layer
    refs = Nabu::Adapters::IgCyprus.new.discover(FIXTURES).to_a
    refute(refs.any? { |ref| ref.id.end_with?("-de") }, "German translations ride the registry flag")
    assert_equal 9, refs.size, "6 records + 3 alphabetic transcriptions"
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::IgCyprus.new(translations: true).discover(dir).to_a
    end
  end

  def test_fixture_census
    adapter = Nabu::Adapters::IgCyprus.new(translations: true)
    documents = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }
    base = documents.reject { |d| d.urn.end_with?("-de", "-transcription") }
    assert_equal 36, base.sum(&:size)
    languages = base.flat_map { |d| d.map(&:language) }.tally
    assert_equal({ "ecy-Latn" => 6, "grc" => 10, "grc-Latn" => 20 }, languages)
  end

  # --- fetch (WebMock; the two-stage crawl) -----------------------------------

  def record_url(id)
    Nabu::Adapters::IgCyprus.record_url(id)
  end

  def stub_crawl(listing_body:)
    stub_request(:get, LISTING_URL).to_return(status: 200, body: listing_body)
    RECORD_IDS.zip(STEMS).each do |id, stem|
      stub_request(:get, record_url(id))
        .to_return(status: 200, body: File.binread(File.join(FIXTURES, "documents", "#{stem}.xml")))
    end
  end

  def test_record_urls_encode_the_spaces
    assert_equal "https://telota.bbaw.de/ig/api/xml/IG%20XV%201,%20237(I)", record_url("IG XV 1, 237(I)")
  end

  def test_fetch_crawls_the_fascicle_and_ignores_other_volumes
    stub_crawl(listing_body: File.binread(File.join(FIXTURES, "map", "inscriptions.json")))
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::IgCyprus.new(crawl_delay: 0).fetch(dir)
      assert File.file?(File.join(dir, "map", "inscriptions.json"))
      STEMS.each { |stem| assert File.file?(File.join(dir, "documents", "#{stem}.xml")), "#{stem} crawled" }
      assert_equal STEMS.sort, Dir.children(File.join(dir, "documents")).map { |f| f.delete_suffix(".xml") }.sort,
                   "IG XV 2, 1's ids are never crawled"
      assert_match(/documents: 6 fetched, 0 cached \(6 ids\)/, report.notes)
      assert_equal [LISTING_URL], report.repos.keys
    end
  end

  # Upstream sends no Last-Modified/ETag, so a repeat sync always answers
  # 200: an unchanged listing body (same sha pin) stands in for the 304.
  def test_fetch_is_resumable_an_unchanged_listing_skips_cached_records
    stub_crawl(listing_body: File.binread(File.join(FIXTURES, "map", "inscriptions.json")))
    Dir.mktmpdir do |dir|
      adapter = Nabu::Adapters::IgCyprus.new(crawl_delay: 0)
      adapter.fetch(dir)
      File.delete(File.join(dir, "documents", "410.xml"))
      report = adapter.fetch(dir)
      assert_match(/documents: 1 fetched, 5 cached/, report.notes)
    end
  end

  def test_fetch_on_a_304_skips_cached_records
    stub_crawl(listing_body: File.binread(File.join(FIXTURES, "map", "inscriptions.json")))
    Dir.mktmpdir do |dir|
      adapter = Nabu::Adapters::IgCyprus.new(crawl_delay: 0)
      adapter.fetch(dir)
      stub_request(:get, LISTING_URL).to_return(status: 304)
      report = adapter.fetch(dir)
      assert_match(/documents: 0 fetched, 6 cached/, report.notes)
    end
  end

  def test_fetch_with_a_changed_listing_recrawls
    listing = File.binread(File.join(FIXTURES, "map", "inscriptions.json"))
    stub_crawl(listing_body: listing)
    Dir.mktmpdir do |dir|
      adapter = Nabu::Adapters::IgCyprus.new(crawl_delay: 0)
      adapter.fetch(dir)
      stub_request(:get, LISTING_URL).to_return(status: 200, body: listing.sub('"IG XV 2, 2"', '"IG XV 2, 3"'))
      report = adapter.fetch(dir)
      assert_match(/documents: 6 fetched, 0 cached/, report.notes)
    end
  end

  def test_fetch_without_the_fascicle_key_aborts_loudly
    stub_request(:get, LISTING_URL).to_return(status: 200, body: '{"IG XV 2, 1 || Zypern":["IG XV 2, 1"]}')
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::IgCyprus.new(crawl_delay: 0).fetch(dir) }
      assert_match(/no "IG XV 1, 1 \|\|" fascicle key/, error.message)
    end
  end

  def test_fetch_with_an_empty_fascicle_aborts_loudly
    stub_request(:get, LISTING_URL).to_return(status: 200, body: '{"IG XV 1, 1 || Zypern: Syllabarinschriften":[]}')
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::IgCyprus.new(crawl_delay: 0).fetch(dir) }
      assert_match(/no record ids/, error.message)
    end
  end

  def test_fetch_refuses_an_id_outside_the_censused_shape
    body = '{"IG XV 1, 1 || Zypern: Syllabarinschriften":["IG XV 1, 1","IG XV 1, 12a"]}'
    stub_request(:get, LISTING_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::IgCyprus.new(crawl_delay: 0).fetch(dir) }
      assert_match(/IG XV 1, 12a/, error.message)
    end
  end

  def test_a_failed_record_get_aborts_the_crawl
    stub_request(:get, LISTING_URL)
      .to_return(status: 200, body: '{"IG XV 1, 1 || Zypern: Syllabarinschriften":["IG XV 1, 1"]}')
    stub_request(:get, record_url("IG XV 1, 1")).to_return(status: 500, body: "Server Error")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::IgCyprus.new(crawl_delay: 0).fetch(dir) }
      assert_match(/HTTP 500/, error.message)
      refute File.exist?(File.join(dir, "documents", "1.xml")), "no partial record is left behind"
    end
  end

  # --- timeline projection ------------------------------------------------------

  def test_structured_dates_project_bce_onto_the_timeline
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["ig-cyprus"]
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "ig-cyprus", name: "IG XV 1,1",
                                        adapter_class: "Nabu::Adapters::IgCyprus", license_class: "attribution")
    Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
    Nabu::Store::TimelineBuilder::MetadataDates.refresh_source!(catalog: db, slug: "ig-cyprus")
    doc_id = db[:documents].where(urn: "urn:nabu:ig-cyprus:1").get(:id)
    row = db[:document_axes].where(document_id: doc_id).first
    assert_equal(-330, row[:not_before])
    assert_equal(-310, row[:not_after])
    assert_equal "Amathus", row[:place_name]
    assert_equal 6, db[:document_axes].where(axis_source: "ig-cyprus").count, "siblings never row"
  end

  def test_load_twice_is_idempotent
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "ig-cyprus", name: "IG XV 1,1",
                                        adapter_class: "Nabu::Adapters::IgCyprus", license_class: "attribution")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
    assert_equal 13, first.added
    passages = db[:passages].count
    second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
    assert_equal 13, second.skipped
    assert_equal passages, db[:passages].count
  end

  # --- registry ---------------------------------------------------------------

  def test_registry_row_is_unwired_manual_with_its_layers
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ig-cyprus"]
    refute_nil entry, "ig-cyprus must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::IgCyprus, entry.adapter_class
    refute entry.wired, "flips after the first real sync is verified"
    assert_equal "manual", entry.sync_policy
    assert entry.translations
    assert_equal %w[epigraphy classical], entry.axes
  end
end
