# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The mul/kind-classifications builder (P102-2): the kind axis
# published at document grain — the ruled class path per row with the
# VERBATIM upstream genre label beside it, multi-label as multiple
# rows, license slicing (open+attribution only) censused, the honest
# `unknown` class published and the `unmapped` curation bucket
# excluded (a TODO marker is not a classification).
class KindClassificationsBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)

  def registry_rig
    { "alpha" => EntryRig.new(manifest: ManifestRig.new(
      name: "Alpha Corpus", upstream_url: "https://alpha.example", license: "CC BY 4.0"
    )) }
  end

  def setup
    @catalog = store_test_db
    @alpha = Nabu::Store::Source.create(slug: "alpha", name: "Alpha", adapter_class: "TestAdapter",
                                        license_class: "attribution")
    @closed = Nabu::Store::Source.create(slug: "closed", name: "Closed", adapter_class: "TestAdapter",
                                         license_class: "nc")
    rows = [
      ["urn:nabu:alpha:d1", @alpha, [["funerary/epitaph", "sepulcralis"],
                                     ["literary/poetry", "sepulcralis, carmen"]]],
      ["urn:nabu:alpha:d2", @alpha, [["unknown", "ignoratur"]]],
      ["urn:nabu:alpha:d3", @alpha, [["unmapped", "cetera"]]],
      ["urn:nabu:alpha:d4", @alpha, [["historiography/annals", nil]]], # source_kind row: no raw
      ["urn:nabu:closed:d5", @closed, [["administrative", "Administrative"]]]
    ]
    rows.each do |urn, source, kind_rows|
      doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn,
                                         language: "la", content_sha256: "x", revision: 1)
      kind_rows.each do |value, raw|
        @catalog[:document_facets].insert(document_id: doc.id, facet: "kind",
                                          value: value, raw: raw)
      end
    end
    # A non-kind facet row must never leak into the export.
    doc_id = @catalog[:documents].first(urn: "urn:nabu:alpha:d1")[:id]
    @catalog[:document_facets].insert(document_id: doc_id, facet: "genre", value: "sepulcralis")
  end

  def build!(out_dir)
    Nabu::DataBuild::KindClassificationsBuilder.new(registry: registry_rig)
                                               .build(catalog: @catalog, out_dir: out_dir)
  end

  def test_publishes_class_rows_with_the_verbatim_upstream_label
    Dir.mktmpdir do |dir|
      result = build!(dir)
      table = CSV.read(File.join(dir, "kind-classifications.csv"), headers: true)
      assert_equal %w[ID URN Value Kind_Raw Source], table.headers
      assert_equal %w[urn:nabu:alpha:d1 urn:nabu:alpha:d1 urn:nabu:alpha:d2 urn:nabu:alpha:d4],
                   table.map { |row| row["URN"] },
                   "multi-label = multiple rows; unmapped and the nc slice never appear; " \
                   "unknown (a ruled claim) publishes"
      first = table.first
      assert_equal %w[funerary/epitaph sepulcralis alpha],
                   first.values_at("Value", "Kind_Raw", "Source")
      assert_nil table[3]["Kind_Raw"], "a whole-source declaration row carries no upstream label"
      assert_equal 4, result.resources.first.rows
      ids = table.map { |row| row["ID"] }
      assert_equal ids.uniq, ids, "multi-label rows mint distinct deterministic IDs"
    end
  end

  def test_the_census_rides_in_band
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      assert_equal 6, evaluation["kind_rows"]
      assert_equal 4, evaluation["published_rows"]
      assert_equal({ "nc" => 1 }, evaluation["excluded_rows"])
      assert_equal 1, evaluation["unmapped_rows_excluded"]
    end
  end

  def test_the_recipe_digest_tracks_the_published_slice
    Dir.mktmpdir do |dir|
      first = build!(dir).recipe
      assert_match(/sha256=\h{64}/, first)
      @catalog[:document_facets].where(value: "funerary/epitaph").update(value: "funerary")
      refute_equal first, build!(dir).recipe
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::KindClassificationsBuilder.new(registry: registry_rig)
                                                   .build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
