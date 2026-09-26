# frozen_string_literal: true

require "test_helper"

# Nabu::PlaceLink (P105-4 — Q86's apply lane): registry-MATCHED mined
# names promote their place-candidate edges to ruled attestation edges —
# kind "place", producer "place-link", the ruled identity ONLY (a
# homonym candidate the decision does not cite gets nothing). The
# materialization stays at the grain the evidence exists: passage-level
# attestations in the links journal, never document_axes.place_ref (a
# text MENTIONING a place is not FROM it).
class PlaceLinkTest < Minitest::Test
  include StoreTestDB

  Place = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods, :name_keys)

  RegistryStub = Struct.new(:rows) do
    def decisions_for(_source) = rows
  end

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    Nabu::Store::PlaceIndex.derive!(
      @catalog, gazetteer: "chgis",
                places: [
                  Place.new(id: "hvd_1", title: "杜陵", lat: 34.18, lon: 108.92,
                            place_types: ["xian"], time_periods: ["23–264"], name_keys: ["杜陵"]),
                  # The homonym the decision does NOT cite.
                  Place.new(id: "hvd_2", title: "杜陵", lat: 30.0, lon: 104.0,
                            place_types: ["cun zhen"], time_periods: ["1911"], name_keys: ["杜陵"]),
                  Place.new(id: "hvd_3", title: "王城", lat: 25.5, lon: 116.7,
                            place_types: ["cun zhen"], time_periods: ["1911"], name_keys: ["王城"])
                ],
                names_for: :name_keys.to_proc
    )
    seed_passages
    # Empty stop/allow lists pin the fixture against the shipped hand
    # stop list (the round-6 清水 lesson in the report test).
    Nabu::PlaceMine.new(catalog: @catalog, journal: @journal, gazetteer: "chgis",
                        stop_names: [], allow_names: [])
                   .apply!(source: "kanripo")
  end

  def teardown
    @journal.disconnect
  end

  def seed_passages
    source = Nabu::Store::Source.create(slug: "kanripo", name: "Kanripo",
                                        adapter_class: "X", license_class: "attribution")
    doc = Nabu::Store::Document.create(source_id: source.id, urn: "urn:nabu:kanripo:d1",
                                       language: "lzh", title: "t1", canonical_path: "x",
                                       content_sha256: "0" * 64)
    [["urn:nabu:kanripo:d1:1", "田何徙杜陵號杜田生"],
     ["urn:nabu:kanripo:d1:2", "王入于王城"]].each_with_index do |(urn, text), i|
      Nabu::Store::Passage.create(document_id: doc.id, urn: urn, language: "lzh",
                                  text: text, text_normalized: text,
                                  content_sha256: i.to_s * 64, sequence: i, revision: 1)
    end
  end

  def registry
    matched = Nabu::Places::Decision.new(refs: ["chgis:hvd_1"], status: "matched",
                                         certainty: "high", note: "the Han county")
    rejected = Nabu::Places::Decision.new(refs: [], status: "rejected",
                                          certainty: "high", note: "wrong identity")
    RegistryStub.new({ "杜陵" => matched, "王城" => rejected })
  end

  def apply!
    Nabu::PlaceLink.new(catalog: @catalog, journal: @journal,
                        registry: registry, gazetteer: "chgis")
                   .apply!(source: "kanripo")
  end

  def test_promotes_only_the_ruled_identity_of_matched_names
    result = apply!
    edges = @journal[:links].where(kind: "place").all
    assert_equal ["urn:nabu:place:chgis:hvd_1"], edges.map { |e| e[:to_urn] }.uniq,
                 "the decision cites hvd_1 — the hvd_2 homonym candidate gets NOTHING, " \
                 "and a rejected name (王城) promotes nothing"
    assert_equal(["urn:nabu:kanripo:d1:1"], edges.map { |e| e[:from_urn] })
    assert_equal 1, result.names, "one matched name promoted"
    assert_equal 1, result.edges_written
    assert_operator result.seconds, :>, 0
  end

  def test_candidate_edges_stay_untouched_as_review_provenance
    apply!
    assert_equal 3, @journal[:links].where(kind: "place-candidate").count,
                 "promotion copies — the mine's own edges remain its provenance"
  end

  def test_rerun_supersedes_its_own_run_idempotently
    apply!
    result = apply!
    assert_equal 1, result.superseded_runs
    assert_equal 1, @journal[:links].where(kind: "place").count, "rerun never accretes"
    assert_equal 1, @journal[:link_runs].where(producer: "place-link").count
  end

  def test_edge_detail_carries_the_ruled_evidence
    apply!
    detail = @journal[:links].where(kind: "place").get(:detail)
    assert_includes detail, "「杜陵」"
    assert_includes detail, "chgis:hvd_1"
    assert_includes detail, "registry", "the edge names its authority"
  end
end
