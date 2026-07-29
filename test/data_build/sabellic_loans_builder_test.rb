# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"
require "digest"

# The lat/sabellic-loans dataset builder (P52-5): publishes the hand-curated
# Sabellic (Oscan/Umbrian/Sabine) → Latin loan rows — the SAME curation
# (config/sabellic_loans.yml) that powers the sabellic-osc/xum/sbv dictionary
# shelves — as a CC BY-SA nabu-data dataset (owner ruling D51-a: the
# Wiktionary dual CC BY-SA/GFDL grant is share-alike, so the dataset's
# manifest overrides the repo-default CC BY). Expectations below are
# HAND-COUNTED from the real in-repo YAML (census 2026-07-29): 85 rows total
# — Oscan 48 (23 borrowed, 17 etyma, 1 translit, 4 reconstructed), Umbrian
# 11 (6 borrowed, 4 etyma), Sabine 26 (13 borrowed, 2 etyma).
class DataBuildSabellicLoansBuilderTest < Minitest::Test
  CONFIG = File.expand_path("../../config/sabellic_loans.yml", __dir__)

  def build(out_dir, **)
    FileUtils.mkdir_p(out_dir)
    Nabu::DataBuild::SabellicLoansBuilder.new(**).build(catalog: nil, out_dir: out_dir)
  end

  def read_table(dir)
    CSV.read(File.join(dir, "loans.csv"), headers: true)
  end

  # --- registry ---------------------------------------------------------------

  def test_the_feature_is_available_by_sa_and_carries_this_builder
    feature = Nabu::DataBuild.feature("lat/sabellic-loans")
    refute_nil feature, "lat/sabellic-loans must be registered"
    assert_predicate feature, :available?
    assert_equal Nabu::DataBuild::SabellicLoansBuilder, feature.builder
    assert_equal "CC-BY-SA-4.0", feature.license,
                 "the Wiktionary dual grant is share-alike — BY-SA under owner ruling D51-a"
    assert_equal "gold", feature.tier
    assert_empty feature.inputs, "own curation (config/sabellic_loans.yml) — no canonical corpus inputs"
    assert_empty feature.canonical_cones
    assert_equal "none", feature.anchoring
    assert_equal "lat", feature.language_code, "the loans live in Latin — every row carries a Latin form"
  end

  # --- the table, against the hand-counted census -----------------------------

  def test_build_writes_the_loan_table_at_the_hand_counted_census
    Dir.mktmpdir do |dir|
      result = build(dir)
      table = read_table(dir)
      assert_equal %w[ID Language_ID Form Relation Etymon_Language Etymon Etymon_Translit Source],
                   table.headers
      assert_equal 85, table.size, "48 Oscan + 11 Umbrian + 26 Sabine curated rows"

      by_lang = table.group_by { |row| row["Etymon_Language"] }
      assert_equal({ "osc" => 48, "xum" => 11, "sbv" => 26 }, by_lang.transform_values(&:size))

      borrowed = table.select { |row| row["Relation"] == "borrowed" }
      assert_equal({ "osc" => 23, "xum" => 6, "sbv" => 13 },
                   borrowed.group_by { |row| row["Etymon_Language"] }.transform_values(&:size),
                   "the explicit-borrowing subsets, per the category census")
      assert_equal 85, table.count { |row| %w[borrowed derived].include?(row["Relation"]) },
                   "relation is the curation's closed vocabulary, verbatim"

      etyma = table.reject { |row| row["Etymon"].to_s.empty? }
      assert_equal({ "osc" => 17, "xum" => 4, "sbv" => 2 },
                   etyma.group_by { |row| row["Etymon_Language"] }.transform_values(&:size),
                   "an empty Etymon cell = en.wiktionary cites no source-language form")
      assert_equal 4, table.count { |row| row["Etymon"].to_s.start_with?("*") },
                   "leading * marks a reconstructed etymon, kept verbatim"
      assert_equal 1, table.count { |row| !row["Etymon_Translit"].to_s.empty? },
                   "exactly one curated transliteration (Arrius)"

      assert(table.all? { |row| row["Language_ID"] == "lat" },
             "the loans live in Latin — Language_ID references the one languages.csv row")
      assert_equal result.resources.first.rows, table.size
    end
  end

  def test_spot_rows_pin_the_curation_verbatim
    Dir.mktmpdir do |dir|
      build(dir)
      by_id = read_table(dir).to_h { |row| [row["ID"], row] }

      rufus = by_id.fetch("osc-rufus")
      assert_equal %w[rufus borrowed 𐌓𐌖𐌚𐌓𐌉𐌉𐌔],
                   rufus.values_at("Form", "Relation", "Etymon"),
                   "the Old Italic etymon travels verbatim"

      arrius = by_id.fetch("osc-Arrius")
      assert_equal ["*𐌀𐌓𐌓𐌉𐌄𐌔", "*Arries"], arrius.values_at("Etymon", "Etymon_Translit"),
                   "reconstructed etymon + the one curated transliteration"

      mephitis = by_id.fetch("osc-mephitis")
      assert_equal "derived", mephitis["Relation"], "derived-only — the P17-3 no-marker semantics"

      tofus = by_id.fetch("osc-tofus")
      assert_nil tofus["Etymon"], "no Oscan form cited — the cell stays honestly empty"

      nero = by_id.fetch("sbv-Nero")
      assert_equal %w[Nero borrowed nero], nero.values_at("Form", "Relation", "Etymon")

      mons = by_id.fetch("osc-Mons-Casinus")
      assert_equal "Mons Casinus", mons["Form"], "multi-word lemmas mint hyphenated IDs"
      assert by_id.key?("osc-eius"), "the -eius suffix lemma survives ID minting"

      # rufus/Vibius appear under two source languages — the language prefix
      # keeps the primary key honest.
      assert by_id.key?("xum-rufus")
      assert by_id.key?("xum-Vibius")
    end
  end

  def test_ids_are_unique_cldf_legal_and_the_declared_primary_key
    Dir.mktmpdir do |dir|
      result = build(dir)
      ids = read_table(dir).map { |row| row["ID"] }
      assert_equal ids.uniq, ids, "the minted ID is the primary key — no column tuple is unique"
      ids.each { |id| assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, id }

      resource = result.resources.first
      assert_equal "loans.csv", resource.path
      assert_equal ["ID"], resource.primary_key
      assert_equal(%w[ID Language_ID Form Relation Etymon_Language Etymon Etymon_Translit Source],
                   resource.fields.map { |field| field[:name] })
    end
  end

  def test_values_are_nfc
    Dir.mktmpdir do |dir|
      build(dir)
      read_table(dir).each do |row|
        %w[Form Etymon Etymon_Translit].each do |column|
          value = row[column]
          assert value.nil? || value.unicode_normalized?(:nfc), "#{row['ID']}: #{column} must be NFC"
        end
      end
    end
  end

  def test_build_twice_is_byte_identical
    Dir.mktmpdir do |dir|
      one = File.join(dir, "one")
      two = File.join(dir, "two")
      build(one)
      build(two)
      assert_equal File.binread(File.join(one, "loans.csv")), File.binread(File.join(two, "loans.csv"))
    end
  end

  # --- the re-fingerprint-on-curation-change property -------------------------

  def test_recipe_embeds_the_curation_sha_so_a_curation_change_refingerprints
    Dir.mktmpdir do |dir|
      result = build(File.join(dir, "out"))
      digest = Digest::SHA256.file(CONFIG).hexdigest
      assert_includes result.recipe, digest,
                      "own-curation dataset: the recipe is the fingerprint's only moving part, " \
                      "so it must carry the curation file's content identity (the wylie-fold precedent)"

      modified = File.join(dir, "sabellic_loans.yml")
      File.write(modified, "#{File.read(CONFIG)}# a re-curation\n")
      changed = build(File.join(dir, "out2"), config_path: modified)
      refute_equal result.recipe, changed.recipe
      refute_equal Nabu::DataBuild::Manifest.fingerprint(input_shas: {}, recipe: result.recipe),
                   Nabu::DataBuild::Manifest.fingerprint(input_shas: {}, recipe: changed.recipe),
                   "a curation change must re-fingerprint the dataset"
    end
  end

  # --- citations: the category-page provenance the YAML header records --------

  def test_citations_carry_the_wiktionary_category_provenance_and_the_dual_grant
    Dir.mktmpdir do |dir|
      citations = build(dir).citations
      assert_equal %w[wiktionary-oscan wiktionary-umbrian wiktionary-sabine], citations.map(&:key)

      table = read_table(dir)
      assert_equal({ "osc" => "wiktionary-oscan", "xum" => "wiktionary-umbrian", "sbv" => "wiktionary-sabine" },
                   table.group_by { |row| row["Etymon_Language"] }
                        .transform_values { |rows| rows.map { |row| row["Source"] }.uniq.join(";") },
                   "every row cites its language's category-page citation")

      oscan = citations.first
      assert_includes oscan.fields.fetch("howpublished"),
                      "https://en.wiktionary.org/wiki/Category:Latin_terms_derived_from_Oscan"
      note = oscan.fields.fetch("note")
      assert_includes note, "https://en.wiktionary.org/wiki/Category:Latin_terms_borrowed_from_Oscan"
      assert_includes note, "2026-07-18", "the retrieval date travels in the citation"
      assert_match(/CC BY-SA 4\.0/, note)
      assert_match(/GFDL/, note, "the dual upstream grant is noted; publication picks BY-SA")
    end
  end

  # --- the runner end to end: the BY-SA carve-out must render -----------------

  def test_runner_builds_the_full_by_sa_dataset_end_to_end
    Dir.mktmpdir do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "alpha:\n  adapter: TestAdapter\n  wired: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: "(test)")
      runner = Nabu::DataBuild::Runner.new(config: config, registry: Nabu::SourceRegistry.load(sources))

      summary = runner.run(feature: Nabu::DataBuild.feature("lat/sabellic-loans"),
                           into: File.join(root, "nabu-data"))
      out_dir = File.join(root, "nabu-data", "lat", "sabellic-loans")
      %w[loans.csv languages.csv sources.bib datapackage.json README.md].each do |name|
        assert File.file?(File.join(out_dir, name)), "expected #{name}"
      end

      languages = CSV.read(File.join(out_dir, "languages.csv"))
      assert_equal %w[lat Latin lati1261 lat], languages[1],
                   "the Glottolog-verified Latin statics (lati1261, spine check 2026-07-29)"

      manifest = JSON.parse(File.read(File.join(out_dir, "datapackage.json")))
      assert_equal "lat-sabellic-loans", manifest["name"]
      assert_equal [{ "name" => "CC-BY-SA-4.0",
                      "path" => "https://creativecommons.org/licenses/by-sa/4.0/" }],
                   manifest["licenses"], "the dataset's manifest is authoritative over the repo default"
      assert_equal "gold", manifest.dig("nabu", "tier")
      assert_empty manifest.dig("nabu", "derivation", "inputs")
      assert_equal 85, manifest.dig("nabu", "counts", "rows") - 1, "85 loan rows + the one languages.csv row"
      assert_equal summary.fingerprint, manifest.dig("nabu", "derivation", "fingerprint")

      readme = File.read(File.join(out_dir, "README.md"))
      assert_match(/License: CC-BY-SA-4\.0/, readme)
      assert_match(/the repository's default license does not apply to it/, readme,
                   "the D51-a carve-out sentence must render for a BY-SA feature")
      assert_match(/Own authorship/, readme)
      assert_match(/en\.wiktionary/, readme, "the curation provenance reaches the README")
    end
  end
end
