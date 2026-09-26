# frozen_string_literal: true

require "test_helper"

# Nabu::PlaceMineReport (P97-1 — Q70): the aggregate review surface over
# kind=place-candidate edges — candidates grouped by place, ranked by
# DOCUMENT spread (distinct documents beat raw passage counts), titles
# resolved through the gazetteer's derived slice, each row carrying the
# two exits (the stop-list line, the place ref). The review-fuel
# doctrine finally gets a review surface.
class PlaceMineReportTest < Minitest::Test
  include StoreTestDB

  Place = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods, :name_keys, :parent) do
    def initialize(parent: nil, **rest) = super
  end

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    Nabu::Store::PlaceIndex.derive!(
      @catalog, gazetteer: "chgis",
                places: [
                  Place.new(id: "hvd_1", title: "霸州", lat: 39.1, lon: 116.4,
                            place_types: ["zhou"], time_periods: ["1820"], name_keys: ["霸州"],
                            parent: "順天府 (Shuntian Fu)"),
                  Place.new(id: "hvd_2", title: "順天府", lat: 39.9, lon: 116.4,
                            place_types: ["fu"], time_periods: ["1820"], name_keys: ["順天府"]),
                  # The homonym pair — same written name, two identities the
                  # board must keep apart via the discriminators.
                  Place.new(id: "hvd_3", title: "清水", lat: 34.7, lon: 106.1,
                            place_types: ["xian"], time_periods: ["960–1279"], name_keys: ["清水"],
                            parent: "秦州 (Qin Zhou)"),
                  Place.new(id: "hvd_4", title: "清水", lat: 25.9, lon: 116.8,
                            place_types: ["zhen"], time_periods: ["1071–1911"], name_keys: ["清水"],
                            parent: "汀州 (Ting Zhou)")
                ],
                names_for: :name_keys.to_proc
    )
    seed_passages
    # The empty stop/allow lists pin the fixture against the SHIPPED
    # config/place_stop_names.yml — 清水 joined the real hand stop list
    # in review round 6, which silently emptied this homonym fixture.
    Nabu::PlaceMine.new(catalog: @catalog, journal: @journal, gazetteer: "chgis",
                        stop_names: [], allow_names: [])
                   .apply!(source: "kanripo")
  end

  def teardown
    @journal.disconnect
  end

  # d1 carries 霸州 twice + 順天府 once; d2 carries 順天府 once. So
  # 霸州 = 2 passages / 1 document, 順天府 = 2 passages / 2 documents —
  # document spread must rank 順天府 first despite the passage tie.
  def seed_passages
    source = Nabu::Store::Source.create(slug: "kanripo", name: "Kanripo",
                                        adapter_class: "X", license_class: "attribution")
    d1 = Nabu::Store::Document.create(source_id: source.id, urn: "urn:nabu:kanripo:d1",
                                      language: "lzh", title: "t1", canonical_path: "x",
                                      content_sha256: "0" * 64)
    d2 = Nabu::Store::Document.create(source_id: source.id, urn: "urn:nabu:kanripo:d2",
                                      language: "lzh", title: "t2", canonical_path: "y",
                                      content_sha256: "1" * 64)
    [[d1, "urn:nabu:kanripo:d1:1", "臣至霸州見順天府尹"],
     [d1, "urn:nabu:kanripo:d1:2", "霸州之地"],
     [d2, "urn:nabu:kanripo:d2:1", "順天府之南"],
     [d2, "urn:nabu:kanripo:d2:2", "一路行至清水之濱而還"]].each_with_index do |(doc, urn, text), i|
      Nabu::Store::Passage.create(document_id: doc.id, urn: urn, language: "lzh",
                                  text: text, text_normalized: text,
                                  content_sha256: i.to_s * 64, sequence: i, revision: 1)
    end
  end

  def report(**)
    Nabu::PlaceMineReport.new(catalog: @catalog, journal: @journal).run(**)
  end

  def test_rows_group_by_place_and_rank_by_document_spread
    result = report
    assert_equal 4, result.rows.size
    first, second = result.rows
    assert_equal "chgis:hvd_2", first.ref, "2 documents beat 1 despite the passage tie"
    assert_equal "順天府", first.title, "the title resolves through the derived slice"
    assert_equal 2, first.documents
    assert_equal 2, first.passages
    assert_equal [["順天府", 2]], first.names
    assert_equal "chgis:hvd_1", second.ref
    assert_equal 1, second.documents
  end

  def test_rows_carry_samples_and_the_two_exits
    row = report.rows.find { |r| r.ref == "chgis:hvd_1" }
    assert_includes 1..2, row.samples.size
    assert(row.samples.all? { |urn| urn.start_with?("urn:nabu:kanripo:d1:") })
    assert_equal ['  - "霸州"'], row.stop_lines,
                 "the ready-to-paste place_stop_names.yml exit"
  end

  def test_limit_truncates_and_announces_the_total
    result = report(limit: 1)
    assert_equal 1, result.rows.size
    assert_equal 4, result.total_places, "the cap announces what it clipped"
  end

  def test_summary_carries_elapsed_and_scope
    result = report
    assert_operator result.seconds, :>, 0, "elapsed rides every summary (owner rule 2026-09-11)"
    assert_equal 6, result.edges
  end

  def test_source_filter_scopes_by_run
    assert_equal 4, report(source: "kanripo").rows.size
    assert_empty report(source: "cbeta").rows, "an unmined source reports honestly empty"
  end

  # --- the board (P105-1 — Q86): the name-grouped verdict surface ----------

  # A verdict is made per NAME (names.yml keys are verbatim names), so the
  # board's grain is the mined name, its candidates listed under it with
  # the discriminators that separate homonym identities.
  RegistryStub = Struct.new(:rows) do
    def decision(_source, name)
      rows[name]
    end
  end

  def board(registry: nil, stop_names: [], **)
    Nabu::PlaceMineReport.new(catalog: @catalog, journal: @journal)
                         .board(source: "kanripo", gazetteer: "chgis",
                                registry: registry, stop_names: stop_names, **)
  end

  def test_board_groups_by_name_and_ranks_by_document_spread
    result = board
    assert_equal %w[順天府 霸州 清水], result.rows.map(&:name),
                 "document spread first, passages second — per name"
    row = result.rows.last
    assert_equal 1, row.documents
    assert_equal 1, row.passages
    assert_equal %w[chgis:hvd_3 chgis:hvd_4], row.candidates.map(&:ref).sort,
                 "the homonym pair rides ONE row as two candidates"
  end

  def test_board_candidates_carry_the_chgis_discriminators
    row = board.rows.find { |r| r.name == "清水" }
    c3 = row.candidates.find { |c| c.ref == "chgis:hvd_3" }
    assert_equal "清水", c3.title
    assert_equal "秦州 (Qin Zhou)", c3.parent, "the parent unit separates homonyms"
    assert_equal ["960–1279"], c3.time_periods
    assert_equal ["xian"], c3.place_types
    assert_in_delta 34.7, c3.lat, 0.01
    c4 = row.candidates.find { |c| c.ref == "chgis:hvd_4" }
    assert_equal "汀州 (Ting Zhou)", c4.parent
  end

  def test_board_rows_carry_in_context_snippets
    row = board.rows.find { |r| r.name == "清水" }
    urn, snippet = row.snippets.first
    assert_equal "urn:nabu:kanripo:d2:2", urn
    assert_includes snippet, "「清水」", "the matched name is bracketed in place"
    assert_includes snippet, "之濱", "surrounding context rides along"
  end

  def test_board_excludes_decided_and_stopped_names_censused
    decision = Nabu::Places::Decision.new(refs: ["chgis:hvd_2"], status: "matched",
                                          certainty: "high", note: nil)
    registry = RegistryStub.new({ "順天府" => decision })
    result = board(registry: registry, stop_names: ["霸州"])
    assert_equal ["清水"], result.rows.map(&:name),
                 "decided and stopped names leave the board — undecided work only"
    assert_equal [%w[順天府 matched]], result.decided
    assert_equal ["霸州"], result.stopped, "a stop ruled after the mine ran is censused, not silent"
  end

  def test_board_limit_and_totals
    result = board(limit: 1)
    assert_equal 1, result.rows.size
    assert_equal 3, result.total_names
    assert_operator result.seconds, :>, 0
  end
end
