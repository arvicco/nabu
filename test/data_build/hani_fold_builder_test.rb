# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"

# The zho/hani-fold dataset builder (P52-3): publishes the Han
# trad↔simp↔z-variant fold — resolved from canonical/unihan/Unihan_Variants.txt
# through Nabu::Ops::HaniFoldBuilder, the SAME seam `rake fold:hani` compiles
# into Nabu::Hani — as pairs.csv plus the per-row refusal census refusals.csv.
# Expectations below are HAND-RESOLVED from test/fixtures/unihan/
# Unihan_Variants.txt (real upstream lines, Unicode 17.0.0):
#
#   pairs: 4 —  亚→亞 (direct kTraditionalVariant),
#               弃→棄 (reverse-only: only 棄's kSimplifiedVariant names it),
#               爱→愛 (direct), 𫚍→魵 (reverse-only, supplementary-plane)
#   refusals: 1 — 体 self-lists among its own traditional variants (a
#               traditional word in its own right; folding would merge words)
#   excluded: 8 semantic-variant lines never enter the graph; the
#               kSpoofingVariant lines are not read at all
class DataBuildHaniFoldBuilderTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("unihan"), "Unihan_Variants.txt")
  PAIRS_COLUMNS = %w[ID Variant Traditional Variant_Codepoint Traditional_Codepoint Source].freeze
  REFUSALS_COLUMNS = %w[ID Form Reason Source].freeze

  # A tmp environment shaped like the box: a canonical/unihan cone holding the
  # fixture variants file (non-git → content identity), a sources.yml carrying
  # the real adapter (its manifest feeds the datapackage sources[]).
  def with_env
    Dir.mktmpdir("nabu-hani-fold") do |root|
      canonical = File.join(root, "canonical")
      cone = File.join(canonical, "unihan")
      FileUtils.mkdir_p(cone)
      FileUtils.cp(FIXTURE, File.join(cone, "Unihan_Variants.txt"))
      sources = File.join(root, "sources.yml")
      File.write(sources, "unihan:\n  adapter: Nabu::Adapters::Unihan\n  wired: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      yield root, canonical, config
    end
  end

  # The registry's real feature, its builder pinned to the tmp canonical tree
  # (the Runner instantiates builders with no arguments; the default
  # canonical_dir is the box's own — tests must never read it).
  def feature_for(canonical)
    builder = Class.new(Nabu::DataBuild::HaniFoldBuilder) do
      define_method(:initialize) { super(canonical_dir: canonical) }
    end
    Nabu::DataBuild.feature("zho/hani-fold").with(builder: builder)
  end

  def run_build(root, canonical, config, into: File.join(root, "nabu-data"))
    registry = Nabu::SourceRegistry.load(config.sources_path)
    runner = Nabu::DataBuild::Runner.new(config: config, registry: registry)
    runner.run(feature: feature_for(canonical), into: into)
  end

  def read_pairs(out_dir)
    CSV.read(File.join(out_dir, "pairs.csv"), headers: true)
  end

  def test_the_feature_is_available_and_declares_the_unihan_cone
    feature = Nabu::DataBuild.feature("zho/hani-fold")
    assert_predicate feature, :available?
    assert_equal Nabu::DataBuild::HaniFoldBuilder, feature.builder
    assert_equal ["unihan"], feature.inputs, "the source of truth STAYS upstream Unihan"
    assert_equal ["unihan"], feature.canonical_cones
    assert_equal "gold-derived", feature.tier
    assert_equal Nabu::Adapters::Unihan::LANGUAGE, feature.language_code,
                 "the dataset files under the same pan-CJK macro tag Nabu's unihan shelf uses"
  end

  def test_end_to_end_build_writes_the_full_dataset_directory
    with_env do |root, canonical, config|
      summary = run_build(root, canonical, config)

      out_dir = File.join(root, "nabu-data", "zho", "hani-fold")
      assert_equal out_dir, summary.out_dir
      %w[pairs.csv refusals.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert File.file?(File.join(out_dir, name)), "expected #{name} in the dataset directory"
      end

      pairs = read_pairs(out_dir)
      assert_equal PAIRS_COLUMNS, pairs.headers
      assert_equal 4, pairs.size, "hand-resolved from the fixture: 亚 弃 爱 𫚍"

      refusals = CSV.read(File.join(out_dir, "refusals.csv"), headers: true)
      assert_equal REFUSALS_COLUMNS, refusals.headers
      assert_equal 1, refusals.size, "hand-resolved: only 体 refuses (self-listing)"

      assert_equal 6, summary.rows, "4 pairs + 1 refusal + 1 languages row"

      languages = CSV.read(File.join(out_dir, "languages.csv"))
      assert_equal %w[ID Name Glottocode ISO639P3code], languages[0]
      assert_equal ["zho", "Chinese", nil, "zho"], languages[1],
                   "zho is an ISO 639-3 macrolanguage — Glottolog assigns it no glottocode; empty is honest"
    end
  end

  def test_the_pairs_are_the_resolved_fold_with_honest_ids_and_codepoints
    with_env do |root, canonical, config|
      pairs = read_pairs(run_build(root, canonical, config).out_dir)

      by_variant = pairs.to_h { |row| [row["Variant"], row["Traditional"]] }
      assert_equal({ "亚" => "亞", "弃" => "棄", "爱" => "愛", "𫚍" => "魵" }, by_variant)

      first = pairs[0]
      assert_equal "U-4E9A", first["ID"], "the ID is minted from the variant codepoint"
      assert_equal "U+4E9A", first["Variant_Codepoint"]
      assert_equal "U+4E9E", first["Traditional_Codepoint"]
      assert_equal "unihan", first["Source"], "every row cites the sources.bib key"

      ids = pairs.map { |row| row["ID"] }
      assert_equal ids, ids.uniq, "IDs are unique — the PK"
      ids.each { |id| assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, id }
      variants = pairs.map { |row| row["Variant"] }
      assert_equal variants, variants.uniq, "one fold per variant codepoint"
      pairs.each do |row|
        refute_includes variants, row["Traditional"],
                        "every Traditional is a fixed point — never itself a variant key"
      end
    end
  end

  def test_the_refusal_census_is_published_per_row_with_its_reason
    with_env do |root, canonical, config|
      refusals = CSV.read(File.join(run_build(root, canonical, config).out_dir, "refusals.csv"), headers: true)
      row = refusals[0]
      assert_equal "体", row["Form"]
      assert_equal "self-listing", row["Reason"],
                   "体 is a traditional word in its own right — folding 体→體 would merge two words"
      assert_equal "self-listing-U-4F53", row["ID"]
      assert_equal "unihan", row["Source"]
    end
  end

  # The design rule from the fold-in audit: the ops builder and the dataset
  # builder provably use ONE resolution path. Same input ⇒ identical fold map;
  # and a change to the cone's bytes moves BOTH consumers identically — the
  # dataset reads through the live seam, never a baked copy.
  def test_the_dataset_and_the_ops_fold_share_one_resolution_path
    with_env do |root, canonical, config|
      variants = File.join(canonical, "unihan", "Unihan_Variants.txt")
      pairs = read_pairs(run_build(root, canonical, config).out_dir)
      ops_table = Nabu::Ops::HaniFoldBuilder.new(variants_path: variants).table
      assert_equal(ops_table, pairs.to_h { |row| [row["Variant"], row["Traditional"]] })

      File.open(variants, "a") { |f| f.puts "U+4E1C\tkTraditionalVariant\tU+6771" } # 东→東
      out_dir = File.join(root, "again")
      FileUtils.mkdir_p(out_dir)
      Nabu::DataBuild::HaniFoldBuilder.new(canonical_dir: canonical).build(catalog: nil, out_dir: out_dir)
      grown = read_pairs(out_dir).to_h { |row| [row["Variant"], row["Traditional"]] }
      assert_equal "東", grown["东"]
      assert_equal Nabu::Ops::HaniFoldBuilder.new(variants_path: variants).table, grown
    end
  end

  def test_the_manifest_describes_the_derivation_honestly
    with_env do |root, canonical, config|
      summary = run_build(root, canonical, config)
      manifest = JSON.parse(File.read(File.join(summary.out_dir, "datapackage.json")))

      assert_equal "zho-hani-fold", manifest["name"]
      assert_equal "gold-derived", manifest.dig("nabu", "tier"),
                   "mechanical resolution of upstream-declared variants — the verb-lemma parity"
      assert_equal "none", manifest.dig("nabu", "anchoring", "kind")
      assert_equal(%w[pairs refusals languages sources], manifest["resources"].map { |r| r["name"] })
      assert_equal ["ID"], manifest["resources"][0]["schema"]["primaryKey"]

      cone_sha = manifest.dig("nabu", "derivation", "inputs", "unihan", "canonical_sha")
      assert_equal Nabu::DerivationFingerprint.canonical_identity(File.join(canonical, "unihan")), cone_sha

      recipe = manifest.dig("nabu", "derivation", "recipe")
      assert_match(/fold:hani/, recipe, "the recipe names the shared seam")
      assert_match(/refus/, recipe)
      assert_match(/semantic/i, recipe, "the structural exclusion is part of the derivation description")

      source = manifest["sources"].first
      assert_equal "Unihan — the Unicode Han Database", source["title"]
      assert_equal cone_sha, source["version"]
      assert_match(/Unicode License V3/, source["licenses"].first["name"])
    end
  end

  def test_the_readme_carries_the_census_the_field_discipline_and_a_pandas_one_liner
    with_env do |root, canonical, config|
      summary = run_build(root, canonical, config)
      readme = File.read(File.join(summary.out_dir, "README.md"))
      assert_match(/semantic/i, readme, "the semantic-variant exclusion is stated where scholars read")
      assert_match(/1 self-listing/, readme, "the refusal census numbers ride in-band")
      assert_match(/4 fold pairs/, readme)
      assert_match(/pd\.read_csv/, readme)
      assert_match(/lzh/, readme, "the macro-tag applicability call (kanripo/cbeta) is stated")
      assert_match(/17\.0\.0/, readme, "the Unihan version at derivation is quoted")

      bib = File.read(File.join(summary.out_dir, "sources.bib"))
      assert_match(/@misc\{unihan,/, bib)
      assert_match(/Unicode/, bib)
    end
  end

  def test_building_twice_is_byte_identical
    with_env do |root, canonical, config|
      first = run_build(root, canonical, config, into: File.join(root, "first"))
      second = run_build(root, canonical, config, into: File.join(root, "second"))
      assert_equal first.fingerprint, second.fingerprint
      %w[pairs.csv refusals.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert_equal File.read(File.join(first.out_dir, name)), File.read(File.join(second.out_dir, name)),
                     "#{name} must be byte-identical across builds — the dataset is deterministic"
      end
    end
  end

  def test_a_missing_canonical_input_refuses_with_a_sync_hint
    Dir.mktmpdir("nabu-hani-fold-missing") do |root|
      builder = Nabu::DataBuild::HaniFoldBuilder.new(canonical_dir: File.join(root, "canonical"))
      error = assert_raises(Nabu::DataBuild::Error) do
        builder.build(catalog: nil, out_dir: root)
      end
      assert_match(/unihan/, error.message)
      assert_match(/sync/, error.message)
    end
  end
end
