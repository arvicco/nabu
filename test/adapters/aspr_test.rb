# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Aspr adapter tests (P12-2): the Anglo-Saxon Poetic Records — OTA 3009, the
# complete OE poetry corpus as ONE 2.2 MB TEI file — minting one document per
# poem div keyed by its Cameron number (urn:nabu:aspr:A4.1 = Beowulf).
# Includes the shared AdapterConformance suite against the checked-in fixture
# trim (8 of 349 divs; Beowulf lines 1-24). No network: fetch runs against
# WebMock stubs of the real OTA bitstream URL.
class AsprTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("aspr")

  OTA_URL = "https://ota.bodleian.ox.ac.uk/repository/xmlui/bitstream/handle/20.500.12024/3009/3009.xml"

  DOC_URNS = %w[
    urn:nabu:aspr:A3.34.15 urn:nabu:aspr:A3.34.22 urn:nabu:aspr:A4.1 urn:nabu:aspr:A16
    urn:nabu:aspr:A32.1 urn:nabu:aspr:A32.2 urn:nabu:aspr:A43.5 urn:nabu:aspr:A43.10
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Aspr.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "aspr"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_aspr_source
    manifest = Nabu::Adapters::Aspr.manifest
    assert_equal "aspr", manifest.id
    assert_match(/CC BY-SA 3\.0/, manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal OTA_URL, manifest.upstream_url
    assert_equal "aspr", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_poem_in_file_order
    refs = Nabu::Adapters::Aspr.new.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id)
    assert_equal "Beowulf", refs.find { |r| r.id == "urn:nabu:aspr:A4.1" }.metadata["title"]
    assert(refs.all? { |r| r.source_id == "aspr" && r.metadata["language"] == "ang" })
  end

  def test_discover_keeps_the_title_collision_pair_apart
    refs = Nabu::Adapters::Aspr.new.discover(FIXTURES).to_a
    pair = refs.select { |r| r.metadata["title"] == "For Loss of Cattle" }
    assert_equal %w[urn:nabu:aspr:A43.5 urn:nabu:aspr:A43.10], pair.map(&:id),
                 "identical titles, distinct Cameron urns — the title-slug rejection made concrete"
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Aspr.new.discover(dir).to_a
    end
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_round_trips_beowulf_at_line_grain
    adapter = Nabu::Adapters::Aspr.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:aspr:A4.1" }
    document = adapter.parse(ref)
    assert_equal "urn:nabu:aspr:A4.1", document.urn
    assert_equal "ang", document.language
    assert_equal "Beowulf", document.title
    assert_equal 24, document.size
    assert_equal "Hwæt! We Gardena in geardagum,",
                 document.find { |p| p.urn == "urn:nabu:aspr:A4.1:1" }.text
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_downloads_the_file_and_returns_report
    stub_request(:get, OTA_URL).to_return(
      status: 200, body: File.read(File.join(FIXTURES, "3009.xml")),
      headers: { "Last-Modified" => "Fri, 19 Jul 2019 12:07:26 GMT" }
    )
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Aspr.new
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 8, adapter.discover(workdir).count, "the fetched file is discoverable in place"

      stub_request(:get, OTA_URL)
        .with(headers: { "If-Modified-Since" => "Fri, 19 Jul 2019 12:07:26 GMT" })
        .to_return(status: 304)
      assert_equal report.sha, adapter.fetch(workdir).sha, "a 304 keeps the pinned sha"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, OTA_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Aspr.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ------------------------------------------------

  def test_probe_targets_head_the_bitstream_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Aspr.remote_probe_strategy
    targets = Nabu::Adapters::Aspr.http_probe_targets
    assert_equal 1, targets.size
    target = targets.first
    assert_equal OTA_URL, target.zip_url
    assert_nil target.metadata_url, "the license lives IN the fetched file; there is no metadata endpoint"
    assert_equal "", target.state_subdir
    assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
  end

  # --- registry round-trip -------------------------------------------------------

  def test_registry_resolves_aspr_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["aspr"]
    refute_nil entry, "aspr must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Aspr, entry.adapter_class
    assert entry.enabled, "aspr is live (owner sign-off 2026-07-11 after first sync + eyeball)"
    assert_equal Nabu::Adapters::Aspr.manifest, entry.manifest
  end
end
