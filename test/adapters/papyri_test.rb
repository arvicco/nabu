# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Papyri.info (DDbDP) adapter tests (P3-6). The adapter composes DdbdpParser
# with the idp.data repo layout: discover walks
# DDB_EpiDoc_XML/<collection>/(<collection>.<volume>/)?*.xml — both nested
# (bgu/bgu.1/) and flat (c.epist.lat/) collections — peeking each header for
# ddb-hybrid/HGV/TM idnos, title and edition language; parse delegates to
# DdbdpParser; fetch clones/pulls the single upstream repo. Includes the
# shared AdapterConformance suite against the checked-in fixtures. No
# network: fetch runs against a local git repo in a tmpdir.
class PapyriTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("ddbdp") # NABU_FIXTURE_DIR-aware (fixtures:check)

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Papyri.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "papyri-ddbdp"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::Papyri.manifest
    assert_equal "papyri-ddbdp", manifest.id
    assert_equal "Papyri.info — Duke Databank of Documentary Papyri", manifest.name
    assert_equal "CC BY 3.0 (per-document availability)", manifest.license
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/papyri/idp.data", manifest.upstream_url
    assert_equal "ddbdp", manifest.parser_family
  end

  # --- discover -----------------------------------------------------------

  def test_discover_finds_both_nested_and_flat_collections_with_frozen_urn_minting
    refs = Nabu::Adapters::Papyri.new.discover(FIXTURES).to_a
    assert_equal %w[
      urn:nabu:ddbdp:bgu:1:100
      urn:nabu:ddbdp:bgu:1:102
      urn:nabu:ddbdp:c.epist.lat::10
    ], refs.map(&:id)
    refs.each do |ref|
      assert_equal "papyri-ddbdp", ref.source_id
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path)
    end
  end

  def test_discover_metadata_carries_language_title_and_hgv_tm_crosslinks
    refs = Nabu::Adapters::Papyri.new.discover(FIXTURES).to_a
    bgu100, bgu102, cel10 = refs

    assert_equal({ "language" => "grc", "title" => "bgu.1.100", "hgv" => "8875", "tm" => "8875" },
                 bgu100.metadata)
    assert_equal({ "language" => "grc", "title" => "bgu.1.102", "hgv" => "8877", "tm" => "8877" },
                 bgu102.metadata)
    # Edition div says xml:lang="la"; our tags use ISO 639-3 lat.
    assert_equal({ "language" => "lat", "title" => "c.epist.lat.10", "hgv" => "78573", "tm" => "78573" },
                 cel10.metadata)
  end

  def test_discover_skips_files_without_a_ddb_hybrid_idno
    Dir.mktmpdir do |root|
      collection = File.join(root, "DDB_EpiDoc_XML", "bgu", "bgu.1")
      FileUtils.mkdir_p(collection)
      FileUtils.cp(File.join(FIXTURES, "DDB_EpiDoc_XML", "bgu", "bgu.1", "bgu.1.100.xml"), collection)
      # A stray non-DDbDP xml (no ddb-hybrid idno) must be skipped, not error.
      File.write(File.join(collection, "stray.xml"), "<TEI><teiHeader/></TEI>\n")
      refs = Nabu::Adapters::Papyri.new.discover(root).to_a
      assert_equal ["urn:nabu:ddbdp:bgu:1:100"], refs.map(&:id)
    end
  end

  # --- parse round-trip -----------------------------------------------------

  def test_parse_delegates_to_ddbdp_parser_and_urn_matches_ref
    adapter = Nabu::Adapters::Papyri.new
    ref = adapter.discover(FIXTURES).first
    document = adapter.parse(ref)
    assert_equal ref.id, document.urn
    assert_equal 12, document.size
    assert_equal "grc", document.language
    assert_equal "bgu.1.100", document.title
  end

  def test_parse_latin_document_spot_check
    adapter = Nabu::Adapters::Papyri.new
    ref = adapter.discover(FIXTURES).to_a.last
    document = adapter.parse(ref)
    assert_equal "lat", document.language
    assert_equal "urn:nabu:ddbdp:c.epist.lat::10:r:7", document.to_a[6].urn
    assert_equal "qui de tam pusilla summa tam magnum lucrum facit", document.to_a[6].text
  end

  # --- fetch (local git only, no network) -----------------------------------

  def test_fetch_clones_then_pulls_and_returns_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream)
      workdir = File.join(root, "work")
      adapter = papyri_pointing_at(upstream)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_instance_of Time, report.fetched_at
      assert File.directory?(File.join(workdir, ".git")), "repo must be cloned"
      assert_equal git(upstream, "rev-parse", "HEAD"), report.sha

      # Second call → pull path, still succeeds and reports the same sha.
      assert_equal report.sha, adapter.fetch(workdir).sha
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      workdir = File.join(root, "work")
      adapter = papyri_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- registry round-trip ----------------------------------------------------

  def test_registry_resolves_papyri_ddbdp_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["papyri-ddbdp"]
    refute_nil entry, "papyri-ddbdp must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Papyri, entry.adapter_class
    assert_equal "papyri-ddbdp", entry.manifest.id
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::Papyri.manifest, entry.manifest
  end

  private

  # An adapter whose repo_url resolves to a local git tmpdir (house test
  # pattern), keeping fetch entirely off the network.
  def papyri_pointing_at(upstream)
    adapter = Nabu::Adapters::Papyri.new
    adapter.define_singleton_method(:repo_url) { upstream }
    adapter
  end

  def make_git_repo(dir)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    File.write(File.join(dir, "readme.txt"), "idp.data\n")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
