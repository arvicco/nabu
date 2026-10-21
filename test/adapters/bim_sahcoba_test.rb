# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# BIM/SAHCOBA adapter tests: the historical Basque corpus (HiTZ, CLARIAH-EUS
# hdl:20.500.14614/43, CC BY 4.0) — one document per work TSV. Fixtures:
# real line windows of four of the deposit's 15 files (Materra's opening
# with its title page and French dedication, a Beriain folio pair with a
# Latin span, Axular's duplicated page 585, Etxepare's opening sentences).
# No network: fetch runs against a WebMock stub of the bitstream URL.
class BimSahcobaTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("bim-sahcoba")
  ZIP_URL = "https://clariah.hitz.eus/server/api/core/bitstreams/ca44acee-b541-458b-a917-fbf5eeb3f71d/content"
  DOC_URNS = %w[urn:nabu:bim-sahcoba:axular urn:nabu:bim-sahcoba:beriain urn:nabu:bim-sahcoba:etxepare
                urn:nabu:bim-sahcoba:materra].freeze

  def conformance_adapter = Nabu::Adapters::BimSahcoba.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "bim-sahcoba"

  def test_manifest_records_the_cc_by_grant_and_credit
    manifest = Nabu::Adapters::BimSahcoba.manifest
    assert_equal "bim-sahcoba", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/Attribution 4\.0 International \(CC BY 4\.0\)/, manifest.license)
    assert_match(%r{doi:10\.71845/hitz-32}, manifest.license)
    assert_equal "bim-tsv", manifest.parser_family
  end

  def test_discover_mints_one_ref_per_work
    assert_equal DOC_URNS, Nabu::Adapters::BimSahcoba.new.discover(FIXTURES).map(&:id)
  end

  def test_every_deposited_work_has_a_works_row
    assert_equal 15, Nabu::Adapters::BimSahcoba::WORKS.size, "the deposit's 15 files"
    skips = Nabu::Adapters::BimSahcoba.new.discovery_skips(FIXTURES)
    assert_equal 0, skips.unrecognized
  end

  def test_an_unknown_work_is_unrecognized_never_dropped
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(FIXTURES, "BZENTROA-BIM", "Materra_automatikoa.tsv"),
                   File.join(dir, "Nobody_automatikoa.tsv"))
      skips = Nabu::Adapters::BimSahcoba.new.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_equal ["work without a WORKS row: nobody"], skips.notes
    end
  end

  def test_a_title_page_imprint_dates_and_places_the_work
    metadata = parse_urn("urn:nabu:bim-sahcoba:materra").metadata
    assert_equal 1623, metadata.dig("date", "not_before")
    assert_match(/\Atitle page: Bordelen/, metadata.dig("date", "raw"))
    assert_equal "Bordeaux", metadata["place"]
    assert_equal "imprint", metadata["place_role"]
    assert_equal "Labourdin", metadata["dialect"]
  end

  def test_an_attributed_date_says_so_and_claims_no_place
    metadata = parse_urn("urn:nabu:bim-sahcoba:etxepare").metadata
    assert_equal({ "not_before" => 1545, "not_after" => 1545 }, metadata["date"].slice("not_before", "not_after"))
    assert_match(/\Aattributed/, metadata.dig("date", "raw"))
    refute metadata.key?("place"), "Etxepare's stream carries no title page"
    assert_equal "Linguae Vasconum Primitiae", parse_urn("urn:nabu:bim-sahcoba:etxepare").title
  end

  def test_passages_are_basque_with_their_tokens
    document = parse_urn("urn:nabu:bim-sahcoba:beriain")
    assert_equal %w[urn:nabu:bim-sahcoba:beriain:p.90v urn:nabu:bim-sahcoba:beriain:p.91r], document.map(&:urn)
    assert(document.all? { |p| p.language == "eu" })
    assert_equal "trabajuetatik", document.first.annotations["tokens"].first["form"]
  end

  def test_fetch_downloads_and_unpacks_the_bitstream
    stub_zip
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::BimSahcoba.new
      assert_match(/\A\h{64}\z/, adapter.fetch(workdir).sha)
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id)
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 404)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { Nabu::Adapters::BimSahcoba.new.fetch(workdir) } }
  end

  def test_registry_resolves_bim_sahcoba_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["bim-sahcoba"]
    refute_nil entry, "bim-sahcoba must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::BimSahcoba, entry.adapter_class
    assert_equal Nabu::Adapters::BimSahcoba.manifest, entry.manifest
    refute entry.wired, "wired: false until the first real sync is verified"
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::BimSahcoba.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # The bitstream zip holds the BZENTROA-BIM/ directory.
  def stub_zip
    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, "BZENTROA-BIM.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "BZENTROA-BIM", chdir: FIXTURES)
      stub_request(:get, ZIP_URL).to_return(status: 200, body: File.binread(zip_path),
                                            headers: { "Content-Type" => "application/zip" })
    end
  end
end
