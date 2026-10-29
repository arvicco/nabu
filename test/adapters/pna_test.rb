# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

# Nabu::Adapters::Pna: the PNA network dataset (Jauhiainen & Alstola
# 2022, Zenodo 10.5281/zenodo.6220409 v3) as a person-authority MODULE
# (the cbdb/dprr shape — zero documents). Fetch GETs the record's three
# files and lands them verbatim behind hard sha256 pins. No network:
# WebMock answers with zips re-packed from the trimmed real fixtures
# (test/fixtures/pna/README.md), the pins overridden to match.
class PnaTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("pna")
  Pna = Nabu::Adapters::Pna

  def bodies
    @bodies ||= PnaFixtureZips.bodies(FIXTURES)
  end

  def pins
    bodies.transform_values { |bytes| Digest::SHA256.hexdigest(bytes) }
  end

  def stub_record(overrides = {})
    bodies.merge(overrides).each do |name, bytes|
      stub_request(:get, Pna.file_url(name)).to_return(status: 200, body: bytes)
    end
  end

  def test_registry_module_row_and_module_shape
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["pna"]
    refute_nil entry
    assert entry.feature_module?
    assert entry.wired, "wired 2026-10-28: first sync verified on census (17,387 persons)"
    adapter = Pna.new
    assert_empty adapter.discover(".").to_a
    ref = Nabu::DocumentRef.new(source_id: "pna", id: "urn:nabu:pna:x", path: ".", metadata: {})
    assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    assert Pna.person_index_producer?
    assert_equal "pna", Pna.person_index_producer(catalog: nil).authority
  end

  def test_the_record_files_are_pinned_on_the_third_zenodo_version
    assert_equal %w[Networks.zip SupplementaryData.zip README.txt], Pna::FILES.keys
    assert_equal "https://zenodo.org/api/records/6220409/files/Networks.zip/content",
                 Pna.file_url("Networks.zip")
    Pna::FILES.each_value { |sha| assert_match(/\A\h{64}\z/, sha) }
  end

  def test_fetch_lands_the_three_files_verbatim_with_a_state_pin
    stub_record
    Dir.mktmpdir do |workdir|
      report = Pna.new(pins: pins).fetch(workdir)
      bodies.each { |name, bytes| assert_equal bytes, File.binread(File.join(workdir, name)) }
      assert_match(/\A\h{64}\z/, report.sha)
      assert_includes report.notes, "8 persons"
      state = JSON.parse(File.read(File.join(workdir, Pna::STATE_FILE)))
      assert_equal report.sha, state["sha256"]
      assert_equal pins, state["files"]

      again = Pna.new(pins: pins).fetch(workdir)
      assert_equal report.sha, again.sha
      assert_includes again.notes, "already at"
    end
  end

  def test_a_pin_mismatch_refuses_before_writing_anything
    stub_record("README.txt" => "a re-release nobody announced")
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Pna.new(pins: pins).fetch(workdir) }
      assert_match(/sha256 pin/, error.message)
      assert_empty Dir.children(workdir)
    end
  end

  def test_the_real_pins_refuse_the_trimmed_fixtures
    stub_record
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Pna.new.fetch(workdir) }
    end
  end

  def test_manifest_is_attribution_with_the_verified_license
    manifest = Pna.manifest
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "Creative Commons Attribution-ShareAlike 3.0 Unported License"
    assert_includes manifest.license, "2026-10-28"
  end

  def test_the_license_sentence_is_in_the_record_readme
    assert_includes File.read(File.join(FIXTURES, "README.txt")),
                    "These files are licensed under a Creative Commons Attribution-ShareAlike 3.0 Unported License."
  end

  def test_module_census_reads_the_archives_and_counts_the_skipped_edges
    Dir.mktmpdir do |workdir|
      PnaFixtureZips.pack!(FIXTURES, workdir)
      counts = Nabu::ModuleCensus.at_dir(Pna, workdir).to_h { |c| [c.label, c.count] }
      assert_equal 8, counts["persons"]
      assert_equal 3, counts["co-occurrence edges (skipped by rule)"]
    end
  end

  def test_probe_is_liveness_only_on_the_record
    assert_equal :http_zip, Pna.remote_probe_strategy
    target = Pna.http_probe_targets.first
    assert target.liveness_only
    assert_equal "https://zenodo.org/records/6220409", target.zip_url
  end
end
