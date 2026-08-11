# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The mul/place-refs builder (P73-4): the compiled doc→place projection
# published — one row per (document, namespaced claim), every historical
# ref spelling folded through the ONE ref reader, verbatim names and the
# basis (upstream-asserted vs nabu-places-applied) in-band, license
# slicing censused.
class PlaceRefsBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)
  DecisionRig = Data.define(:refs, :status) do
    def matched? = status == "matched"
  end
  PlacesRig = Data.define(:by_source) do
    def sources = by_source.keys
    def decisions_for(slug) = by_source.fetch(slug, {})
  end

  def registry_rig
    {
      "alpha" => EntryRig.new(manifest: ManifestRig.new(
        name: "Alpha Corpus", upstream_url: "https://alpha.example", license: "CC BY-SA 4.0"
      ))
    }
  end

  def places_rig
    PlacesRig.new(by_source: {
                    "alpha" => {
                      "Bovianum" => DecisionRig.new(refs: ["pleiades:432725"], status: "matched")
                    }
                  })
  end

  def setup
    @catalog = store_test_db
    @alpha = Nabu::Store::Source.create(slug: "alpha", name: "Alpha", adapter_class: "TestAdapter",
                                        license_class: "attribution")
    @closed = Nabu::Store::Source.create(slug: "closed", name: "Closed", adapter_class: "TestAdapter",
                                         license_class: "nc")
    axis_rows.each do |urn, source, name, ref|
      doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn,
                                         language: "la", content_sha256: "x", revision: 1)
      @catalog[:document_axes].insert(document_id: doc.id, place_name: name, place_ref: ref,
                                      axis_source: source.slug)
    end
  end

  def axis_rows
    [
      # A registry-applied row: the ref equals the matched decision.
      ["urn:nabu:alpha:d1", @alpha, "Bovianum", "pleiades:432725"],
      # An upstream multi-claim URL field: two claims, both published.
      ["urn:nabu:alpha:d2", @alpha, "Pompeii",
       "https://pleiades.stoa.org/places/433032 https://www.trismegistos.org/place/2788"],
      # An unparseable stray: censused, never guessed.
      ["urn:nabu:alpha:d3", @alpha, "Somewhere", "https://example.org/text/392592"],
      # The nc slice: excluded, censused.
      ["urn:nabu:closed:d4", @closed, "Jerusalem", "pleiades:687928"]
    ]
  end

  def build!(out_dir)
    Nabu::DataBuild::PlaceRefsBuilder
      .new(registry: registry_rig, places: places_rig)
      .build(catalog: @catalog, out_dir: out_dir)
  end

  def test_publishes_one_row_per_claim_with_basis_in_band
    Dir.mktmpdir do |dir|
      result = build!(dir)
      table = CSV.read(File.join(dir, "place-refs.csv"), headers: true)
      assert_equal %w[ID URN Place_Ref Place_Name Basis Source], table.headers
      rows = table.map { |row| [row["URN"], row["Place_Ref"], row["Basis"]] }
      assert_equal [
        ["urn:nabu:alpha:d1", "pleiades:432725", "nabu-places"],
        ["urn:nabu:alpha:d2", "pleiades:433032", "upstream"],
        ["urn:nabu:alpha:d2", "tm:2788", "upstream"]
      ], rows, "one row per namespaced claim, URL spellings folded, basis decided per axis row"
      assert_equal "Pompeii", table[1]["Place_Name"], "the verbatim upstream name rides every claim"
      assert_equal 3, result.resources.first.rows
    end
  end

  def test_the_census_rides_in_band
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      assert_equal 4, evaluation["axis_rows"]
      assert_equal 3, evaluation["published_rows"]
      assert_equal({ "nc" => 1, "unparseable" => 1 }, evaluation["excluded_rows"])
      assert_equal 3, evaluation["distinct_places"]
      assert_equal({ "pleiades" => 2, "tm" => 1 }, evaluation["claims_by_namespace"])
    end
  end

  def test_cites_the_contributing_corpora_and_the_registry
    Dir.mktmpdir do |dir|
      citations = build!(dir).citations
      keys = citations.map(&:key)
      assert_includes keys, "alpha"
      assert_includes keys, "nabu-places", "the decisions registry is cited"
      refute_includes keys, "closed"
    end
  end

  def test_the_recipe_digest_tracks_the_published_slice
    Dir.mktmpdir do |dir|
      first = build!(dir).recipe
      assert_match(/sha256=\h{64}/, first)
      @catalog[:document_axes].where(place_name: "Bovianum").update(place_ref: "pleiades:1")
      refute_equal first, build!(dir).recipe
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::PlaceRefsBuilder
          .new(registry: registry_rig, places: places_rig)
          .build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
