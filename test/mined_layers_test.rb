# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::MinedLayers — the cost law's classification (config/
# mined_layers.yml) and the services around the heavy class: provenance,
# the presence line the rebuild summary shows, the staleness reading
# health shows.
class MinedLayersTest < Minitest::Test
  include StoreTestDB

  def setup
    @dir = Dir.mktmpdir("nabu-mined-layers")
    @path = File.join(@dir, "mined-links.sqlite3")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # -- the shipped classification ---------------------------------------------

  def test_the_shipped_classification
    assert_equal({ "parallels" => "heavy", "formulas" => "cheap", "cognates" => "cheap",
                   "place-mine" => "cheap", "place-link" => "cheap", "person-candidates" => "cheap" },
                 Nabu::MinedLayers.classification)
    assert_equal %w[parallels], Nabu::MinedLayers.heavy_producers
  end

  # Every producer the replay dispatches is classified — a producer born
  # later is classified at birth, never silently cheap.
  def test_every_dispatched_producer_is_classified
    source = File.read(File.expand_path("../lib/nabu/link_scope_replay.rb", __dir__))
    dispatched = source.scan(/^\s*when "([a-z-]+)"/).flatten.sort
    assert_equal dispatched, Nabu::MinedLayers.classification.keys.sort
  end

  # The grain is the producer because edges dedupe per pair per KIND across
  # runs and the stamps group scopes by shared kind: producers sharing a
  # kind must share a class (place-mine and place-link move together).
  def test_producers_sharing_an_edge_kind_share_a_class
    classes = Nabu::MinedLayers.classification
    Nabu::LinkStamps::PRODUCERS.to_a.combination(2).each do |(one, spec_one), (two, spec_two)|
      next unless spec_one.kinds.intersect?(spec_two.kinds)

      assert_equal classes.fetch(one), classes.fetch(two), "#{one} and #{two} share a kind"
    end
  end

  def test_an_unknown_class_is_a_loud_error
    path = File.join(@dir, "layers.yml")
    File.write(path, "producers:\n  parallels:\n    class: tepid\n")
    error = assert_raises(Nabu::Error) { Nabu::MinedLayers.classification(path) }
    assert_match(/parallels has class "tepid" — expected cheap or heavy/, error.message)
  end

  def test_run_scope_follows_each_producers_run_rows
    assert_equal "perseus-latin", Nabu::MinedLayers.run_scope("producer" => "parallels", "scope" => "perseus-latin")
    assert_equal "kanripo:chgis", Nabu::MinedLayers.run_scope("producer" => "place-mine", "scope" => "kanripo",
                                                              "params" => { "gazetteer" => "chgis" })
  end

  def test_recorded_lists_only_heavy_scopes
    path = File.join(@dir, "link_scopes.yml")
    Nabu::LinkScopes.record!(path, producer: "formulas", scope: "aspr", params: {})
    Nabu::LinkScopes.record!(path, producer: "parallels", scope: "perseus-latin", params: { "lang" => "lat" })
    assert_equal(%w[perseus-latin], Nabu::MinedLayers.recorded(path).map { |scope| scope["scope"] })
    assert_empty Nabu::MinedLayers.recorded(path, "aspr")
  end

  def test_mine_refuses_a_cheap_producer
    config = Struct.new(:mined_links_path).new(@path)
    error = assert_raises(Nabu::Error) do
      Nabu::MinedLayers.mine!({ "producer" => "formulas", "scope" => "aspr" }, config: config, catalog: nil,
                                                                               registry: nil) { flunk }
    end
    assert_match(/rebuild lane/, error.message)
    refute_path_exists @path
  end

  # -- provenance and staleness -----------------------------------------------

  def test_provenance_carries_the_stamp_preimage_and_the_ingest_identities
    catalog = store_test_db
    catalog[:sources].insert(slug: "aspr", name: "A", adapter_class: "X", license_class: "open",
                             last_ingest_identity: "i-aspr")
    config = Struct.new(:canonical_dir).new(File.join(@dir, "canonical"))
    prov = Nabu::MinedLayers.provenance({ "producer" => "formulas", "scope" => "aspr", "params" => {} },
                                        catalog: catalog, config: config, registry: nil)
    assert_match(/\A\h{64}\z/, prov.stamp)
    assert_equal %w[members params producer_code], prov.inputs.keys.sort
    assert_equal({ "aspr" => "i-aspr" }, prov.catalog)
  end

  def layer(catalog: { "aspr" => "i1" }, inputs: { "producer_code" => Nabu::LinkStamps.code_digests["parallels"] })
    Nabu::Store::MinedLinks::Layer.new(producer: "parallels", scope: "s", run_scope: "s", run_ids: [1], edges: 3,
                                       code_version: "v", stamp: "x", inputs: inputs, catalog: catalog,
                                       origin: "mine", seconds: 1.0, mined_at: Time.now)
  end

  def test_staleness_reads_ingest_identities_and_code
    catalog = store_test_db
    catalog[:sources].insert(slug: "aspr", name: "A", adapter_class: "X", license_class: "open",
                             last_ingest_identity: "i1")
    fresh = Nabu::MinedLayers.staleness(layer, catalog: catalog)
    assert_equal [[], false, false], [fresh.changed, fresh.code_moved, fresh.stale?]

    catalog[:sources].where(slug: "aspr").update(last_ingest_identity: "i2")
    moved = Nabu::MinedLayers.staleness(layer(inputs: { "producer_code" => "old" }), catalog: catalog)
    assert_equal [%w[aspr], true, true], [moved.changed, moved.code_moved, moved.stale?]

    unrecorded = Nabu::MinedLayers.staleness(layer(catalog: nil), catalog: catalog)
    assert_nil unrecorded.changed, "a migrated layer whose stamp no longer matched records no identity"
    refute unrecorded.stale?
  end

  # -- the rebuild summary's presence line -------------------------------------

  def test_presence_line_states
    heavy = [{ "producer" => "parallels", "scope" => "perseus-latin" }]
    assert_equal "mined layers: none present · not yet mined: parallels perseus-latin (nabu links mine SCOPE)",
                 Nabu::MinedLayers.presence_line(@path, heavy_scopes: heavy)

    Nabu::Store::MinedLinks.mine!(@path, producer: "parallels", scope: "perseus-latin", stamp: nil, inputs: nil,
                                         catalog: nil) do |db|
      run = Nabu::Store::LinksJournal.record_run!(db, producer: "parallels", scope: "perseus-latin", params: {},
                                                      code_version: "v")
      Nabu::Store::LinksJournal.finish_run!(db, run)
    end
    assert_equal "mined layers: 1 present, oldest #{Time.now.strftime('%Y-%m-%d')}",
                 Nabu::MinedLayers.presence_line(@path, heavy_scopes: heavy)

    journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    Nabu::Store::LinksJournal.record_run!(journal, producer: "parallels", scope: "x", params: {}, code_version: "v")
    assert_match(%r{· 1 heavy run\(s\) still in db/links\.sqlite3 \(nabu links migrate-mined\)\z},
                 Nabu::MinedLayers.presence_line(@path, heavy_scopes: heavy, journal: journal))
    journal.disconnect
  end
end
