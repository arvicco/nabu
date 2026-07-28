# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"

# The build orchestrator (P50-W1): builder -> languages.csv/sources.bib ->
# datapackage.json/README.md, with canonical input shas resolved honestly
# (git HEAD only when the tree is clean; content identity for non-git trees;
# refusal otherwise) and NEVER a git operation in the output clone.
class DataBuildRunnerTest < Minitest::Test
  def with_env
    Dir.mktmpdir("nabu-data-runner") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      sources = File.join(root, "sources.yml")
      File.write(sources, "alpha:\n  adapter: TestAdapter\n  wired: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      registry = Nabu::SourceRegistry.load(sources)
      yield root, config, Nabu::DataBuild::Runner.new(config: config, registry: registry)
    end
  end

  def git(dir, *argv)
    Nabu::Shell.run("git", "-C", dir, *argv)
  end

  def seed_repo(dir)
    FileUtils.mkdir_p(dir)
    Nabu::Shell.run("git", "init", "-q", dir)
    File.write(File.join(dir, "data.txt"), "one\n")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
    git(dir, "rev-parse", "HEAD").strip
  end

  def test_run_writes_the_full_dataset_directory_and_summarizes_honestly
    with_env do |root, _config, runner|
      into = File.join(root, "nabu-data")
      summary = runner.run(feature: DataBuildFake.feature, into: into)

      out_dir = File.join(into, "san", "fake-forms")
      assert_equal out_dir, summary.out_dir
      %w[forms.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert File.file?(File.join(out_dir, name)), "expected #{name} in the dataset directory"
      end

      table = CSV.read(File.join(out_dir, "languages.csv"))
      assert_equal %w[san Sanskrit sans1269 san], table[1]

      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      assert_equal "san-fake-forms", manifest["name"]
      assert_equal(%w[forms languages sources], manifest["resources"].map { |resource| resource["name"] })

      assert_equal 3, summary.rows, "2 forms rows + 1 languages row"
      assert_equal manifest.dig("nabu", "derivation", "fingerprint"), summary.fingerprint
      assert_includes summary.files.map(&:first), "forms.csv"

      readme = File.read(File.join(out_dir, "README.md"))
      assert_match(%r{nabu data build san/fake-forms}, readme)
      assert_match(/Maintenance/, readme)
    end
  end

  def test_run_refuses_a_planned_feature
    with_env do |root, _config, runner|
      error = assert_raises(Nabu::DataBuild::Error) do
        runner.run(feature: Nabu::DataBuild.feature("san/form-lemma"), into: File.join(root, "out"))
      end
      assert_match(/planned/, error.message)
    end
  end

  def test_cone_shas_land_in_manifest_sources_and_change_the_fingerprint
    with_env do |root, _config, runner|
      repo = File.join(root, "canonical", "alpha")
      head = seed_repo(repo)
      feature = DataBuildFake.feature(inputs: ["alpha"], canonical_cones: ["alpha"])
      into = File.join(root, "nabu-data")

      first = runner.run(feature: feature, into: into)
      manifest = JSON.parse(File.read(File.join(first.out_dir, "datapackage.json")))
      assert_equal head, manifest.dig("nabu", "derivation", "inputs", "alpha", "canonical_sha")

      source = manifest["sources"].first
      assert_equal "Conformance Test Adapter", source["title"], "title comes from the source's manifest"
      assert_equal head, source["version"]
      assert_equal [{ "name" => "CC0 1.0 (hand-written test data)" }], source["licenses"]

      # A new upstream commit changes the cone sha — and therefore the
      # fingerprint, with an unchanged recipe.
      File.write(File.join(repo, "data.txt"), "two\n")
      git(repo, "add", ".")
      git(repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "update")
      second = runner.run(feature: feature, into: into)
      refute_equal first.fingerprint, second.fingerprint
    end
  end

  def test_a_dirty_git_cone_is_refused_not_misdescribed
    with_env do |root, _config, runner|
      repo = File.join(root, "canonical", "alpha")
      seed_repo(repo)
      File.write(File.join(repo, "data.txt"), "edited, uncommitted\n")
      feature = DataBuildFake.feature(inputs: ["alpha"], canonical_cones: ["alpha"])
      error = assert_raises(Nabu::DataBuild::Error) do
        runner.run(feature: feature, into: File.join(root, "out"))
      end
      assert_match(/local modifications/, error.message)
    end
  end

  def test_a_non_git_cone_gets_the_content_identity
    with_env do |root, _config, runner|
      cone = File.join(root, "canonical", "alpha")
      FileUtils.mkdir_p(cone)
      File.write(File.join(cone, "table.tsv"), "a\tb\n")
      feature = DataBuildFake.feature(inputs: ["alpha"], canonical_cones: ["alpha"])
      summary = runner.run(feature: feature, into: File.join(root, "nabu-data"))
      manifest = JSON.parse(File.read(File.join(summary.out_dir, "datapackage.json")))
      sha = manifest.dig("nabu", "derivation", "inputs", "alpha", "canonical_sha")
      assert_equal Nabu::DerivationFingerprint.canonical_identity(cone), sha
      assert_match(/\A\h{64}\z/, sha)
    end
  end

  def test_a_missing_cone_is_refused_with_a_sync_hint
    with_env do |root, _config, runner|
      feature = DataBuildFake.feature(inputs: ["alpha"], canonical_cones: ["alpha"])
      error = assert_raises(Nabu::DataBuild::Error) do
        runner.run(feature: feature, into: File.join(root, "out"))
      end
      assert_match(/missing/, error.message)
      assert_match(/sync/, error.message)
    end
  end

  def test_an_unregistered_input_source_is_refused
    with_env do |root, _config, runner|
      cone = File.join(root, "canonical", "ghost")
      FileUtils.mkdir_p(cone)
      File.write(File.join(cone, "x.txt"), "x\n")
      feature = DataBuildFake.feature(inputs: ["ghost"], canonical_cones: ["ghost"])
      error = assert_raises(Nabu::DataBuild::Error) do
        runner.run(feature: feature, into: File.join(root, "out"))
      end
      assert_match(/ghost/, error.message)
      assert_match(/not registered/, error.message)
    end
  end

  def test_the_runner_never_touches_git_in_the_output_clone
    with_env do |root, _config, runner|
      into = File.join(root, "nabu-data")
      Nabu::Shell.run("git", "init", "-q", into)
      runner.run(feature: DataBuildFake.feature, into: into)
      status = Nabu::Shell.run("git", "-C", into, "status", "--porcelain")
      refute_empty status.strip, "written files must be left uncommitted — publishing is the owner's act"
      log = Nabu::Shell.run("git", "-C", into, "rev-list", "--all", "--count").strip
      assert_equal "0", log, "the rail must never create commits in the nabu-data clone"
    end
  end
end
