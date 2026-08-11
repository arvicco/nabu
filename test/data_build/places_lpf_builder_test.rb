# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"
require "json"

# The mul/places-lpf builder (P73-5): the referenced-places gazetteer in
# Linked Places Format v1.3 + the LP-TSV sidecar — one Feature per
# published claim, titles/coords from place_index, attested names cited
# to their corpora, when-spans aggregated from document dates, closeMatch
# links from place_crosswalk. License slicing as in 73-4.
class PlacesLpfBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)

  def registry_rig
    { "alpha" => EntryRig.new(manifest: ManifestRig.new(
      name: "Alpha Corpus", upstream_url: "https://alpha.example", license: "CC BY-SA 4.0"
    )) }
  end

  def setup
    @catalog = store_test_db
    @alpha = Nabu::Store::Source.create(slug: "alpha", name: "Alpha", adapter_class: "TestAdapter",
                                        license_class: "attribution")
    @closed = Nabu::Store::Source.create(slug: "closed", name: "Closed", adapter_class: "TestAdapter",
                                         license_class: "nc")
    [
      ["urn:nabu:alpha:d1", @alpha, "Bovianum", "pleiades:432725", -425, -375],
      ["urn:nabu:alpha:d2", @alpha, "Bouianom", "pleiades:432725", -300, -200],
      ["urn:nabu:alpha:d3", @alpha, "Teate", "tm:2711", nil, nil],
      ["urn:nabu:closed:d4", @closed, "Hidden", "pleiades:687928", -100, -50]
    ].each do |urn, source, name, ref, not_before, not_after|
      doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn,
                                         language: "la", content_sha256: "x", revision: 1)
      @catalog[:document_axes].insert(document_id: doc.id, place_name: name, place_ref: ref,
                                      not_before: not_before, not_after: not_after,
                                      axis_source: source.slug)
    end
    @catalog[:place_index].insert(gazetteer: "pleiades", place_id: "432725", title: "Bovianum",
                                  lat: 41.482, lon: 14.472, place_types_json: '["settlement"]',
                                  time_periods_json: "[]", position: 0)
    @catalog[:place_crosswalk].insert(source: "cigs", gazetteer_a: "pleiades", id_a: "432725",
                                      gazetteer_b: "tm", id_b: "12345")
  end

  def build!(out_dir)
    Nabu::DataBuild::PlacesLpfBuilder.new(registry: registry_rig)
                                     .build(catalog: @catalog, out_dir: out_dir)
  end

  def features(dir)
    JSON.parse(File.read(File.join(dir, "places.lpf.geojson"))).fetch("features")
  end

  def test_one_lpf_feature_per_published_claim
    Dir.mktmpdir do |dir|
      build!(dir)
      all = features(dir)
      assert_equal %w[pleiades:432725 tm:2711], all.map { |f| f["properties"]["nabu_ref"] }.sort,
                   "one Feature per published claim; the nc-source claim never appears"

      bovianum = all.find { |f| f["properties"]["nabu_ref"] == "pleiades:432725" }
      assert_equal "Feature", bovianum["type"]
      assert_equal "https://pleiades.stoa.org/places/432725", bovianum["@id"]
      assert_equal "Bovianum", bovianum["properties"]["title"], "the index title wins"
      assert_equal ["P"], bovianum["properties"]["fclasses"], "settlement maps to P"
      assert_equal [14.472, 41.482], bovianum["geometry"]["coordinates"]

      names = bovianum["names"].map { |n| n["toponym"] }.sort
      assert_equal %w[Bouianom Bovianum], names, "every distinct attested spelling rides names[]"
      assert_equal [{ "label" => "alpha" }],
                   bovianum["names"].first["citations"], "each toponym cites its corpus"

      timespan = bovianum["when"]["timespans"].first
      assert_equal({ "in" => "-0425" }, timespan["start"])
      assert_equal({ "in" => "-0200" }, timespan["end"])

      assert_equal [{ "type" => "closeMatch", "identifier" => "https://www.trismegistos.org/place/12345" }],
                   bovianum["links"], "the crosswalk rides as closeMatch"
    end
  end

  def test_a_claim_without_an_index_row_falls_back_honestly
    Dir.mktmpdir do |dir|
      build!(dir)
      teate = features(dir).find { |f| f["properties"]["nabu_ref"] == "tm:2711" }
      assert_equal "Teate", teate["properties"]["title"], "the attested name is the fallback title"
      assert_nil teate["geometry"], "no coordinates are ever invented"
      refute teate.key?("when"), "no dated referencing docs, no when"
    end
  end

  def test_the_lp_tsv_sidecar_carries_the_upload_contract
    Dir.mktmpdir do |dir|
      build!(dir)
      table = CSV.read(File.join(dir, "places.tsv"), headers: true, col_sep: "\t")
      assert_equal %w[id title title_source fclasses start end lon lat matches], table.headers
      row = table.find { |r| r["id"] == "pleiades:432725" }
      assert_equal ["Bovianum", "pleiades", "P", "-425", "-200"],
                   row.values_at("title", "title_source", "fclasses", "start", "end")
      assert_equal "https://www.trismegistos.org/place/12345", row["matches"]
    end
  end

  def test_the_census_rides_in_band
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      assert_equal 2, evaluation["features"]
      assert_equal 1, evaluation["with_geometry"]
      assert_equal 1, evaluation["with_when"]
      assert_equal({ "nc" => 1 }, evaluation["excluded_rows"])
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::PlacesLpfBuilder.new(registry: registry_rig)
                                         .build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
