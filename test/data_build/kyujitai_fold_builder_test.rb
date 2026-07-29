# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"
require "zlib"

# The jpn/kyujitai-fold dataset builder (P52-4): publishes the two-lane
# kyūjitai↔shinjitai pair census — Unihan kJinmeiyoKanji (lane 1) + the
# KANJIDIC2 jōyō-variant lane (lane 2, merges admitted, refusals censused) —
# through Nabu::Ops::JpnFoldBuilder, the SAME resolution seam `rake fold:jpn`
# compiles into Nabu::Jpn (one seam, two consumers). CC BY-SA 4.0: the
# load-bearing KANJIDIC2 lane is EDRDG share-alike (owner ruling D51-a).
#
# Fixture-scale expectations are HAND-COUNTED from the same inputs the ops
# test pins (byte-verbatim Unihan 17.0.0 lines + the trimmed real KANJIDIC2
# sample): 1 jinmeiyō pair (國→国), 2 kanjidic singles (醫→医, 罐→缶), two
# merges (弁←辨瓣辯, 学←學斈斅 — 6 edges), the jinmeiyō-absorbed duplicate
# edge 國→国 deduplicated ⇒ 9 pair rows; 1 refusal (碕, one-to-many).
class DataBuildKyujitaiFoldBuilderTest < Minitest::Test
  KANJIDIC_FIXTURE = File.expand_path("../fixtures/kanjidic2/kanjidic2-sample.xml", __dir__)

  # Byte-verbatim Unihan 17.0.0 lines (the ops-test rig): one jinmeiyō
  # pointer pair, one NFC-identity compat pointer, and the jōyō set the
  # lane-2 filter intersects.
  UNIHAN = <<~TXT
    # Unihan_OtherMappings.txt
    # Date: 2025-07-24 00:00:00 GMT [KL]
    # Unicode Version 17.0.0
    #
    U+570B\tkJinmeiyoKanji\t2010:U+56FD
    U+6E1A\tkJinmeiyoKanji\t2010:U+FA46
    U+56FD\tkJoyoKanji\t2010
    U+533B\tkJoyoKanji\t2010
    U+5F01\tkJoyoKanji\t2010
    U+5D0E\tkJoyoKanji\t2010
    U+57FC\tkJoyoKanji\t2010
    U+7F36\tkJoyoKanji\t2010
    U+5B66\tkJoyoKanji\t2010
  TXT

  PAIR_COLUMNS = %w[ID Old_Form New_Form Lane Source].freeze
  REFUSAL_COLUMNS = %w[ID Form Reason Detail].freeze

  # A tmp environment shaped like the box: canonical/unihan +
  # canonical/edrdg/kanjidic2 cones (non-git → content identity), a
  # sources.yml carrying the REAL adapters so their manifests feed the
  # datapackage sources[] entries.
  def with_env
    Dir.mktmpdir("nabu-kyujitai-fold") do |root|
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(File.join(canonical, "unihan"))
      File.write(File.join(canonical, "unihan", "Unihan_OtherMappings.txt"), UNIHAN)
      kanjidic_dir = File.join(canonical, "edrdg", "kanjidic2")
      FileUtils.mkdir_p(kanjidic_dir)
      Zlib::GzipWriter.open(File.join(kanjidic_dir, "kanjidic2.xml.gz")) do |gz|
        gz.write(File.binread(KANJIDIC_FIXTURE))
      end
      sources = File.join(root, "sources.yml")
      File.write(sources, "unihan:\n  adapter: Nabu::Adapters::Unihan\n  wired: true\n  sync_policy: manual\n" \
                          "edrdg:\n  adapter: Nabu::Adapters::Edrdg\n  wired: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      yield root, canonical, config
    end
  end

  # The registry's real feature, its builder pinned to the tmp canonical tree
  # (the Runner instantiates builders with no arguments; the default
  # canonical_dir is the box's own — tests must never read it).
  def feature_for(canonical)
    builder = Class.new(Nabu::DataBuild::KyujitaiFoldBuilder) do
      define_method(:initialize) { super(canonical_dir: canonical) }
    end
    Nabu::DataBuild.feature("jpn/kyujitai-fold").with(builder: builder)
  end

  def build_direct(canonical, out_dir)
    FileUtils.mkdir_p(out_dir)
    Nabu::DataBuild::KyujitaiFoldBuilder.new(canonical_dir: canonical).build(catalog: nil, out_dir: out_dir)
  end

  def test_the_feature_is_registered_available_and_by_sa
    feature = Nabu::DataBuild.feature("jpn/kyujitai-fold")
    assert_predicate feature, :available?
    assert_equal Nabu::DataBuild::KyujitaiFoldBuilder, feature.builder
    assert_equal "CC-BY-SA-4.0", feature.license, "the KANJIDIC2 lane is EDRDG share-alike (D51-a)"
    assert_equal "gold", feature.tier
    assert_equal "none", feature.anchoring
    assert_equal %w[unihan edrdg], feature.inputs
    assert_equal %w[unihan edrdg], feature.canonical_cones
    assert_equal "jpn", feature.language_code
    assert_equal "jpn-kyujitai-fold", feature.package_name
  end

  def test_build_writes_the_hand_counted_pair_census_with_lane_provenance
    with_env do |root, canonical, _config|
      build_direct(canonical, File.join(root, "out"))
      table = CSV.read(File.join(root, "out", "pairs.csv"), headers: true)
      assert_equal PAIR_COLUMNS, table.headers
      assert_equal 9, table.size, "1 jinmeiyō + 2 singles + 6 merge edges (hand-counted; 國→国 deduplicated)"

      rows = table.map { |row| [row["Old_Form"], row["New_Form"], row["Lane"], row["Source"]] }
      assert_includes rows, %w[國 国 jinmeiyo unihan]
      assert_includes rows, %w[醫 医 kanjidic kanjidic2]
      assert_includes rows, %w[罐 缶 kanjidic kanjidic2]
      %w[辨 瓣 辯].each { |old| assert_includes rows, [old, "弁", "kanjidic-merge", "kanjidic2"] }
      %w[學 斈 斅].each { |old| assert_includes rows, [old, "学", "kanjidic-merge", "kanjidic2"] }
      assert_equal 1, rows.count { |old, new, _lane, _source| old == "國" && new == "国" },
                   "the jinmeiyō-absorbed kanjidic edge duplicates lane 1 and is emitted once"

      ids = table.map { |row| row["ID"] }
      assert_equal ids, ids.uniq, "the minted ID is the PK — unique"
      ids.each { |id| assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, id }
    end
  end

  def test_build_censuses_the_refusals
    with_env do |root, canonical, _config|
      result = build_direct(canonical, File.join(root, "out"))
      table = CSV.read(File.join(root, "out", "refusals.csv"), headers: true)
      assert_equal REFUSAL_COLUMNS, table.headers
      assert_equal 1, table.size, "the fixture refuses exactly 碕 (one-to-many)"
      row = table.first
      assert_equal "碕", row["Form"]
      assert_equal "one-to-many-ambiguity", row["Reason"]
      assert_match(/崎/, row["Detail"])
      assert_match(/埼/, row["Detail"])

      names = result.resources.map(&:name)
      assert_equal %w[pairs refusals], names
      assert_equal ["ID"], result.resources[0].primary_key
      assert_equal ["ID"], result.resources[1].primary_key
      assert_equal 9, result.resources[0].rows
      assert_equal 1, result.resources[1].rows
    end
  end

  def test_the_dataset_and_the_fold_generator_provably_share_one_seam
    with_env do |root, canonical, _config|
      result = build_direct(canonical, File.join(root, "out"))
      seam = Nabu::Ops::JpnFoldBuilder.new(
        mappings_path: File.join(canonical, "unihan", "Unihan_OtherMappings.txt"),
        kanjidic_path: File.join(canonical, "edrdg", "kanjidic2", "kanjidic2.xml.gz")
      )
      table = CSV.read(File.join(root, "out", "pairs.csv"), headers: true)

      jinmeiyo = table.select { |row| row["Lane"] == "jinmeiyo" }
                      .to_h { |row| [row["New_Form"], row["Old_Form"]] }
      assert_equal seam.reform_pairs, jinmeiyo, "lane 1 is the seam's reform-pair census, verbatim"

      kanjidic = table.reject { |row| row["Lane"] == "jinmeiyo" }
                      .map { |row| [row["Old_Form"], row["New_Form"]] }.sort
      expected = seam.kanjidic_edges.map { |edge| [edge.old_form, edge.new_form] }
                                    .reject { |old, new| seam.reform_pairs[new] == old }.sort
      assert_equal expected, kanjidic, "lane 2 is the seam's edge census minus the lane-1 duplicates"

      assert_match(/Nabu::Ops::JpnFoldBuilder/, result.recipe)
      assert_match(/rake fold:jpn/, result.recipe)
    end
  end

  def test_build_twice_is_byte_identical
    with_env do |root, canonical, _config|
      one = File.join(root, "one")
      two = File.join(root, "two")
      build_direct(canonical, one)
      build_direct(canonical, two)
      %w[pairs.csv refusals.csv].each do |name|
        assert_equal File.binread(File.join(one, name)), File.binread(File.join(two, name)), name
      end
    end
  end

  def test_a_missing_input_file_refuses_with_the_sync_remedy
    with_env do |root, canonical, _config|
      FileUtils.rm(File.join(canonical, "unihan", "Unihan_OtherMappings.txt"))
      error = assert_raises(Nabu::DataBuild::Error) do
        build_direct(canonical, File.join(root, "out"))
      end
      assert_match(/Unihan_OtherMappings\.txt/, error.message)
      assert_match(/nabu sync unihan/, error.message)
    end
  end

  def test_runner_builds_the_full_by_sa_dataset_end_to_end
    with_env do |root, canonical, config|
      registry = Nabu::SourceRegistry.load(config.sources_path)
      runner = Nabu::DataBuild::Runner.new(config: config, registry: registry)
      summary = runner.run(feature: feature_for(canonical), into: File.join(root, "nabu-data"))

      out_dir = File.join(root, "nabu-data", "jpn", "kyujitai-fold")
      assert_equal out_dir, summary.out_dir
      %w[pairs.csv refusals.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert File.file?(File.join(out_dir, name)), "expected #{name} in the dataset directory"
      end

      languages = CSV.read(File.join(out_dir, "languages.csv"))
      assert_equal %w[jpn Japanese nucl1643 jpn], languages[1]

      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      assert_equal "jpn-kyujitai-fold", manifest["name"]
      assert_equal [{ "name" => "CC-BY-SA-4.0", "path" => "https://creativecommons.org/licenses/by-sa/4.0/" }],
                   manifest["licenses"], "the manifest is authoritative over the repo-default CC BY (D51-a)"
      assert_equal "gold", manifest.dig("nabu", "tier")
      assert_equal 11, manifest.dig("nabu", "counts", "rows"), "9 pairs + 1 refusal + 1 languages row"
      %w[unihan edrdg].each do |cone|
        sha = manifest.dig("nabu", "derivation", "inputs", cone, "canonical_sha")
        assert_equal Nabu::DerivationFingerprint.canonical_identity(File.join(canonical, cone)), sha
      end
      source_titles = manifest["sources"].map { |source| source["title"] }
      assert_equal 2, manifest["sources"].size
      assert(source_titles.any? { |title| title =~ /Unihan/i })
      assert(manifest["sources"].any? { |source| source["licenses"].first["name"] =~ /BY-SA/ },
             "the EDRDG source entry carries the share-alike licence")

      readme = File.read(File.join(out_dir, "README.md"))
      assert_includes readme, "License: CC-BY-SA-4.0 (https://creativecommons.org/licenses/by-sa/4.0/)."
      assert_includes readme, "This dataset is CC BY-SA 4.0 (inherited share-alike from its inputs); " \
                              "the repository's default license does not apply to it."

      bib = File.read(File.join(out_dir, "sources.bib"))
      assert_match(/kanjidic2/, bib)
      assert_match(/Creative Commons Attribution-ShareAlike Licence \(V4\.0\)/, bib,
                   "the EDRDG licence wording rides the citation (required attribution)")
      assert_match(/unihan/, bib)
      assert_match(/Unicode License V3/, bib)
    end
  end
end
