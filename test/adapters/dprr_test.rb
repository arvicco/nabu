# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"
require "uri"

# Nabu::Adapters::Dprr: the Digital Prosopography of the Roman Republic
# as a person-authority MODULE (the cbdb shape — zero documents). Fetch
# sends the two adapter SELECTs to the public SPARQL endpoint and lands
# the JSON answers verbatim. No network: WebMock answers with the
# trimmed real fixtures (test/fixtures/dprr/README.md).
class DprrTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("dprr")
  ENDPOINT = Nabu::Adapters::Dprr::ENDPOINT

  def stub_endpoint(persons: File.read(File.join(FIXTURES, "persons.json")),
                    dates: File.read(File.join(FIXTURES, "dates.json")))
    { Nabu::Adapters::Dprr::PERSONS_QUERY => persons, Nabu::Adapters::Dprr::DATES_QUERY => dates }
      .each do |query, body|
      stub_request(:get, ENDPOINT)
        .with(query: { "query" => query },
              headers: { "Accept" => "application/sparql-results+json" })
        .to_return(status: 200, body: body,
                   headers: { "Content-Type" => "application/sparql-results+json" })
    end
  end

  def test_registry_module_row_and_module_shape
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["dprr"]
    refute_nil entry
    assert entry.feature_module?
    refute entry.wired, "wired: false until the first real sync is verified"
    adapter = Nabu::Adapters::Dprr.new
    assert_empty adapter.discover(".").to_a
    ref = Nabu::DocumentRef.new(source_id: "dprr", id: "urn:nabu:dprr:x", path: ".", metadata: {})
    assert_raises(Nabu::ParseError) { adapter.parse(ref) }
  end

  def test_fetch_lands_both_answers_verbatim_with_a_state_pin
    stub_endpoint
    Dir.mktmpdir do |workdir|
      report = Nabu::Adapters::Dprr.new.fetch(workdir)
      assert_equal File.read(File.join(FIXTURES, "persons.json")),
                   File.read(File.join(workdir, Nabu::Adapters::Dprr::PERSONS_FILE))
      assert_equal File.read(File.join(FIXTURES, "dates.json")),
                   File.read(File.join(workdir, Nabu::Adapters::Dprr::DATES_FILE))
      assert_match(/\A\h{64}\z/, report.sha)
      assert_includes report.notes, "4 persons"
      state = JSON.parse(File.read(File.join(workdir, Nabu::Adapters::Dprr::STATE_FILE)))
      assert_equal report.sha, state["sha256"]

      again = Nabu::Adapters::Dprr.new.fetch(workdir)
      assert_equal report.sha, again.sha, "an unchanged answer pins the same identity"
    end
  end

  def test_a_non_results_answer_refuses_and_keeps_nothing
    stub_endpoint(persons: "<html>maintenance</html>")
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Dprr.new.fetch(workdir) }
      assert_match(/not a SPARQL results document/, error.message)
      refute File.exist?(File.join(workdir, Nabu::Adapters::Dprr::PERSONS_FILE))
    end
  end

  def test_an_empty_persons_answer_refuses
    empty = JSON.generate("head" => { "vars" => [] }, "results" => { "bindings" => [] })
    stub_endpoint(persons: empty)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Dprr.new.fetch(workdir) }
      assert_match(/zero persons/, error.message)
    end
  end

  def test_manifest_is_nc_with_the_verified_license
    manifest = Nabu::Adapters::Dprr.manifest
    assert_equal "nc", manifest.license_class
    assert_includes manifest.license, "CC BY-NC 4.0"
    assert_includes manifest.license, "2026-10-27", "the license string records its verification date"
  end

  def test_probe_is_liveness_only_on_the_documentation_page
    assert_equal :http_zip, Nabu::Adapters::Dprr.remote_probe_strategy
    target = Nabu::Adapters::Dprr.http_probe_targets.first
    assert target.liveness_only
    assert_equal "https://romanrepublic.ac.uk/rdf/doc/", target.zip_url
  end
end
