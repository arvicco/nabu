# frozen_string_literal: true

require "test_helper"
require "digest"
require "tmpdir"

# Helipad adapter tests (P40-3): HeliPaD — the Heliand Parsed Database
# (Walkden; Zenodo 4395040, v0.9) — the single Penn labeled-bracketing file
# heliand.psd, one document (the Old Saxon Heliand, MS C), one passage per
# tree block. Includes the shared AdapterConformance suite against the
# checked-in fixture trim (first 2 of 3,549 trees). No network: fetch runs
# against WebMock stubs of the real Zenodo file URL, with the sha256 pin
# swapped for the fixture body's (the open-etruscan pattern).
class HelipadTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("helipad")

  RECORD_URL = "https://zenodo.org/records/4395040"
  CORPUS_URL = "https://zenodo.org/api/records/4395040/files/heliand.psd/content"
  DOC_URN = "urn:nabu:helipad:OSHeliandC"

  def conformance_adapter
    Nabu::Adapters::Helipad.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "helipad"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_helipad_source
    manifest = Nabu::Adapters::Helipad.manifest
    assert_equal "helipad", manifest.id
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(/Walkden/, manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal RECORD_URL, manifest.upstream_url
    assert_equal "penn-psd", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_document_for_the_whole_heliand
    refs = Nabu::Adapters::Helipad.new.discover(FIXTURES).to_a
    assert_equal 1, refs.size
    ref = refs.first
    assert_equal DOC_URN, ref.id, "the urn tail is the file's own ID prefix, verbatim"
    assert_equal "helipad", ref.source_id
    assert_equal "OSHeliandC", ref.metadata["text_id"]
    assert_equal "osx", ref.metadata["language"]
    assert_equal "Heliand", ref.metadata["title"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Helipad.new.discover(dir).to_a
    end
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_round_trips_the_heliand_opening_at_tree_grain
    adapter = Nabu::Adapters::Helipad.new
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_equal DOC_URN, document.urn
    assert_equal "osx", document.language
    assert_equal "Heliand", document.title
    assert_equal 2, document.size, "the fixture trim holds the first 2 of 3,549 trees"
    assert_equal ["#{DOC_URN}:1.1-5", "#{DOC_URN}:2.5-9"], document.map(&:urn)
  end

  def test_the_old_saxon_opening_is_byte_pinned_nfc
    adapter = Nabu::Adapters::Helipad.new
    first = adapter.parse(adapter.discover(FIXTURES).first).first
    assert first.text.start_with?("Manega uuaron the sia iro mod gespon, that sia uuord godes"),
           "unexpected opening: #{first.text[0, 70].inspect}"
    assert first.text.unicode_normalized?(:nfc)
    tokens = first.annotations.fetch("tokens")
    assert_equal "manag", tokens.find { |t| t["form"] == "Manega" }["lemma"], "gold lemma lane present"
    assert_includes tokens, { "code" => "F_1" }, "fitt 1 opens here — lineation retained"
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_downloads_the_pinned_file_and_returns_report
    body = File.binread(File.join(FIXTURES, "heliand-head.psd"))
    stub_request(:get, CORPUS_URL).to_return(
      status: 200, body: body,
      headers: { "Last-Modified" => "Mon, 28 Dec 2015 00:00:00 GMT" }
    )
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Helipad.new(corpus_sha256: Digest::SHA256.hexdigest(body))
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal [DOC_URN], adapter.discover(workdir).map(&:id),
                   "the fetched heliand.psd is discoverable in place"

      stub_request(:get, CORPUS_URL)
        .with(headers: { "If-Modified-Since" => "Mon, 28 Dec 2015 00:00:00 GMT" })
        .to_return(status: 304)
      assert_equal report.sha, adapter.fetch(workdir).sha, "a 304 keeps the pinned sha"
    end
  end

  def test_fetch_aborts_on_sha_drift_before_touching_the_tree
    stub_request(:get, CORPUS_URL).to_return(status: 200, body: "( (IP-MAT (X a-b)) (ID Y.1))\n")
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Helipad.new.fetch(workdir) }
      assert_match(/drifted/, error.message)
      assert_match(/re-pin/, error.message)
      refute File.exist?(File.join(workdir, "heliand.psd")), "drift aborts with the tree untouched"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, CORPUS_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Helipad.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ----------------------------------------------

  def test_probe_targets_head_the_zenodo_file_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Helipad.remote_probe_strategy
    targets = Nabu::Adapters::Helipad.http_probe_targets
    assert_equal 1, targets.size
    target = targets.first
    assert_equal CORPUS_URL, target.zip_url
    assert_nil target.metadata_url, "the Zenodo API record body carries volatile stats (diorisis lesson)"
    assert_equal "", target.state_subdir
    assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
  end

  # --- registration -----------------------------------------------------------

  def test_registered_in_sources_yml_disabled_manual_germanic
    config = YAML.safe_load_file(File.expand_path("../../config/sources.yml", __dir__))
    row = config.fetch("helipad")
    assert_equal "Nabu::Adapters::Helipad", row.fetch("adapter")
    assert_equal true, row.fetch("enabled"),
                 "first sync verified + owner-flipped 2026-07-22 (3,549 passages, fixture-predicted exactly)"
    assert_equal "manual", row.fetch("sync_policy")
    assert_equal ["germanic"], row.fetch("axes")
  end
end
