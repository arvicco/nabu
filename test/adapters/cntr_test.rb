# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# CNTR adapter tests: the Center for New Testament Restoration's MES
# transcriptions, one document per witness file. Includes the shared
# AdapterConformance suite against the checked-in real files (README.md
# there names every grain); the critical-text, class-README and top-level
# documentation specimens pin the rejected grains. No network: fetch runs
# against a WebMock stub of the commit-addressed archive, built from the
# fixtures in upstream's own zip shape (one top directory).
class CntrTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("cntr")
  ADAPTER = Nabu::Adapters::Cntr

  URNS = %w[0171 03 62312 meli orig p52].map { |id| "urn:nabu:cntr:#{id}" }.freeze

  def conformance_adapter
    ADAPTER.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "cntr"
  end

  def document(id)
    adapter = ADAPTER.new
    adapter.parse(adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:cntr:#{id}" })
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_source
    manifest = ADAPTER.manifest
    assert_equal "cntr", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/\ACC BY-SA 4\.0/, manifest.license)
    assert_match(/Alan Bunning and the Center for New Testament Restoration/, manifest.license)
    assert_equal "https://github.com/Center-for-New-Testament-Restoration/transcriptions",
                 manifest.upstream_url
    assert_equal "cntr-mes", manifest.parser_family
  end

  def test_the_pin_is_commit_addressed
    assert_match(/\A\h{40}\z/, ADAPTER::COMMIT)
    assert_equal "https://codeload.github.com/Center-for-New-Testament-Restoration/transcriptions/zip/" \
                 "#{ADAPTER::COMMIT}", ADAPTER::ZIP_URL
    assert_match(/\A\h{64}\z/, ADAPTER::ZIP_SHA256)
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_witness_file
    refs = ADAPTER.new.discover(FIXTURES).to_a
    assert_equal URNS, refs.map(&:id)
    titles = refs.to_h { |r| [r.id.split(":").last, r.metadata["title"]] }
    assert_equal "GA P52", titles["p52"]
    assert_equal "TM 62312 (GA P12)", titles["62312"]
    assert_equal "Orig (patristic citations)", titles["orig"]
    assert_equal({ "p52" => 1, "62312" => 2, "orig" => 3 },
                 refs.to_h { |r| [r.id.split(":").last, r.metadata["cntr_class"]] }.slice("p52", "62312", "orig"))
  end

  def test_the_rejected_grains_skip_by_rule
    skips = ADAPTER.new.discovery_skips(FIXTURES)
    assert_equal 6, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert skips.clean?
    assert(skips.notes.any? { |n| n.start_with?("critical texts/SR.txt: skipped by rule — a modern critical edition") })
    assert(skips.notes.any? { |n| n.start_with?("class 2/README.txt: skipped by rule") })
    assert_equal(4, skips.notes.count { |n| n.include?("repository documentation") })
  end

  def test_a_stray_file_is_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "class 4"))
      File.write(File.join(dir, "class 4", "Copt.txt"), "40001001 x\n")
      skips = ADAPTER.new.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_empty ADAPTER.new.discover(dir).to_a
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty ADAPTER.new.discover(dir).to_a }
  end

  # --- parse ------------------------------------------------------------------

  def test_fixture_passage_counts
    counts = URNS.to_h { |urn| [urn.split(":").last, document(urn.split(":").last).size] }
    assert_equal({ "0171" => 30, "03" => 9, "62312" => 1, "meli" => 1, "orig" => 2, "p52" => 5 }, counts)
  end

  def test_document_shape
    doc = document("p52")
    assert_equal "urn:nabu:cntr:p52", doc.urn
    assert_equal "grc", doc.language
    assert_equal "GA P52", doc.title
    assert_equal "urn:nabu:cntr:p52:john.18.31", doc.first.urn
    assert_equal({ "cntr_id" => "P52", "cntr_class" => 1, "identifier_system" => "Gregory-Aland",
                   "books" => ["john"] }, doc.metadata.except("class_note"))
  end

  def test_tokens_carry_the_nt_hub_citation
    verse = document("03").find { |p| p.urn == "urn:nabu:cntr:03:matt.1.1" }
    assert(verse.annotations["tokens"].all? { |t| t["citation_part"] == "MATT 1.1" })
    registry = Nabu::AlignmentRegistry.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "alignments.yml"))
    witness = registry.work("nt").witness_for("urn:nabu:cntr:03")
    refute_nil witness, "every CNTR witness joins the nt hub"
    assert_equal "MATT 1.1", witness.normalize_ref(verse.annotations["tokens"].first["citation_part"])
  end

  def test_parse_is_idempotent
    first = document("0171")
    second = document("0171")
    assert_equal first.map(&:urn), second.map(&:urn)
    assert_equal first.map(&:text), second.map(&:text)
    assert_equal first.map(&:annotations), second.map(&:annotations)
  end

  # --- fetch (WebMock only, no network) ------------------------------------------

  def test_fetch_lands_the_archive_tree_and_verifies_the_pin
    body = zip_body
    stub_request(:get, ADAPTER::ZIP_URL).to_return(status: 200, body: body,
                                                   headers: { "Content-Type" => "application/zip" })
    Dir.mktmpdir do |dir|
      adapter = ADAPTER.new(pin: Digest::SHA256.hexdigest(body))
      report = adapter.fetch(dir)
      assert_equal ADAPTER::COMMIT, report.sha
      assert File.exist?(File.join(dir, "class 1", "P52.txt")), "the zip's top directory maps onto the workdir"
      assert_equal URNS, adapter.discover(dir).map(&:id)
      assert ADAPTER.new.discovery_skips(dir).clean?, "the fetcher's state file is not a stray"
    end
  end

  def test_fetch_rejects_a_sha_drift_with_the_tree_untouched
    stub_request(:get, ADAPTER::ZIP_URL).to_return(status: 200, body: zip_body,
                                                   headers: { "Content-Type" => "application/zip" })
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(dir) }
      assert_match(/sha256 pin/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ADAPTER::ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(dir) }
    end
  end

  # --- registry round-trip -------------------------------------------------------

  def test_registry_resolves_the_source_wired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["cntr"]
    refute_nil entry, "cntr must be registered in config/sources/"
    assert_equal ADAPTER, entry.adapter_class
    assert entry.wired, "wired after the verified first sync (189 docs / 42,228 passages, 2026-11-21)"
    assert_equal ADAPTER.manifest, entry.manifest
  end

  private

  # The fixture tree in GitHub's archive shape: one top directory named
  # <repo>-<commit>.
  def zip_body
    Dir.mktmpdir do |staging|
      top = "transcriptions-#{ADAPTER::COMMIT}"
      FileUtils.cp_r(FIXTURES, File.join(staging, top))
      zip = File.join(staging, "archive.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip, top, chdir: staging)
      File.binread(zip)
    end
  end
end
