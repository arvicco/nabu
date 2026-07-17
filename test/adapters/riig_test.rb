# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Riig adapter tests (P25-1): discovery over the crawled documents/ tree,
# the -fr translation siblings, the RIG reference-edge targets, and the
# WebMock'd two-stage fetch (corpus map via FileFetch + polite record
# crawl). Includes the shared AdapterConformance suite; fixtures are real
# records (test/fixtures/riig/README.md).
class RiigTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("riig")

  CORPUS_URL = Nabu::Adapters::Riig::CORPUS_URL
  RECORD_IDS = %w[AHP-01-01 ALL-01-01 GAR-10-03 VAU-13-01].freeze

  def conformance_adapter
    # translations: true — the registry row's posture; the -fr siblings must
    # pass conformance too.
    Nabu::Adapters::Riig.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "riig"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_quotes_the_governing_in_file_grant
    manifest = Nabu::Adapters::Riig.manifest
    assert_equal "riig", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/Cette œuvre est mise à disposition/, manifest.license)
    assert_match(/CC BY-NC-ND 4\.0/, manifest.license, "the page-level layer is named, not hidden")
    assert_equal "riig-epidoc", manifest.parser_family
  end

  def test_reference_edges_capability_names_its_own_producer
    assert Nabu::Adapters::Riig.reference_edges?
    assert_equal "riig", Nabu::Adapters::Riig.reference_producer
  end

  def test_remote_probe_heads_the_corpus_map
    targets = Nabu::Adapters::Riig.http_probe_targets
    assert_equal 1, targets.size
    assert_equal CORPUS_URL, targets.first.zip_url
    assert_nil targets.first.metadata_url, "no license endpoint — the grant lives per-record"
    assert_equal Nabu::FileFetch::STATE_FILE, targets.first.state_file
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_original_and_fr_sibling_refs
    refs = Nabu::Adapters::Riig.new(translations: true).discover(FIXTURES).to_a
    assert_equal %w[
      urn:nabu:riig:ahp-01-01 urn:nabu:riig:all-01-01
      urn:nabu:riig:gar-10-03 urn:nabu:riig:gar-10-03-fr
      urn:nabu:riig:vau-13-01 urn:nabu:riig:vau-13-01-fr
    ], refs.map(&:id), "-fr siblings only where the record carries translation prose " \
                       "(AHP-01-01's translation div is empty; ALL-01-01 has none)"
  end

  def test_discover_without_translations_is_originals_only
    refs = Nabu::Adapters::Riig.new.discover(FIXTURES).to_a
    assert_equal 4, refs.size
    refute(refs.any? { |ref| ref.id.end_with?("-fr") })
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Riig.new(translations: true).discover(dir).to_a
    end
  end

  # --- the -fr sibling --------------------------------------------------------

  def test_parse_fr_sibling_mints_french_passages_cited_by_reading
    adapter = Nabu::Adapters::Riig.new(translations: true)
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:riig:vau-13-01-fr" }
    document = adapter.parse(ref)
    assert_equal "fra", document.language
    assert_equal({ "kind" => "translation" }, document.metadata)
    assert_match(/French translation\z/, document.title)
    assert_equal 2, document.size, "one translation div per reading"
    assert_equal %w[urn:nabu:riig:vau-13-01-fr:MLE-a urn:nabu:riig:vau-13-01-fr:PLT-a],
                 document.map(&:urn)
    assert_match(/citoyen de Nîmes/, document.first.text)
  end

  # --- fetch (WebMock; the two-stage crawl) -----------------------------------

  def stub_crawl(map_body:)
    stub_request(:get, CORPUS_URL)
      .to_return(status: 200, body: map_body, headers: { "Last-Modified" => "Thu, 01 Jan 2026 00:00:00 GMT" })
    RECORD_IDS.each do |id|
      stub_request(:get, "#{Nabu::Adapters::Riig::DOCUMENT_BASE_URL}#{id}.xml")
        .to_return(status: 200, body: File.binread(File.join(FIXTURES, "documents", "#{id}.xml")))
    end
  end

  def test_fetch_crawls_the_map_and_every_record
    map_body = File.binread(File.join(FIXTURES, "map", "corpus.html"))
    stub_crawl(map_body: map_body)
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::Riig.new(crawl_delay: 0).fetch(dir)
      assert File.file?(File.join(dir, "map", "corpus.html"))
      RECORD_IDS.each { |id| assert File.file?(File.join(dir, "documents", "#{id}.xml")), "#{id} crawled" }
      assert_match(/documents: 4 fetched, 0 cached \(4 ids\)/, report.notes)
      assert_equal [CORPUS_URL], report.repos.keys
    end
  end

  def test_fetch_is_resumable_an_unchanged_map_skips_cached_records
    map_body = File.binread(File.join(FIXTURES, "map", "corpus.html"))
    stub_crawl(map_body: map_body)
    Dir.mktmpdir do |dir|
      adapter = Nabu::Adapters::Riig.new(crawl_delay: 0)
      adapter.fetch(dir)
      # Second pass: the conditional GET answers 304; records are cached.
      stub_request(:get, CORPUS_URL).to_return(status: 304)
      report = adapter.fetch(dir)
      assert_match(/documents: 0 fetched, 4 cached/, report.notes)
    end
  end

  def test_fetch_with_an_idless_map_aborts_loudly
    stub_request(:get, CORPUS_URL).to_return(status: 200, body: "<html><body>nothing here</body></html>")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Riig.new(crawl_delay: 0).fetch(dir) }
      assert_match(/no record ids found/, error.message)
    end
  end

  # --- registry ---------------------------------------------------------------

  def test_registry_row_is_disabled_manual_with_translations
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["riig"]
    refute_nil entry, "riig must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Riig, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first crawl"
    assert_equal "manual", entry.sync_policy
    assert entry.translations, "-fr siblings ride the registry flag"
  end
end
