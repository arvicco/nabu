# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# The `nabu data` command family (P50-W1): `list` is the self-documentation
# surface (every feature with rationale AND maintenance — the owner ruling),
# `build` writes a dataset directory into the owner's nabu-data clone and
# never runs git there; planned features and unknown slugs refuse helpfully.
class DataCommandTest < Minitest::Test
  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end

  # Splice +features+ in as the census (the with_config singleton-swap house
  # pattern), restoring after.
  def with_features(features)
    original = Nabu::DataBuild.method(:features)
    Nabu::DataBuild.define_singleton_method(:features) { features }
    yield
  ensure
    Nabu::DataBuild.define_singleton_method(:features, original)
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def test_data_list_documents_every_feature_with_rationale_and_maintenance
    out, _err, status = run_cli(%w[data list])
    assert_nil status

    Nabu::DataBuild::REGISTRY.each do |feature|
      assert_includes out, feature.slug
      assert_includes out, feature.title
      assert_includes out, feature.status.to_s
      assert_includes out, feature.tier
      assert_includes out, feature.anchoring
      assert_includes out, feature.rationale
      assert_includes out, feature.maintenance
      assert_includes out, "license: #{feature.license}",
                      "#{feature.slug}: the metadata line states the dataset's license (D51-a)"
      feature.inputs.each { |slug| assert_includes out, slug }
    end
    assert_match(/own authorship/, out, "an inputs-free feature says so instead of printing nothing")
  end

  # Owner ruling 2026-07-29: the maintenance line alone ("re-derive after
  # each dcs sync") gives no copy-paste path — every AVAILABLE feature must
  # print its exact command sequence: the input syncs (the D50-a guard makes
  # them mandatory anyway) chained into the build invocation.
  def test_data_list_prints_explicit_copy_paste_commands_per_available_feature
    out, _err, status = run_cli(%w[data list])
    assert_nil status

    Nabu::DataBuild::REGISTRY.each do |feature|
      if feature.available?
        expected = "  commands: #{feature.inputs.map { |slug| "nabu sync #{slug} && " }.join}" \
                   "nabu data build #{feature.slug} --into "
        assert_includes out, expected,
                        "#{feature.slug}: available features print the full copy-paste command line"
      else
        refute_match(/commands:.*#{Regexp.escape(feature.slug)}/, out,
                     "#{feature.slug}: planned features print no command line — build would refuse")
      end
    end
  end

  # A spliced planned rig rather than a registry feature: builder packets
  # flip the real features one by one, and this refusal must outlive them all.
  def test_data_build_refuses_a_planned_feature_by_name
    planned = Nabu::DataBuild::Feature.new(
      slug: "san/planned-rig", language: Nabu::DataBuild::LANGUAGES.fetch("san"),
      title: "Planned rig (no builder yet)", status: :planned, tier: "gold", anchoring: "none",
      inputs: [], canonical_cones: [], rationale: "Exists to pin the planned refusal.",
      maintenance: "never — test rig only"
    )
    out_dir = Dir.mktmpdir("nabu-data-cli")
    out, err, status = with_features(Nabu::DataBuild::REGISTRY + [planned]) do
      run_cli(["data", "build", "san/planned-rig", "--into", out_dir])
    end
    assert_equal 1, status
    assert_match(/planned/, err)
    assert_match(%r{san/planned-rig}, err)
    assert_empty Dir.children(out_dir), "a refusal must write nothing"
    assert_empty out
  ensure
    FileUtils.remove_entry(out_dir)
  end

  def test_data_build_rejects_an_unknown_slug_listing_the_valid_ones
    _out, err, status = run_cli(["data", "build", "grc/none-such", "--into", "/tmp/never-used"])
    assert_equal 1, status
    assert_match(%r{grc/none-such}, err)
    Nabu::DataBuild::REGISTRY.each { |feature| assert_includes err, feature.slug }
  end

  def test_data_build_writes_the_dataset_and_prints_an_honest_summary
    Dir.mktmpdir("nabu-data-cli") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      into = File.join(root, "nabu-data")
      fake = DataBuildFake.feature

      out, _err, status = with_config(config) do
        with_features(Nabu::DataBuild::REGISTRY + [fake]) do
          run_cli(["data", "build", "san/fake-forms", "--into", into])
        end
      end

      assert_nil status
      out_dir = File.join(into, "san", "fake-forms")
      %w[forms.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert File.file?(File.join(out_dir, name)), "expected #{name}"
        assert_includes out, name, "the summary lists every file written"
      end
      assert_match(/2 rows/, out, "the summary reports rows written")
      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      assert_includes out, manifest.dig("nabu", "derivation", "fingerprint")[0, 12]
      assert_match(/[Nn]o git/, out, "the summary states the no-git contract")
    end
  end

  def test_help_lists_the_data_subcommands
    out, _err, _status = run_cli(%w[data])
    assert_match(/data list/, out)
    assert_match(/data build/, out)
  end

  # Owner ask 2026-07-29: `data build --all` rebuilds every AVAILABLE feature
  # in one command. Planned features are skipped by name (never a failure);
  # per-feature summaries print as each lands; one grand total closes.
  def test_data_build_all_builds_every_available_and_skips_planned
    with_build_env do |config, into|
      second = DataBuildFake.feature(slug: "san/fake-extra")
      planned = planned_rig
      out, _err, status = with_config(config) do
        with_features([DataBuildFake.feature, second, planned]) do
          run_cli(["data", "build", "--all", "--into", into])
        end
      end
      assert_nil status
      assert File.file?(File.join(into, "san", "fake-forms", "forms.csv"))
      assert File.file?(File.join(into, "san", "fake-extra", "forms.csv"))
      assert_match(%r{skipped \(planned\): san/planned-rig}, out)
      assert_match(/2 dataset\(s\) built, 1 skipped \(planned\), 0 failed/, out)
      assert_match(/[Nn]o git/, out, "the no-git contract prints once at the end")
    end
  end

  # A failing feature must not abort the sweep: the census-and-continue
  # doctrine — later features still build, the failure is named with its
  # message, and the command exits nonzero.
  def test_data_build_all_continues_past_a_failure_and_exits_nonzero
    failing_builder = Class.new do
      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        raise Nabu::DataBuild::Error, "rigged failure (test)"
      end
    end
    with_build_env do |config, into|
      failing = DataBuildFake.feature(slug: "san/fake-broken", builder: failing_builder)
      good = DataBuildFake.feature
      out, err, status = with_config(config) do
        with_features([failing, good]) do
          run_cli(["data", "build", "--all", "--into", into])
        end
      end
      assert_equal 1, status
      assert File.file?(File.join(into, "san", "fake-forms", "forms.csv")),
             "the good feature still builds after the failure"
      assert_match(%r{FAILED san/fake-broken: rigged failure}, out + err)
      assert_match(/1 dataset\(s\) built, 0 skipped \(planned\), 1 failed/, out + err)
    end
  end

  def test_data_build_all_and_slug_are_mutually_exclusive_and_one_is_required
    out_dir = Dir.mktmpdir("nabu-data-cli")
    _out, err, status = run_cli(["data", "build", "san/form-lemma", "--all", "--into", out_dir])
    assert_equal 1, status
    assert_match(/either a slug or --all/, err)

    _out, err, status = run_cli(["data", "build", "--into", out_dir])
    assert_equal 1, status
    assert_match(/either a slug or --all/, err)
  end

  private

  def planned_rig
    Nabu::DataBuild::Feature.new(
      slug: "san/planned-rig", language: Nabu::DataBuild::LANGUAGES.fetch("san"),
      title: "Planned rig (no builder yet)", status: :planned, tier: "gold", anchoring: "none",
      inputs: [], canonical_cones: [], rationale: "Exists to pin the planned skip.",
      maintenance: "never — test rig only"
    )
  end

  def with_build_env
    Dir.mktmpdir("nabu-data-cli") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(canonical)
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      yield config, File.join(root, "nabu-data")
    end
  end
end
