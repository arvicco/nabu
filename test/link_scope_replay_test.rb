# frozen_string_literal: true

require "test_helper"

# Nabu::LinkScopeReplay (P106-6 — Q94): the links-stage dispatch of
# recorded scopes, now covering the place pair. The 2026-09-27 rebuild
# silently dropped a 3.25M-edge place-mine run because the place CLIs
# never recorded scopes and the replay knew only the three original
# producers — this pins the dispatch and the mine-before-link order.
class LinkScopeReplayTest < Minitest::Test
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
                places: [Place.new(id: "hvd_1", title: "杜陵", lat: 34.2, lon: 109.1,
                                   place_types: ["xian"], time_periods: ["1820"],
                                   name_keys: ["杜陵"])],
                names_for: :name_keys.to_proc
    )
    source = Nabu::Store::Source.create(slug: "kanripo", name: "K", adapter_class: "X",
                                        license_class: "attribution")
    doc = Nabu::Store::Document.create(source_id: source.id, urn: "urn:nabu:kanripo:d1",
                                       language: "lzh", title: "t", canonical_path: "x",
                                       content_sha256: "0" * 64)
    Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:nabu:kanripo:d1:1",
                                language: "lzh", text: "田何徙杜陵號杜田生",
                                text_normalized: "田何徙杜陵號杜田生",
                                content_sha256: "1" * 64, sequence: 0, revision: 1)
  end

  def teardown
    @journal.disconnect
  end

  def test_order_puts_place_link_after_place_mine_whatever_the_recorded_order
    scopes = [{ "producer" => "place-link", "scope" => "kanripo" },
              { "producer" => "parallels", "scope" => "x" },
              { "producer" => "place-mine", "scope" => "kanripo" }]
    ordered = Nabu::LinkScopeReplay.order(scopes).map { |s| s["producer"] }
    assert_equal %w[parallels place-mine place-link], ordered
  end

  def test_a_recorded_place_mine_scope_re_mints_candidate_edges
    Nabu::LinkScopeReplay.replay!(
      { "producer" => "place-mine", "scope" => "kanripo", "params" => { "gazetteer" => "chgis" } },
      db: @catalog, fulltext: nil, journal: @journal, config: nil
    )
    edges = @journal[:links].where(kind: "place-candidate").all
    assert_equal ["urn:nabu:place:chgis:hvd_1"], edges.map { |e| e[:to_urn] }.uniq
  end

  def test_a_recorded_place_link_scope_promotes_after_the_mine
    %w[place-mine place-link].each do |producer|
      Nabu::LinkScopeReplay.replay!(
        { "producer" => producer, "scope" => "kanripo", "params" => { "gazetteer" => "chgis" } },
        db: @catalog, fulltext: nil, journal: @journal, config: nil,
        places: RegistryStub.new({ "杜陵" => Nabu::Places::Decision.new(
          refs: ["chgis:hvd_1"], status: "matched", certainty: "high", note: "the Han county"
        ) })
      )
    end
    assert_equal 1, @journal[:links].where(kind: "place").count,
                 "the matched name's candidate edge promotes to a ruled attestation edge"
  end

  def test_place_link_without_a_registry_is_a_loud_failure_never_silent
    error = assert_raises(Nabu::Error) do
      Nabu::LinkScopeReplay.replay!(
        { "producer" => "place-link", "scope" => "kanripo" },
        db: @catalog, fulltext: nil, journal: @journal,
        config: Struct.new(:canonical_dir).new(Dir.mktmpdir), places: :auto
      )
    end
    assert_match(/nabu-places registry/, error.message)
  end

  def test_unknown_producer_still_raises
    error = assert_raises(Nabu::Error) do
      Nabu::LinkScopeReplay.replay!({ "producer" => "nope", "scope" => "x" },
                                    db: @catalog, fulltext: nil, journal: @journal, config: nil)
    end
    assert_match(/unknown batch producer/, error.message)
  end
end
