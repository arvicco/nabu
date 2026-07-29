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
end
