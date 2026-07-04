# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Universal Dependencies adapter tests (P3-3). The adapter composes ConlluParser
# with UD's git-repo-per-treebank layout: discover walks <slug>/*.conllu (one
# DocumentRef per file), parse delegates to ConlluParser, fetch clones/pulls
# each treebank repo. Includes the shared AdapterConformance suite against the
# checked-in UD fixtures. No network: fetch is exercised against a local git
# repo in a tmpdir plus a Shell-failure path.
class UniversalDependenciesTest < Minitest::Test
  include AdapterConformance

  FIXTURES = File.expand_path("../fixtures/ud", __dir__)

  EXPECTED_URNS = [
    "urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50",
    "urn:nabu:ud:greek-proiel:grc_proiel-ud-test-head50",
    "urn:nabu:ud:latin-ittb:la_ittb-ud-test-head50+mwt",
    "urn:nabu:ud:sanskrit-vedic:sa_vedic-ud-test-head50"
  ].freeze

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::UniversalDependencies.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "ud"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::UniversalDependencies.manifest
    assert_equal "ud", manifest.id
    assert_equal "Universal Dependencies — ancient treebanks", manifest.name
    assert_equal "nc", manifest.license_class
    assert_equal "https://github.com/UniversalDependencies", manifest.upstream_url
    assert_equal "conllu", manifest.parser_family
  end

  def test_instance_manifest_agrees_with_class_manifest
    assert_equal Nabu::Adapters::UniversalDependencies.manifest,
                 Nabu::Adapters::UniversalDependencies.new.manifest
  end

  # --- discover -----------------------------------------------------------

  def test_discover_finds_exactly_four_files_sorted_by_urn
    refs = Nabu::Adapters::UniversalDependencies.new.discover(FIXTURES).to_a
    assert_equal EXPECTED_URNS, refs.map(&:id)
  end

  def test_discover_sets_source_id_language_treebank_and_absolute_path
    refs = Nabu::Adapters::UniversalDependencies.new.discover(FIXTURES).to_a
    by_urn = refs.to_h { |ref| [ref.id, ref] }

    expected_languages = {
      "urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50" => "got",
      "urn:nabu:ud:greek-proiel:grc_proiel-ud-test-head50" => "grc",
      "urn:nabu:ud:latin-ittb:la_ittb-ud-test-head50+mwt" => "lat",
      "urn:nabu:ud:sanskrit-vedic:sa_vedic-ud-test-head50" => "san"
    }
    expected_languages.each do |urn, language|
      ref = by_urn.fetch(urn)
      assert_equal "ud", ref.source_id
      assert_equal language, ref.metadata["language"]
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path), "path must exist: #{ref.path.inspect}"
    end

    got = by_urn.fetch("urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50")
    assert_equal "gothic-proiel", got.metadata["treebank"]
    assert_equal "UD_Gothic-PROIEL (got_proiel-ud-test-head50)", got.metadata["title"]
  end

  def test_discover_skips_unknown_subdirectories
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "gothic-proiel"))
      FileUtils.cp(
        File.join(FIXTURES, "gothic-proiel", "got_proiel-ud-test-head50.conllu"),
        File.join(root, "gothic-proiel")
      )
      # An unregistered treebank on disk must be ignored, not error.
      FileUtils.mkdir_p(File.join(root, "klingon-tng"))
      unknown = "# sent_id = 1\n# text = x\n1\tx\t_\t_\t_\t_\t0\troot\t_\t_\n\n"
      File.write(File.join(root, "klingon-tng", "tlh-ud-test.conllu"), unknown)

      refs = Nabu::Adapters::UniversalDependencies.new.discover(root).to_a
      assert_equal ["urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50"], refs.map(&:id)
    end
  end

  # --- parse round-trip ---------------------------------------------------

  def test_parse_delegates_to_conllu_parser_and_urn_matches_ref
    adapter = Nabu::Adapters::UniversalDependencies.new
    ref = adapter.discover(FIXTURES).find { |r| r.id.include?("gothic") }
    document = adapter.parse(ref)
    assert_equal ref.id, document.urn
    assert_equal 50, document.size
    assert_equal "got", document.language
  end

  # --- fetch (local git only, no network) ---------------------------------

  def test_fetch_clones_each_treebank_then_pulls_and_returns_report
    Dir.mktmpdir do |root|
      upstreams = {}
      Nabu::Adapters::UniversalDependencies::TREEBANKS.each_key do |slug|
        upstream = File.join(root, "upstream-#{slug}")
        make_git_repo(upstream, slug)
        upstreams[slug] = upstream
      end

      workdir = File.join(root, "work")
      adapter = ud_pointing_at(upstreams)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_instance_of Time, report.fetched_at

      # Every treebank was cloned into its own subdir.
      upstreams.each_key do |slug|
        assert File.directory?(File.join(workdir, slug, ".git")), "#{slug} must be cloned"
        head = git(upstreams[slug], "rev-parse", "HEAD")
        assert_includes report.notes, "#{slug}=#{head}"
      end

      # sha is the LAST treebank's HEAD; notes carries the whole summary.
      last_slug = upstreams.keys.last
      assert_equal git(upstreams[last_slug], "rev-parse", "HEAD"), report.sha

      # Second call → pull path, still succeeds and reports the same shas.
      assert_equal report.notes, adapter.fetch(workdir).notes
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      workdir = File.join(root, "work")
      adapter = ud_pointing_at(Hash.new(File.join(root, "does-not-exist")))
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- registry round-trip ------------------------------------------------

  def test_registry_resolves_ud_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ud"]
    refute_nil entry, "ud must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::UniversalDependencies, entry.adapter_class
    assert_equal "ud", entry.manifest.id
    assert_equal Nabu::Adapters::UniversalDependencies.manifest, entry.manifest
  end

  private

  # An adapter whose repo_url resolves to local git tmpdirs (Perseus test
  # pattern), keeping fetch entirely off the network.
  def ud_pointing_at(upstreams)
    adapter = Nabu::Adapters::UniversalDependencies.new
    adapter.define_singleton_method(:repo_url) { |slug| upstreams[slug] }
    adapter
  end

  def make_git_repo(dir, seed)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    File.write(File.join(dir, "#{seed}.txt"), "#{seed}\n")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", seed)
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
