# frozen_string_literal: true

require "test_helper"

# Nabu::PlaceMine (P96-3 — Q9 v0, the Han lane): gazetteer name keys
# mined against passage text into place-candidate edges, with every
# precision rule censused: the single-char floor, the ambiguity cap,
# the derived stop rule, the hand stop list, and the non-Han filter.
class PlaceMineTest < Minitest::Test
  include StoreTestDB

  Place = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods, :name_keys)

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    derive_gazetteer
    seed_passages
  end

  def teardown
    @journal.disconnect
  end

  # A tiny real-shaped gazetteer slice: 霸州 (the chgis fixture's own
  # first row), an ambiguous name resolving to four places, a
  # single-char name, and a Latin-script name.
  def derive_gazetteer
    places = [
      Place.new(id: "hvd_1", title: "霸州", lat: 39.1, lon: 116.4,
                place_types: ["zhou"], time_periods: ["1820"], name_keys: ["霸州", "ba zhou"]),
      Place.new(id: "hvd_2", title: "順天府", lat: 39.9, lon: 116.4,
                place_types: ["fu"], time_periods: ["1820"], name_keys: ["順天府"]),
      Place.new(id: "amb1", title: "新州一", lat: 1, lon: 1, place_types: [], time_periods: [],
                name_keys: ["新州"]),
      Place.new(id: "amb2", title: "新州二", lat: 2, lon: 2, place_types: [], time_periods: [],
                name_keys: ["新州"]),
      Place.new(id: "amb3", title: "新州三", lat: 3, lon: 3, place_types: [], time_periods: [],
                name_keys: ["新州"]),
      Place.new(id: "amb4", title: "新州四", lat: 4, lon: 4, place_types: [], time_periods: [],
                name_keys: ["新州"]),
      Place.new(id: "hvd_9", title: "東", lat: 5, lon: 5, place_types: [], time_periods: [],
                name_keys: ["東"])
    ]
    Nabu::Store::PlaceIndex.derive!(@catalog, gazetteer: "chgis", places: places,
                                              names_for: :name_keys.to_proc)
  end

  def seed_passages
    @source = Nabu::Store::Source.create(slug: "kanripo", name: "Kanripo",
                                         adapter_class: "X", license_class: "attribution")
    doc = Nabu::Store::Document.create(source_id: @source.id, urn: "urn:nabu:kanripo:d1",
                                       language: "lzh", title: "t", canonical_path: "x",
                                       content_sha256: "0" * 64)
    [
      ["urn:nabu:kanripo:d1:1", "臣至霸州見順天府尹"], # both real places
      ["urn:nabu:kanripo:d1:2", "霸州之地新州之民"],         # real + ambiguous
      ["urn:nabu:kanripo:d1:3", "無關之文東行而已"]          # only the single-char name
    ].each_with_index do |(urn, text), i|
      Nabu::Store::Passage.create(document_id: doc.id, urn: urn, language: "lzh",
                                  text: text, text_normalized: text,
                                  content_sha256: i.to_s * 64, sequence: i, revision: 1)
    end
  end

  def miner(stop_names: [])
    Nabu::PlaceMine.new(catalog: @catalog, journal: @journal, gazetteer: "chgis",
                        stop_names: stop_names)
  end

  def test_census_counts_hits_and_applies_the_precision_rules
    report = miner.census(source: "kanripo")
    assert_equal 3, report.passages
    hits = report.name_hits.to_h
    assert_equal 2, hits["霸州"], "substring attestation, once per passage"
    assert_equal 1, hits["順天府"]
    refute hits.key?("新州"), "four homonym targets exceed the ambiguity cap"
    assert_equal 1, report.names_ambiguous
    refute hits.key?("東"), "single-character names never match (the floor)"
    assert_operator report.names_non_han, :>=, 1, "the pinyin key is filtered and censused"
  end

  def test_apply_writes_candidate_edges_with_the_mined_name_riding_detail
    result = miner.apply!(source: "kanripo")
    assert_equal 3, result.edges_written, "霸州 ×2 passages + 順天府 ×1"
    edge = @journal[:links].first(to_urn: "urn:nabu:place:chgis:hvd_2")
    assert_equal "place-candidate", edge[:kind]
    assert_equal "urn:nabu:kanripo:d1:1", edge[:from_urn]
    assert_includes edge[:detail], "順天府"
  end

  def test_hand_stop_names_exclude_and_reruns_supersede
    first = miner(stop_names: ["霸州"]).apply!(source: "kanripo")
    assert_equal 1, first.edges_written, "the hand-stopped name mines nothing"

    second = miner.apply!(source: "kanripo")
    assert_equal 1, second.superseded_runs
    assert_equal 3, @journal[:links].count, "reruns supersede, never accrete"
  end

  def test_candidates_never_touch_place_ref
    miner.apply!(source: "kanripo")
    refute @catalog[:document_axes].where(Sequel.like(:place_ref, "%chgis%")).any?,
           "mining is review fuel for the np: doctrine — place_ref stays untouched"
  end
end
