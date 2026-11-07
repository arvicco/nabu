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

  # -- the language-slice identity ---------------------------------------------

  # Two members: "pl" holds Latin (two live passages, one withdrawn, one
  # Greek), "pleiades" holds no Latin at all.
  def slice_catalog
    catalog = store_test_db
    pl = catalog[:sources].insert(slug: "pl", name: "P", adapter_class: "X", license_class: "open",
                                  last_ingest_identity: "i-pl")
    catalog[:sources].insert(slug: "pleiades", name: "G", adapter_class: "X", license_class: "open",
                             last_ingest_identity: "i-pleiades")
    doc = catalog[:documents].insert(source_id: pl, urn: "urn:pl:d", language: "lat", content_sha256: "x",
                                     revision: 1, withdrawn: false)
    [["urn:pl:d:1", "lat", 1, false], ["urn:pl:d:2", "lat", 2, false], ["urn:pl:d:3", "lat", 5, true],
     ["urn:pl:d:4", "grc", 7, false]].each_with_index do |(urn, lang, revision, withdrawn), i|
      catalog[:passages].insert(document_id: doc, urn: urn, sequence: i, language: lang, text: "t",
                                text_normalized: "t", content_sha256: "x", revision: revision, withdrawn: withdrawn)
    end
    catalog
  end

  def latin_scope = { "producer" => "parallels", "scope" => "pl", "params" => { "lang" => "lat" } }

  def test_provenance_records_the_language_slice_the_run_consumed
    catalog = slice_catalog
    config = Struct.new(:canonical_dir).new(File.join(@dir, "canonical"))
    prov = Nabu::MinedLayers.provenance(latin_scope, catalog: catalog, config: config, registry: nil)
    assert_equal({ "pl" => "i-pl", "pleiades" => "i-pleiades" }, prov.catalog, "global membership, as before")
    assert_equal({ "lang" => "lat", "members" => { "pl" => [2, 2] } }, prov.slice,
                 "the lat lane (the engine's code variants, live rows only) per member holding any; " \
                 "an empty lane is absent")
  end

  def test_the_slice_lane_follows_the_profile_and_spans_every_language_without_one
    assert_equal "lat", Nabu::MinedLayers.slice_lang("producer" => "parallels", "params" => { "profile" => "latin" })
    assert_nil Nabu::MinedLayers.slice_lang("producer" => "parallels", "params" => {})
    assert_equal({ "pl" => [3, 7] }, Nabu::Store::SourceContentIdentity.slices(slice_catalog, lang: nil, slugs: %w[pl]))
  end

  def sliced_layer(catalog, inputs: { "producer_code" => Nabu::LinkStamps.code_digests["parallels"] })
    config = Struct.new(:canonical_dir).new(File.join(@dir, "canonical"))
    prov = Nabu::MinedLayers.provenance(latin_scope, catalog: catalog, config: config, registry: nil)
    layer(catalog: prov.catalog, inputs: inputs).with(slice: prov.slice)
  end

  def test_a_touch_outside_the_slice_no_longer_stales_the_layer
    catalog = slice_catalog
    sliced = sliced_layer(catalog)
    catalog[:sources].where(slug: "pleiades").update(last_ingest_identity: "i-pleiades-2")
    catalog[:sources].where(slug: "pl").update(last_ingest_identity: "i-pl-2")
    pl_doc = catalog[:documents].where(urn: "urn:pl:d").get(:id)
    catalog[:passages].where(urn: "urn:pl:d:4").update(revision: 8) # the Greek passage: outside the lane
    staleness = Nabu::MinedLayers.staleness(sliced, catalog: catalog)
    assert_equal [[], :slice, %w[pl pleiades]], [staleness.changed, staleness.grain, staleness.touched]
    refute staleness.stale?

    catalog[:passages].insert(document_id: pl_doc, urn: "urn:pl:d:5", sequence: 9, language: "lat", text: "t",
                              text_normalized: "t", content_sha256: "x", revision: 1, withdrawn: false)
    grown = Nabu::MinedLayers.staleness(sliced, catalog: catalog)
    assert_equal %w[pl], grown.changed, "a member whose lane grew is stale"
    assert grown.stale?
  end

  def test_a_re_parsed_lane_member_still_stales_the_layer
    catalog = slice_catalog
    sliced = sliced_layer(catalog)
    catalog[:sources].where(slug: "pl").update(last_ingest_identity: "i-pl-2")
    catalog[:passages].where(urn: "urn:pl:d:1").update(revision: 3)
    assert_equal %w[pl], Nabu::MinedLayers.staleness(sliced, catalog: catalog).changed
  end

  # The slice is probed only for members whose ingest identity moved: an
  # unmoved source was not re-ingested, so its slice cannot have moved.
  def test_the_slice_is_probed_only_for_members_whose_ingest_identity_moved
    catalog = slice_catalog
    sliced = sliced_layer(catalog)
    catalog[:passages].where(urn: "urn:pl:d:1").update(revision: 3) # no re-ingest recorded
    staleness = Nabu::MinedLayers.staleness(sliced, catalog: catalog)
    assert_equal [[], []], [staleness.changed, staleness.touched]
  end

  def test_a_layer_mined_before_the_slice_keeps_the_coarse_verdict
    catalog = slice_catalog
    coarse = layer(catalog: { "pl" => "i-pl", "pleiades" => "i-pleiades" })
    catalog[:sources].where(slug: "pleiades").update(last_ingest_identity: "i-pleiades-2")
    staleness = Nabu::MinedLayers.staleness(coarse, catalog: catalog)
    assert_equal [%w[pleiades], :source], [staleness.changed, staleness.grain]
    assert staleness.stale?, "never upgraded: an old layer's claim stays coarse"
  end

  # -- `links mine --stale`'s selection ---------------------------------------

  def test_stale_selection_grades_every_recorded_scope
    catalog = slice_catalog
    current = sliced_layer(catalog).with(scope: "pl")
    moved_code = sliced_layer(catalog, inputs: { "producer_code" => "old" }).with(scope: "moved")
    scopes = [latin_scope, latin_scope.merge("scope" => "moved"), latin_scope.merge("scope" => "never")]
    picks = Nabu::MinedLayers.stale_selection(scopes, layers: [current, moved_code], catalog: catalog)
    assert_equal([["pl", :current], ["moved", :stale], ["never", :unmined]],
                 picks.map { |pick| [pick.scope["scope"], pick.status] })
    assert picks[1].staleness.code_moved
    assert_nil picks[2].layer
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
