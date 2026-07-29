# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"
require "digest"

# The jpn/aozora-gaiji dataset builder (P52-3): publishes the checked-in gaiji
# composition-description census (config/gaiji/aozora-descriptions.tsv — the
# source of truth, the wylie-fold precedent) as descriptions.csv, and the IDS
# lane a conservative grammar can prove — derived through
# Nabu::Ops::AozoraIdsBuilder, the SAME grammar `rake gaiji:aozora_ids`
# compiles for the display ladder — as ids.csv.
#
# Expectations are counted against the checked-in census (2026-07-22 snapshot;
# a re-census updates them deliberately): 582 distinct composition formulas,
# 244 derivable IDS, refusals 283 kana-component / 0 replace / 14 subtractive /
# 21 parenthesised / 3 multi-operator / 17 other. Spot rows verified by hand:
# 一／力 (count 13) → ⿱一力; 口＋斗 (count 37) → ⿰口斗; にんべん＋巨 (count 4)
# refuses kana-component; 旗－其＋冉 (count 1) refuses subtractive.
class DataBuildAozoraGaijiBuilderTest < Minitest::Test
  CENSUS = Nabu::Ops::AozoraIdsBuilder::CENSUS_PATH
  DESCRIPTIONS_COLUMNS = %w[ID Description Count Resolution Source].freeze
  IDS_COLUMNS = %w[ID Description IDS Source].freeze

  def build(out_dir)
    FileUtils.mkdir_p(out_dir)
    Nabu::DataBuild::AozoraGaijiBuilder.new.build(catalog: nil, out_dir: out_dir)
  end

  def run_build(root, into: File.join(root, "nabu-data"))
    sources = File.join(root, "sources.yml")
    File.write(sources, "alpha:\n  adapter: TestAdapter\n  wired: true\n  sync_policy: manual\n")
    config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                              sources_path: sources, config_path: "(test)")
    runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources))
    runner.run(feature: Nabu::DataBuild.feature("jpn/aozora-gaiji"), into: into)
  end

  def test_the_feature_is_available_with_the_census_tsv_as_source_of_truth
    feature = Nabu::DataBuild.feature("jpn/aozora-gaiji")
    assert_predicate feature, :available?
    assert_equal Nabu::DataBuild::AozoraGaijiBuilder, feature.builder
    assert_empty feature.inputs, "the checked-in census TSV is the source of truth — the wylie-fold precedent"
    assert_empty feature.canonical_cones
    assert_equal "gold", feature.tier
    assert_equal "jpn", feature.language_code
  end

  def test_build_writes_both_lanes_in_cldf_shape_with_the_censused_counts
    Dir.mktmpdir do |dir|
      result = build(dir)

      descriptions = CSV.read(File.join(dir, "descriptions.csv"), headers: true)
      assert_equal DESCRIPTIONS_COLUMNS, descriptions.headers
      assert_equal 582, descriptions.size, "the 2026-07-22 census: 582 distinct composition formulas"

      ids = CSV.read(File.join(dir, "ids.csv"), headers: true)
      assert_equal IDS_COLUMNS, ids.headers
      assert_equal 244, ids.size, "244 formulas are mechanically derivable"

      tally = descriptions.map { |row| row["Resolution"] }.tally
      assert_equal({ "ids" => 244, "kana-component" => 283, "subtractive" => 14,
                     "parenthesised" => 21, "multi-operator" => 3, "other" => 17 }, tally)

      assert_equal(%w[descriptions ids], result.resources.map(&:name))
      assert_equal [582, 244], result.resources.map(&:rows)
      assert_equal ["ID"], result.resources[0].primary_key
      assert_equal ["ID"], result.resources[1].primary_key
    end
  end

  def test_the_two_lanes_join_on_id_and_description
    Dir.mktmpdir do |dir|
      build(dir)
      descriptions = CSV.read(File.join(dir, "descriptions.csv"), headers: true)
      ids = CSV.read(File.join(dir, "ids.csv"), headers: true)

      derived = descriptions.select { |row| row["Resolution"] == "ids" }
      assert_equal derived.map { |row| row["ID"] }, ids.map { |row| row["ID"] },
                   "ids.csv rows are exactly the Resolution=ids census rows, same order, same IDs"
      assert_equal(derived.map { |row| row["Description"] }, ids.map { |row| row["Description"] })

      [descriptions, ids].each do |table|
        table_ids = table.map { |row| row["ID"] }
        assert_equal table_ids, table_ids.uniq, "IDs are unique — the PK"
        table_ids.each { |id| assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, id }
        table.each { |row| assert_equal "aozora", row["Source"] }
      end
    end
  end

  def test_spot_rows_counts_ids_and_refusal_classes
    Dir.mktmpdir do |dir|
      build(dir)
      descriptions = CSV.read(File.join(dir, "descriptions.csv"), headers: true)
      by_desc = descriptions.to_h { |row| [row["Description"], row] }

      assert_equal "13", by_desc["一／力"]["Count"]
      assert_equal "ids", by_desc["一／力"]["Resolution"]
      assert_equal "37", by_desc["口＋斗"]["Count"]
      assert_equal "4", by_desc["にんべん＋巨"]["Count"]
      assert_equal "kana-component", by_desc["にんべん＋巨"]["Resolution"],
                   "a kana radical NAME is not a component glyph — refused, never guessed"
      assert_equal "subtractive", by_desc["旗－其＋冉"]["Resolution"]

      ids = CSV.read(File.join(dir, "ids.csv"), headers: true).to_h { |row| [row["Description"], row["IDS"]] }
      assert_equal "⿱一力", ids["一／力"]
      assert_equal "⿰口斗", ids["口＋斗"]
      refute ids.key?("にんべん＋巨")

      # The ID is deterministic and content-derived (the description cannot
      # survive the CLDF identifier class, so it is digested).
      expected = "g-#{Digest::SHA256.hexdigest('一／力')[0, 12]}"
      assert_equal expected, by_desc["一／力"]["ID"]
    end
  end

  # The shared-seam claim, live: the dataset's IDS lane equals the ops
  # builder's lane for the same census bytes — one grammar, two consumers.
  def test_the_dataset_and_the_ops_ids_lane_share_one_grammar
    Dir.mktmpdir do |dir|
      build(dir)
      ids = CSV.read(File.join(dir, "ids.csv"), headers: true).to_h { |row| [row["Description"], row["IDS"]] }
      assert_equal Nabu::Ops::AozoraIdsBuilder.new(census_path: CENSUS).lane, ids
    end
  end

  def test_a_rigged_census_path_flows_through_columns_and_classification
    Dir.mktmpdir do |root|
      census = File.join(root, "census.tsv")
      File.write(census, "# comment\n3\t口＋斗\n1\t一／力\n2\tにんべん＋巨\n")
      out_dir = File.join(root, "out")
      FileUtils.mkdir_p(out_dir)
      Nabu::DataBuild::AozoraGaijiBuilder.new(census_path: census).build(catalog: nil, out_dir: out_dir)

      descriptions = CSV.read(File.join(out_dir, "descriptions.csv"), headers: true)
      assert_equal %w[にんべん＋巨 一／力 口＋斗], descriptions.map { |row| row["Description"] },
                   "rows sort by description codepoint order — the generated TSV's stable-diff discipline"
      assert_equal(%w[kana-component ids ids], descriptions.map { |row| row["Resolution"] })
      assert_equal 2, CSV.read(File.join(out_dir, "ids.csv"), headers: true).size
    end
  end

  def test_runner_builds_the_full_dataset_end_to_end
    Dir.mktmpdir do |root|
      summary = run_build(root)
      out_dir = File.join(root, "nabu-data", "jpn", "aozora-gaiji")
      assert_equal out_dir, summary.out_dir
      %w[descriptions.csv ids.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert File.file?(File.join(out_dir, name)), "expected #{name}"
      end
      assert_equal 827, summary.rows, "582 census + 244 ids + 1 languages row"

      languages = CSV.read(File.join(out_dir, "languages.csv"))
      assert_equal %w[jpn Japanese nucl1643 jpn], languages[1]

      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      assert_equal "jpn-aozora-gaiji", manifest["name"]
      assert_equal "gold", manifest.dig("nabu", "tier"), "the census formulas are hand-curated upstream text"
      assert_empty manifest.dig("nabu", "derivation", "inputs"),
                   "no canonical cone: the build is a pure function of the checked-in TSV"

      recipe = manifest.dig("nabu", "derivation", "recipe")
      assert_includes recipe, Digest::SHA256.file(CENSUS).hexdigest,
                      "no-cone dataset: the recipe is the fingerprint's only moving part, so it must " \
                      "carry the census TSV's content identity (the wylie-fold precedent)"
      assert_match(/gaiji:aozora_ids/, recipe, "the recipe names the shared grammar seam")

      readme = File.read(File.join(out_dir, "README.md"))
      assert_match(/structural claim/i, readme, "the IDS honesty bar is stated where scholars read")
      assert_match(/pd\.read_csv/, readme)
      assert_match(/source of truth/, readme, "the input-declaration call is stated")
      assert_match(/Aozora/, readme)

      bib = File.read(File.join(out_dir, "sources.bib"))
      assert_match(/@misc\{aozora,/, bib)
      assert_match(/青空文庫/, bib)
    end
  end

  def test_building_twice_is_byte_identical
    Dir.mktmpdir do |root|
      first = run_build(root, into: File.join(root, "first"))
      second = run_build(root, into: File.join(root, "second"))
      assert_equal first.fingerprint, second.fingerprint
      %w[descriptions.csv ids.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert_equal File.read(File.join(first.out_dir, name)), File.read(File.join(second.out_dir, name)),
                     "#{name} must be byte-identical across builds — the dataset is deterministic"
      end
    end
  end
end
