# frozen_string_literal: true

require "test_helper"

# Nabu::ChgisIndex + Adapters::Chgis (P96-1) — the China Historical GIS
# Temporal Gazetteer as a feature module deriving the "chgis" place-index
# slice from the TGAZ dump's mv_pn_srch materialization. Trimmed-real
# fixture (test/fixtures/chgis/README.md): the CREATE TABLE block + the
# first INSERT's first ten tuples, byte-verbatim, close reinstated.
class ChgisTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("chgis")
  SQL_PATH = File.join(FIXTURES, "tgaz_bak_2018.sql")

  def rows
    @rows ||= Nabu::ChgisIndex.each_row(SQL_PATH).to_a
  end

  def row(id)
    rows.find { |r| r.id == id }
  end

  # --- registry / module shape ---------------------------------------------

  def test_registry_carries_the_module_row_manual
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    entry = registry["chgis"]
    refute_nil entry, "chgis must be registered in config/sources.yml"
    assert entry.feature_module?
    assert_equal "manual", entry.sync_policy
  end

  def test_manifest_is_cc0_open
    manifest = Nabu::Adapters::Chgis.manifest
    assert_equal "chgis", manifest.id
    assert_equal "open", manifest.license_class
    assert_includes manifest.license, "CC0 1.0"
  end

  def test_discover_yields_no_documents_and_parse_is_unreachable
    adapter = Nabu::Adapters::Chgis.new
    assert_empty adapter.discover(FIXTURES).to_a
    ref = Nabu::DocumentRef.new(source_id: "chgis", id: "urn:nabu:chgis:x", path: FIXTURES, metadata: {})
    assert_raises(Nabu::ParseError) { adapter.parse(ref) }
  end

  # --- the dump parse (a column-list-less mysqldump INSERT) ----------------

  def test_ba_zhou_carries_both_scripts_years_and_coordinates
    ba = row("hvd_1")
    assert_equal "霸州", ba.title, "the hanzi name is the title"
    assert_includes ba.name_keys, Nabu::Pleiades.name_key("霸州"),
                    "the hanzi written form keys — Q9's Sinitic substrate"
    assert_includes ba.name_keys, Nabu::Pleiades.name_key("Ba Zhou"),
                    "the pinyin transcription keys beside it"
    assert_in_delta 39.10154, ba.lat, 0.0001, "y_coord is latitude"
    assert_in_delta 116.39525, ba.lon, 0.0001, "x_coord is longitude"
    assert_equal ["1820"], ba.time_periods, "a same-year span collapses to one year"
    assert_includes ba.place_types, "zhou"
    assert_equal "hvd_9513", ba.parent
  end

  def test_all_ten_fixture_tuples_parse
    assert_equal 10, rows.size
    assert(rows.all? { |r| r.id.start_with?("hvd_") })
    assert(rows.all? { |r| !r.name_keys.empty? })
  end

  # --- the derive ----------------------------------------------------------

  def test_producer_derives_the_chgis_slice_resolvable_in_either_script
    db = store_test_db
    census = Nabu::ChgisIndex::Producer.new(catalog: db).run("chgis", workdir: FIXTURES)
    assert_equal 10, census.places
    resolver = Nabu::Store::PlaceIndex.resolver(db, gazetteer: "chgis")
    assert_equal "霸州", resolver.place("hvd_1").title
    assert_equal ["霸州"], resolver.titled("霸州").map(&:title),
                 "hanzi input resolves"
    assert_equal ["霸州"], resolver.titled("Ba Zhou").map(&:title),
                 "pinyin input resolves the same place"
  end

  def test_producer_without_the_dump_is_an_honest_noop
    db = store_test_db
    assert_nil Nabu::ChgisIndex::Producer.new(catalog: db).run("chgis", workdir: Dir.mktmpdir)
  end
end
