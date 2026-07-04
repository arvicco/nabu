# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# PROIEL Treebank adapter tests (P3-4). The adapter composes ProielParser with
# the proiel-treebank repo's flat *.xml layout: discover peeks each file's
# <source> header (id/language/title), parse delegates to ProielParser, fetch
# clones/pulls the single upstream repo. Includes the shared AdapterConformance
# suite against the checked-in fixture. No network: fetch runs against a local
# git repo in a tmpdir plus a Shell-failure path.
class ProielTest < Minitest::Test
  include AdapterConformance

  FIXTURES = File.expand_path("../fixtures/proiel", __dir__)

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Proiel.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "proiel"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::Proiel.manifest
    assert_equal "proiel", manifest.id
    assert_equal "PROIEL Treebank", manifest.name
    assert_equal "nc", manifest.license_class
    assert_equal "https://github.com/proiel/proiel-treebank", manifest.upstream_url
    assert_equal "proiel", manifest.parser_family
  end

  def test_instance_manifest_agrees_with_class_manifest
    assert_equal Nabu::Adapters::Proiel.manifest, Nabu::Adapters::Proiel.new.manifest
  end

  # --- discover -----------------------------------------------------------

  def test_discover_yields_one_ref_with_source_derived_urn_and_metadata
    refs = Nabu::Adapters::Proiel.new.discover(FIXTURES).to_a
    assert_equal 1, refs.size
    ref = refs.first
    assert_equal "urn:nabu:proiel:cic-off", ref.id
    assert_equal "proiel", ref.source_id
    assert_equal "lat", ref.metadata["language"]
    assert_equal "De officiis", ref.metadata["title"]
    assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
    assert File.file?(ref.path)
  end

  def test_discover_skips_files_without_a_source_element
    Dir.mktmpdir do |root|
      FileUtils.cp(File.join(FIXTURES, "cic-off-head15.xml"), root)
      # A stray non-treebank .xml (no <source>) must be skipped, not error.
      File.write(File.join(root, "not-a-treebank.xml"), "<config><setting>x</setting></config>\n")
      refs = Nabu::Adapters::Proiel.new.discover(root).to_a
      assert_equal ["urn:nabu:proiel:cic-off"], refs.map(&:id)
    end
  end

  # --- parse round-trip ---------------------------------------------------

  def test_parse_delegates_to_proiel_parser_and_urn_matches_ref
    adapter = Nabu::Adapters::Proiel.new
    ref = adapter.discover(FIXTURES).first
    document = adapter.parse(ref)
    assert_equal ref.id, document.urn
    assert_equal 18, document.size
    assert_equal "lat", document.language
    assert_equal "De officiis", document.title
  end

  # --- fetch (local git only, no network) ---------------------------------

  def test_fetch_clones_then_pulls_and_returns_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream)
      workdir = File.join(root, "work")
      adapter = proiel_pointing_at(upstream)

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
      adapter = proiel_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- registry round-trip ------------------------------------------------

  def test_registry_resolves_proiel_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["proiel"]
    refute_nil entry, "proiel must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Proiel, entry.adapter_class
    assert_equal "proiel", entry.manifest.id
    assert_equal "frozen", entry.sync_policy
    assert_equal Nabu::Adapters::Proiel.manifest, entry.manifest
  end

  private

  # An adapter whose repo_url resolves to a local git tmpdir (Perseus/UD test
  # pattern), keeping fetch entirely off the network.
  def proiel_pointing_at(upstream)
    adapter = Nabu::Adapters::Proiel.new
    adapter.define_singleton_method(:repo_url) { upstream }
    adapter
  end

  def make_git_repo(dir)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    File.write(File.join(dir, "readme.txt"), "proiel\n")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
