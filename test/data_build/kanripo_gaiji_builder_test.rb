# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"
require "digest"

# The lzh/kanripo-gaiji dataset builder (P52-4): publishes the hand-curated
# Kanripo gaiji display ladder — the three config/gaiji/kanripo*.tsv lanes
# (faithful / IDS / substitute) the `--display reading` mode loads through
# Nabu::Display.load_gaiji_map — as a gold-tier CC BY-SA 4.0 dataset (the
# curation derives from KR-Gaiji's charlist, kanripo org grant CC BY-SA 4.0;
# owner ruling D51-a). The in-repo TSVs ARE the data (the wylie-fold
# own-curation precedent): expectations below are the real lane censuses —
# 427 faithful, 0 IDS, 562 substitutes (headers + grep-counted 2026-07-29).
class DataBuildKanripoGaijiBuilderTest < Minitest::Test
  GAIJI_DIR = File.join(Nabu::Config::PROJECT_ROOT, "config", "gaiji")

  def build(out_dir)
    FileUtils.mkdir_p(out_dir)
    Nabu::DataBuild::KanripoGaijiBuilder.new.build(catalog: nil, out_dir: out_dir)
  end

  def test_the_feature_is_registered_available_and_by_sa
    feature = Nabu::DataBuild.feature("lzh/kanripo-gaiji")
    assert_predicate feature, :available?
    assert_equal Nabu::DataBuild::KanripoGaijiBuilder, feature.builder
    assert_equal "CC-BY-SA-4.0", feature.license, "curated from the BY-SA KR-Gaiji charlist (D51-a)"
    assert_equal "gold", feature.tier
    assert_equal "none", feature.anchoring
    assert_empty feature.inputs,
                 "own curation, pinned to the charlist commit the TSV headers record — " \
                 "declaring the live kr-gaiji cone would cite bytes the rows were not curated from"
    assert_empty feature.canonical_cones
    assert_equal "lzh", feature.language_code, "kanripo passages are lzh (MandokuParser::LANGUAGE)"
    assert_equal "lzh-kanripo-gaiji", feature.package_name
  end

  def test_build_writes_the_three_ladder_lanes_with_the_real_censuses
    Dir.mktmpdir do |dir|
      result = build(dir)

      faithful = CSV.read(File.join(dir, "faithful.csv"), headers: true)
      assert_equal %w[ID Glyph], faithful.headers
      assert_equal 427, faithful.size, "the faithful lane census (kanripo.tsv header)"
      by_ref = faithful.to_h { |row| [row["ID"], row["Glyph"]] }
      assert_equal "𫠦", by_ref["KR0001"]
      assert_equal "將", by_ref["KR0005"]
      assert_equal "沔", by_ref["KR0198"], "the one IDS-resolved composition lands faithful (Z-source 沔)"
      assert_equal "𡙋", by_ref["KR4014"]

      ids = CSV.read(File.join(dir, "ids.csv"), headers: true)
      assert_equal %w[ID IDS], ids.headers
      assert_equal 0, ids.size, "the IDS lane ships empty — its one candidate resolved faithful"

      substitutes = CSV.read(File.join(dir, "substitutes.csv"), headers: true)
      assert_equal %w[ID Substitute], substitutes.headers
      assert_equal 562, substitutes.size, "the substitute lane census (kanripo-substitutes.tsv header)"
      sub_by_ref = substitutes.to_h { |row| [row["ID"], row["Substitute"]] }
      assert_equal "若", sub_by_ref["KR0002"]
      assert_equal "甯", sub_by_ref["KR5189"]

      assert_equal %w[faithful ids substitutes], result.resources.map(&:name)
      assert_equal [427, 0, 562], result.resources.map(&:rows)
      result.resources.each { |resource| assert_equal ["ID"], resource.primary_key }
    end
  end

  def test_the_lanes_are_disjoint_and_every_id_is_a_kr_ref
    Dir.mktmpdir do |dir|
      build(dir)
      lanes = %w[faithful.csv ids.csv substitutes.csv].map do |name|
        CSV.read(File.join(dir, name), headers: true).map { |row| row["ID"] }
      end
      lanes.each do |ids|
        assert_equal ids, ids.uniq
        ids.each { |id| assert_match(/\AKR\d{4}\z/, id) }
        assert_equal ids, ids.sort, "each lane is emitted in ref order (deterministic)"
      end
      assert_empty lanes[0] & lanes[2], "faithful and substitute lanes are disjoint by ref (the ladder contract)"
      assert_empty lanes[0] & lanes[1]
    end
  end

  def test_the_dataset_and_the_display_ladder_provably_read_one_seam
    Dir.mktmpdir do |dir|
      build(dir)
      faithful = CSV.read(File.join(dir, "faithful.csv"), headers: true).to_h { |row| [row["ID"], row["Glyph"]] }
      assert_equal Nabu::Display.load_gaiji_map(File.join(GAIJI_DIR, "kanripo.tsv")).to_h, faithful,
                   "the dataset publishes exactly what --display reading loads (same loader, same file)"
      substitutes = CSV.read(File.join(dir, "substitutes.csv"), headers: true)
                       .to_h { |row| [row["ID"], row["Substitute"]] }
      assert_equal Nabu::Display.load_gaiji_map(File.join(GAIJI_DIR, "kanripo-substitutes.tsv")).to_h, substitutes
      assert_empty Nabu::Display.load_gaiji_map(File.join(GAIJI_DIR, "kanripo-ids.tsv"))
    end
  end

  def test_the_recipe_embeds_the_three_file_identities_and_the_upstream_pin
    Dir.mktmpdir do |dir|
      result = build(dir)
      %w[kanripo.tsv kanripo-ids.tsv kanripo-substitutes.tsv].each do |name|
        digest = Digest::SHA256.file(File.join(GAIJI_DIR, name)).hexdigest
        assert_includes result.recipe, digest[0, 12],
                        "own-curation dataset: the recipe must carry #{name}'s content identity"
      end
      assert_match(/662fd61d/, result.recipe, "the charlist commit the curation is pinned to")
      assert_match(/--display reading/, result.recipe)
    end
  end

  def test_build_twice_is_byte_identical
    Dir.mktmpdir do |dir|
      one = File.join(dir, "one")
      two = File.join(dir, "two")
      build(one)
      build(two)
      %w[faithful.csv ids.csv substitutes.csv].each do |name|
        assert_equal File.binread(File.join(one, name)), File.binread(File.join(two, name)), name
      end
    end
  end

  def test_runner_builds_the_full_by_sa_dataset_end_to_end
    Dir.mktmpdir do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "alpha:\n  adapter: TestAdapter\n  wired: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources))
      summary = runner.run(feature: Nabu::DataBuild.feature("lzh/kanripo-gaiji"), into: File.join(root, "nabu-data"))

      out_dir = File.join(root, "nabu-data", "lzh", "kanripo-gaiji")
      assert_equal out_dir, summary.out_dir
      %w[faithful.csv ids.csv substitutes.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert File.file?(File.join(out_dir, name)), "expected #{name} in the dataset directory"
      end

      languages = CSV.read(File.join(out_dir, "languages.csv"))
      assert_equal %w[lzh], [languages[1][0]]
      assert_equal ["lzh", "Classical Chinese", "lite1248", "lzh"], languages[1]

      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      assert_equal "lzh-kanripo-gaiji", manifest["name"]
      assert_equal [{ "name" => "CC-BY-SA-4.0", "path" => "https://creativecommons.org/licenses/by-sa/4.0/" }],
                   manifest["licenses"], "the manifest is authoritative over the repo-default CC BY (D51-a)"
      assert_equal 990, manifest.dig("nabu", "counts", "rows"), "427 + 0 + 562 lane rows + 1 languages row"
      assert_empty manifest.dig("nabu", "derivation", "inputs"),
                   "no build-time cones — provenance is the recipe's TSV shas + the recorded charlist pin"

      readme = File.read(File.join(out_dir, "README.md"))
      assert_includes readme, "License: CC-BY-SA-4.0 (https://creativecommons.org/licenses/by-sa/4.0/)."
      assert_includes readme, "This dataset is CC BY-SA 4.0 (inherited share-alike from its inputs); " \
                              "the repository's default license does not apply to it."
      assert_match(/662fd61d/, readme, "the notes state the exact charlist commit the curation derives from")
      assert_match(/2B1A|⬚/, readme, "the notes document the placeholder rung — unresolved refs are censused")

      bib = File.read(File.join(out_dir, "sources.bib"))
      assert_match(/kr-gaiji/, bib)
      assert_match(/Licensed as CC BY SA 4\.0/, bib, "the kanripo org grant wording rides the citation")
    end
  end
end
