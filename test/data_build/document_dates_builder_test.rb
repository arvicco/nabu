# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The mul/document-dates builder (P73-7): normalized year spans at
# document grain — signed years, precision and the verbatim upstream
# dating string in-band, license slicing (nc AND odbl out) censused.
class DocumentDatesBuilderTest < Minitest::Test
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
    @runic = Nabu::Store::Source.create(slug: "runic", name: "Runic", adapter_class: "TestAdapter",
                                        license_class: "odbl")
    [
      ["urn:nabu:alpha:d1", @alpha, -425, -375, "end of the 5th century BC", "year"],
      ["urn:nabu:alpha:d2", @alpha, 1025, nil, "after 1025", nil],
      ["urn:nabu:alpha:d3", @alpha, nil, nil, nil, nil], # place-only row: no date, no export
      ["urn:nabu:runic:d4", @runic, 1000, 1050, "Viking Age", nil]
    ].each do |urn, source, not_before, not_after, raw, precision|
      doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn,
                                         language: "la", content_sha256: "x", revision: 1)
      @catalog[:document_axes].insert(document_id: doc.id, not_before: not_before,
                                      not_after: not_after, date_raw: raw,
                                      precision: precision, axis_source: source.slug)
    end
  end

  def build!(out_dir)
    Nabu::DataBuild::DocumentDatesBuilder.new(registry: registry_rig)
                                         .build(catalog: @catalog, out_dir: out_dir)
  end

  def test_publishes_dated_rows_with_the_verbatim_raw
    Dir.mktmpdir do |dir|
      result = build!(dir)
      table = CSV.read(File.join(dir, "document-dates.csv"), headers: true)
      assert_equal %w[ID URN Not_Before Not_After Precision Date_Raw Source], table.headers
      assert_equal %w[urn:nabu:alpha:d1 urn:nabu:alpha:d2], table.map { |row| row["URN"] },
                   "dated publishable rows only — the odbl slice and undated rows never appear"
      first = table.first
      assert_equal ["-425", "-375", "year", "end of the 5th century BC", "alpha"],
                   first.values_at("Not_Before", "Not_After", "Precision", "Date_Raw", "Source")
      assert_nil table[1]["Not_After"], "an open-ended bound stays empty, never invented"
      assert_equal 2, result.resources.first.rows
    end
  end

  def test_the_census_rides_in_band
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      assert_equal 3, evaluation["dated_axis_rows"]
      assert_equal 2, evaluation["published_rows"]
      assert_equal({ "odbl" => 1 }, evaluation["excluded_rows"])
    end
  end

  def test_the_recipe_digest_tracks_the_published_slice
    Dir.mktmpdir do |dir|
      first = build!(dir).recipe
      assert_match(/sha256=\h{64}/, first)
      @catalog[:document_axes].where(date_raw: "after 1025").update(not_before: 1026)
      refute_equal first, build!(dir).recipe
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::DocumentDatesBuilder.new(registry: registry_rig)
                                             .build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
