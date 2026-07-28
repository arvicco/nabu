# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"
require "digest"

# The xct/wylie-fold dataset builder (P50-W3): publishes the authored
# Tibetan↔EWTS rule table (config/ewts/rules.csv — the SAME table `rake
# fold:xct` compiles into Nabu::Xct) as a gold-tier nabu-data dataset.
class DataBuildWylieFoldBuilderTest < Minitest::Test
  def build(out_dir)
    FileUtils.mkdir_p(out_dir)
    Nabu::DataBuild::WylieFoldBuilder.new.build(catalog: nil, out_dir: out_dir)
  end

  def test_the_feature_is_available_and_carries_this_builder
    feature = Nabu::DataBuild.feature("xct/wylie-fold")
    assert_predicate feature, :available?
    assert_equal Nabu::DataBuild::WylieFoldBuilder, feature.builder
    assert_empty feature.inputs, "own authorship — no canonical inputs"
    assert_empty feature.canonical_cones
    assert_equal "gold", feature.tier
  end

  def test_build_writes_the_rule_table_in_cldf_shape
    Dir.mktmpdir do |dir|
      result = build(dir)
      table = CSV.read(File.join(dir, "rules.csv"), headers: true)
      assert_equal %w[ID Tibetan EWTS Kind Codepoints Comment], table.headers
      assert_operator table.size, :>=, 90

      ids = table.map { |row| row["ID"] }
      assert_equal ids, ids.uniq
      ids.each { |id| assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, id }

      tibetan = table.map { |row| row["Tibetan"] }
      assert_equal tibetan, tibetan.uniq, "no duplicate Tibetan forms"
      table.each do |row|
        assert_equal format("U+%04X", row["Tibetan"].ord), row["Codepoints"]
        assert_includes %w[consonant subjoined vowel mark punctuation digit], row["Kind"]
        refute_empty row["EWTS"].to_s
      end

      # The one working core, spot-pinned: 30 native consonants present.
      by_char = table.to_h { |row| [row["Tibetan"], row["EWTS"]] }
      assert_equal "k", by_char["ཀ"]
      assert_equal "tsh", by_char["ཚ"]
      assert_equal "'", by_char["འ"]
      assert_equal " ", by_char["་"], "tsheg is the space-analogue"

      resource = result.resources.first
      assert_equal "rules.csv", resource.path
      assert_equal table.size, resource.rows
      field_names = resource.fields.map { |field| field[:name] }
      assert_equal %w[ID Tibetan EWTS Kind Codepoints Comment], field_names
      assert_equal ["ID"], resource.primary_key
    end
  end

  def test_build_twice_is_byte_identical
    Dir.mktmpdir do |dir|
      one = File.join(dir, "one")
      two = File.join(dir, "two")
      build(one)
      build(two)
      assert_equal File.binread(File.join(one, "rules.csv")), File.binread(File.join(two, "rules.csv"))
    end
  end

  def test_recipe_embeds_the_rules_identity_so_the_fingerprint_moves_with_the_rules
    Dir.mktmpdir do |dir|
      result = build(dir)
      digest = Digest::SHA256.file(Nabu::Ops::XctFoldBuilder::RULES_PATH).hexdigest
      assert_includes result.recipe, digest[0, 12],
                      "own-authorship dataset: the recipe is the fingerprint's only moving part, " \
                      "so it must carry the rule table's content identity"
      assert_match(/rake fold:xct/, result.recipe)
    end
  end

  def test_citations_name_unicode_and_the_thl_ewts_scheme
    Dir.mktmpdir do |dir|
      keys = build(dir).citations.map(&:key)
      assert_includes keys, "unicode-tibetan"
      assert_includes keys, "thl-ewts"
    end
  end

  def test_runner_builds_the_full_dataset_end_to_end
    Dir.mktmpdir do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "alpha:\n  adapter: TestAdapter\n  wired: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources))

      summary = runner.run(feature: Nabu::DataBuild.feature("xct/wylie-fold"), into: File.join(root, "nabu-data"))
      out_dir = File.join(root, "nabu-data", "xct", "wylie-fold")
      %w[rules.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert File.file?(File.join(out_dir, name)), "expected #{name}"
      end

      languages = CSV.read(File.join(out_dir, "languages.csv"))
      assert_equal ["xct", "Classical Tibetan", "clas1254", "xct"], languages[1]

      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      assert_equal "xct-wylie-fold", manifest["name"]
      assert_equal "gold", manifest.dig("nabu", "tier")
      assert_empty manifest.dig("nabu", "derivation", "inputs")
      assert_equal summary.fingerprint, manifest.dig("nabu", "derivation", "fingerprint")

      readme = File.read(File.join(out_dir, "README.md"))
      assert_match(/Own authorship/, readme)
      assert_match(/bod/, readme, "the README must state the bod applicability call")
    end
  end
end
