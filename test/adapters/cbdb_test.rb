# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"
require "json"

# Nabu::Adapters::Cbdb (P96-4): the prosopography instrument's
# acquisition module — latest.json (filename + sha256 + direct URL)
# drives a self-pinning fetch; v1 derives nothing (the persons-layer
# scout's ruling decides the surface). No network: WebMock stubs.
class CbdbTest < Minitest::Test
  LATEST = Nabu::Adapters::Cbdb::LATEST_JSON_URL
  HF_URL = "https://huggingface.co/datasets/cbdb/cbdb-sqlite/resolve/test/cbdb_test.zip"

  def setup
    @sqlite = "fake sqlite bytes for the pin"
    @release = {
      "sqlite_filename" => "cbdb_test.sqlite3",
      "sha256" => Digest::SHA256.hexdigest(@sqlite),
      "huggingface_url" => HF_URL
    }
  end

  def zip_body(content: @sqlite)
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "cbdb_test.sqlite3"), content)
      zip = File.join(dir, "z.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", zip, "cbdb_test.sqlite3") }
      File.binread(zip)
    end
  end

  def stub_channel(zip: zip_body)
    stub_request(:get, LATEST).to_return(status: 200, body: JSON.generate(@release))
    stub_request(:get, HF_URL).to_return(status: 200, body: zip)
  end

  def test_registry_module_row_and_module_shape
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["cbdb"]
    refute_nil entry
    assert entry.feature_module?
    adapter = Nabu::Adapters::Cbdb.new
    assert_empty adapter.discover(".").to_a
    ref = Nabu::DocumentRef.new(source_id: "cbdb", id: "urn:nabu:cbdb:x", path: ".", metadata: {})
    assert_raises(Nabu::ParseError) { adapter.parse(ref) }
  end

  def test_fetch_verifies_the_latest_json_pin_and_lands_the_sqlite
    stub_channel
    Dir.mktmpdir do |workdir|
      report = Nabu::Adapters::Cbdb.new.fetch(workdir)
      assert_equal @release["sha256"], report.sha
      assert File.file?(File.join(workdir, "cbdb_test.sqlite3"))
      state = JSON.parse(File.read(File.join(workdir, Nabu::Adapters::Cbdb::STATE_FILE)))
      assert_equal @release["sha256"], state["sha256"]

      second = Nabu::Adapters::Cbdb.new.fetch(workdir)
      assert_includes second.notes, "already at", "an unchanged release re-downloads nothing"
    end
  end

  def test_a_sha_mismatch_refuses_and_keeps_nothing
    stub_channel(zip: zip_body(content: "tampered bytes"))
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Cbdb.new.fetch(workdir) }
      assert_match(/sha mismatch.*refused/m, error.message)
      refute File.file?(File.join(workdir, "cbdb_test.sqlite3")),
             "a tampered artifact is never kept"
    end
  end

  def test_manifest_is_nc_with_the_nd_drift_recorded
    manifest = Nabu::Adapters::Cbdb.manifest
    assert_equal "nc", manifest.license_class
    assert_includes manifest.license, "CC BY-NC-ND 4.0"
    assert_includes manifest.license, "owner eyeballs", "the 403-gated primary read is honest"
  end
end
