# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The mul/language-curve builder: the catalog's language_curve published —
# documents and passages per language × century × basis × source, license
# screening row-by-row (nc/odbl/research_private out, censused), silver-
# estimate datings folded into the undated bucket.
class LanguageCurveBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)

  def registry_rig
    { "perseus" => EntryRig.new(manifest: ManifestRig.new(
      name: "Perseus", upstream_url: "https://perseus.example", license: "CC BY-SA 4.0"
    )) }
  end

  def source(slug, license_class)
    Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: license_class)
  end

  def curve(language, century, basis, source, documents, passages)
    @catalog[:language_curve].insert(language: language, century: century, basis: basis,
                                     source_id: source.id, documents: documents, passages: passages)
  end

  def setup
    @catalog = store_test_db
    @perseus = source("perseus", "attribution")
    @ebl = source("ebl", "nc")
    @runic = source("runic", "odbl")
    @private = source("hidden", "research_private")
    curve("lat", 1, "composition", @perseus, 10, 900)
    curve("grc", -5, "composition", @perseus, 4, 300)
    curve("grc", nil, nil, @perseus, 2, 20)
    curve("grc", 3, "silver", @perseus, 1, 5) # folds into undated: 3 docs, 25 passages
    curve("akk", -7, "artifact", @ebl, 50, 400)
    curve("non", 11, "artifact", @runic, 9, 9)
    curve("lat", 1, "composition", @private, 1, 1)
  end

  def build!(out_dir)
    Nabu::DataBuild::LanguageCurveBuilder.new(registry: registry_rig).build(catalog: @catalog, out_dir: out_dir)
  end

  def table(dir) = CSV.read(File.join(dir, "language-curve.csv"), headers: true)

  def test_publishes_the_attestation_census_of_publishable_sources
    Dir.mktmpdir do |dir|
      result = build!(dir)
      csv = table(dir)
      assert_equal %w[ID Language_ID Century Basis Documents Passages Source], csv.headers
      assert_equal [["perseus-grc-undated", "grc", nil, nil, "3", "25", "perseus"],
                    ["perseus-grc-bce5-composition", "grc", "-5", "composition", "4", "300", "perseus"],
                    ["perseus-lat-ce1-composition", "lat", "1", "composition", "10", "900", "perseus"]],
                   csv.map(&:fields),
                   "publishable rows only, silver datings folded undated, (language, century, basis, source) order"
      assert_equal 3, result.resources.first.rows
    end
  end

  def test_the_census_rides_in_band
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      assert_equal 7, evaluation["curve_rows"]
      assert_equal 1, evaluation["silver_dated_rows_folded"]
      assert_equal 3, evaluation["published_rows"]
      assert_equal({ "nc" => 1, "odbl" => 1, "research_private" => 1 }, evaluation["excluded_rows"])
      assert_equal({ "nc" => 400, "odbl" => 9, "research_private" => 1 }, evaluation["excluded_passages"])
    end
  end

  def test_the_recipe_digest_tracks_the_published_slice
    Dir.mktmpdir do |dir|
      first = build!(dir).recipe
      assert_match(/sha256=\h{64}/, first)
      @catalog[:language_curve].where(language: "akk").update(passages: 401)
      assert_equal first, build!(dir).recipe, "a screened row never moves the published fingerprint"
      @catalog[:language_curve].where(language: "lat", source_id: @perseus.id).update(passages: 901)
      refute_equal first, build!(dir).recipe
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::LanguageCurveBuilder.new(registry: registry_rig).build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
