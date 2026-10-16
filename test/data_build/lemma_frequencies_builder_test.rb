# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"
require "digest"

# The mul/lemma-frequencies builder: the catalog's lemma_rollup published
# as per-language frequency tables at century grain — GOLD rows only,
# license screening row-by-row (nc/odbl/research_private out, censused),
# silver-estimate datings folded into the undated bucket (a model-estimated
# century is never published), deterministic lemma-digest IDs.
class LemmaFrequenciesBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)

  def registry_rig
    { "dcs" => EntryRig.new(manifest: ManifestRig.new(
      name: "Digital Corpus of Sanskrit", upstream_url: "https://dcs.example", license: "CC BY 4.0"
    )),
      "aes" => EntryRig.new(manifest: ManifestRig.new(
        name: "Ancient Egyptian Sentences", upstream_url: "https://aes.example", license: "CC BY-SA 4.0"
      )) }
  end

  def source(slug, license_class)
    Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: license_class)
  end

  def rollup(lemma, language, century, basis, grade, source, occurrences, documents)
    @catalog[:lemma_rollup].insert(lemma: lemma, language: language, century: century, basis: basis,
                                   grade: grade, source_id: source.id, occurrences: occurrences,
                                   documents: documents)
  end

  def setup
    @catalog = store_test_db
    @dcs = source("dcs", "attribution")
    @aes = source("aes", "attribution") # a BY-SA lane: attribution class, publishes
    @ebl = source("ebl", "nc")
    @runic = source("runic", "odbl")
    @private = source("hidden", "research_private")
    rollup("deva", "san", -2, "composition", "gold", @dcs, 40, 7)
    rollup("deva", "san", 5, "artifact", "gold", @dcs, 3, 1)
    rollup("agni", "san", nil, nil, "gold", @dcs, 9, 2)
    # A silver-estimate dating: folds into the undated bucket, summed with
    # the existing undated row (disjoint document sets — each document
    # carries exactly one bucket).
    rollup("agni", "san", 12, "silver", "gold", @dcs, 4, 1)
    rollup("nfr", "egy", -20, "artifact", "gold", @aes, 11, 5)
    # Silver GRADE (automatic lemmatization): never published.
    rollup("deva", "san", -2, "composition", "silver", @dcs, 500, 90)
    # The screened slices: never counted, censused by class.
    rollup("lugal", "sux", -21, "artifact", "gold", @ebl, 70, 30)
    rollup("konungr", "non", 10, "artifact", "gold", @runic, 8, 4)
    rollup("deva", "san", -2, "composition", "gold", @private, 6, 2)
  end

  def build!(out_dir)
    Nabu::DataBuild::LemmaFrequenciesBuilder.new(registry: registry_rig)
                                            .build(catalog: @catalog, out_dir: out_dir)
  end

  def table(dir) = CSV.read(File.join(dir, "lemma-frequencies.csv"), headers: true)

  def test_publishes_gold_rows_of_publishable_sources_in_language_lemma_order
    Dir.mktmpdir do |dir|
      result = build!(dir)
      csv = table(dir)
      assert_equal %w[ID Lemma Language_ID Century Basis Occurrences Documents Source], csv.headers
      assert_equal [["nfr", "egy", "-20", "artifact", "11", "5", "aes"],
                    ["agni", "san", nil, nil, "13", "3", "dcs"],
                    ["deva", "san", "-2", "composition", "40", "7", "dcs"],
                    ["deva", "san", "5", "artifact", "3", "1", "dcs"]],
                   csv.map { |row| row.fields[1..] },
                   "gold publishable rows only, ordered (language, lemma, century, basis, source)"
      assert_equal 4, result.resources.first.rows
      assert_equal "lemma_frequencies", result.resources.first.name
    end
  end

  def test_no_screened_or_silver_contribution_hides_in_an_integer
    Dir.mktmpdir do |dir|
      build!(dir)
      csv = table(dir)
      refute_includes csv.map { |row| row["Source"] }, "ebl"
      refute_includes csv.map { |row| row["Source"] }, "runic"
      refute_includes csv.map { |row| row["Source"] }, "hidden"
      deva = csv.find { |row| row["Lemma"] == "deva" && row["Century"] == "-2" }
      assert_equal %w[40 7], deva.values_at("Occurrences", "Documents"),
                   "neither the silver-grade row nor the research_private row adds to the gold count"
    end
  end

  def test_a_silver_estimate_century_is_never_published
    Dir.mktmpdir do |dir|
      build!(dir)
      csv = table(dir)
      refute_includes csv.map { |row| row["Basis"] }, "silver"
      refute_includes csv.map { |row| row["Century"] }, "12"
    end
  end

  def test_ids_are_legal_and_keyed_on_the_lemma_digest
    Dir.mktmpdir do |dir|
      build!(dir)
      ids = table(dir).map { |row| row["ID"] }
      ids.each { |id| assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, id }
      assert_equal ids.uniq, ids
      assert_equal "dcs-san-bce2-composition-L#{Digest::SHA256.hexdigest('deva')[0, 12]}", ids[2]
      assert_equal "dcs-san-undated-L#{Digest::SHA256.hexdigest('agni')[0, 12]}", ids[1]
    end
  end

  def test_the_census_rides_in_band
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      assert_equal 8, evaluation["gold_rollup_rows"]
      assert_equal 1, evaluation["silver_grade_rows_skipped"]
      assert_equal 1, evaluation["silver_dated_rows_folded"]
      assert_equal 4, evaluation["published_rows"]
      assert_equal({ "nc" => 1, "odbl" => 1, "research_private" => 1 }, evaluation["excluded_rows"])
      assert_equal({ "nc" => 70, "odbl" => 8, "research_private" => 6 }, evaluation["excluded_occurrences"])
      assert_equal({ "egy" => 11, "san" => 56 }, evaluation["published_occurrences_by_language"])
    end
  end

  def test_citations_cover_the_published_sources_only
    Dir.mktmpdir do |dir|
      assert_equal %w[aes dcs], build!(dir).citations.map(&:key)
    end
  end

  def test_the_recipe_digest_tracks_the_published_slice
    Dir.mktmpdir do |dir|
      first = build!(dir).recipe
      assert_match(/sha256=\h{64}/, first)
      @catalog[:lemma_rollup].where(lemma: "lugal").update(occurrences: 71)
      assert_equal first, build!(dir).recipe, "a screened row never moves the published fingerprint"
      @catalog[:lemma_rollup].where(lemma: "nfr").update(occurrences: 12)
      refute_equal first, build!(dir).recipe
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::LemmaFrequenciesBuilder.new(registry: registry_rig).build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
