# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Vulgate adapter tests (P11-5): the full Clementine Latin bible from
# seven1m/open-bibles (one whole-bible USFX file), minting one document per
# book. Includes the shared AdapterConformance suite against the checked-in
# fixture trim (GEN 1, MRK 1-2, JHN 1:1-18). No network: fetch runs against a
# local git repo.
class VulgateTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("vulgate")

  BOOK_URNS = %w[urn:nabu:vulgate:gen urn:nabu:vulgate:mrk urn:nabu:vulgate:jhn].freeze

  def conformance_adapter
    Nabu::Adapters::Vulgate.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "vulgate"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_vulgate_source
    manifest = Nabu::Adapters::Vulgate.manifest
    assert_equal "vulgate", manifest.id
    assert_equal "Public Domain", manifest.license
    assert_equal "open", manifest.license_class
    assert_equal "https://github.com/seven1m/open-bibles", manifest.upstream_url
    assert_equal "usfx", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_book_in_canon_order
    refs = Nabu::Adapters::Vulgate.new.discover(FIXTURES).to_a
    assert_equal BOOK_URNS, refs.map(&:id)
    assert_equal(%w[GEN MRK JHN], refs.map { |r| r.metadata["book"] })
    assert_equal(%w[Genesis Marcus Joannes], refs.map { |r| r.metadata["title"] })
    assert(refs.all? { |r| r.source_id == "vulgate" && r.metadata["language"] == "lat" })
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Vulgate.new.discover(dir).to_a
    end
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_round_trips_mark_at_verse_grain
    adapter = Nabu::Adapters::Vulgate.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:vulgate:mrk" }
    document = adapter.parse(ref)
    assert_equal "urn:nabu:vulgate:mrk", document.urn
    assert_equal "lat", document.language
    assert_equal "Marcus", document.title
    assert_equal 73, document.size
    mark23 = document.find { |p| p.urn == "urn:nabu:vulgate:mrk:2.3" }
    assert_equal "Et venerunt ad eum ferentes paralyticum, qui a quatuor portabatur.", mark23.text
  end

  # --- fetch (local git only, no network) ---------------------------------------

  def test_fetch_clones_then_pulls_and_returns_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream)
      workdir = File.join(root, "work")
      adapter = vulgate_pointing_at(upstream)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert File.directory?(File.join(workdir, ".git")), "repo must be cloned"
      assert_equal report.sha, adapter.fetch(workdir).sha
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      adapter = vulgate_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
    end
  end

  # --- registry round-trip -------------------------------------------------------

  def test_registry_resolves_vulgate_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["vulgate"]
    refute_nil entry, "vulgate must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Vulgate, entry.adapter_class
    assert entry.enabled, "vulgate is live (owner sign-off 2026-07-10 after first sync + eyeball)"
    assert_equal Nabu::Adapters::Vulgate.manifest, entry.manifest
  end

  private

  def vulgate_pointing_at(upstream)
    adapter = Nabu::Adapters::Vulgate.new
    adapter.define_singleton_method(:repo_url) { upstream }
    adapter
  end

  def make_git_repo(dir)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    FileUtils.cp(File.join(FIXTURES, "lat-clementine.usfx.xml"), dir)
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
