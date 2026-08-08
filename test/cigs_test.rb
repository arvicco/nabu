# frozen_string_literal: true

require "test_helper"

# Nabu::CigsIndex + Adapters::Cigs (P63-5) — the cuneiform site index as a
# feature module deriving the "cigs" place-index slice + crosswalk rows from
# its OWN columns. Trimmed-real fixture (test/fixtures/cigs/README.md).
class CigsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("cigs")
  CSV_PATH = File.join(FIXTURES, "cigs.csv")

  def rows
    @rows ||= Nabu::CigsIndex.each_row(CSV_PATH).to_a
  end

  def row(id)
    rows.find { |r| r.id == id }
  end

  # --- registry / module shape ------------------------------------------------

  def test_registry_carries_the_module_row_manual
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    entry = registry["cigs"]
    refute_nil entry, "cigs must be registered in config/sources.yml"
    assert entry.feature_module?
    assert_equal "manual", entry.sync_policy
  end

  def test_manifest_is_cc_by_attribution_verbatim
    manifest = Nabu::Adapters::Cigs.manifest
    assert_equal "cigs", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "Creative Commons Attribution 4.0"
  end

  def test_discover_yields_no_documents_and_parse_is_unreachable
    adapter = Nabu::Adapters::Cigs.new
    assert_empty adapter.discover(FIXTURES).to_a
    ref = Nabu::DocumentRef.new(source_id: "cigs", id: "urn:nabu:cigs:x", path: FIXTURES, metadata: {})
    assert_raises(Nabu::ParseError) { adapter.parse(ref) }
  end

  # --- the CSV parse ----------------------------------------------------------

  def test_girsu_carries_names_coordinates_and_all_three_crosswalks
    girsu = row("GIR")
    assert_equal "Girsu", girsu.title
    assert_in_delta 31.5624, girsu.lat, 0.1
    %w[girsu].each { |k| assert_includes girsu.name_keys, k }
    assert_includes girsu.name_keys, Nabu::Pleiades.name_key("Girsu (mod. Tello)"),
                    "the CDLI house composite (legacy_name) keys verbatim — the seed join"
    assert_includes girsu.crosswalks, %w[pleiades 912855]
    assert_includes girsu.crosswalks, %w[geonames 93976]
    assert_includes girsu.crosswalks, %w[cdli-provenience 88]
  end

  def test_mari_asserts_the_post_dump_pleiades_id
    assert_includes row("MAR").crosswalks, %w[pleiades 286681704],
                    "CIGS resolves the survey's 'Mari absent from Pleiades?' question"
  end

  def test_a_row_without_gazetteer_links_claims_only_its_cdli_provenience
    assert_equal [%w[cdli-provenience 770]], row("HAY").crosswalks,
                 "empty pleiades/geonames cells assert nothing; the CDLI link stands"
    refute_empty row("HAY").name_keys
  end

  def test_lon_before_lat_is_read_correctly
    nippur = row("NIP")
    assert_operator nippur.lat, :<, nippur.lon, "Mesopotamia: lat ~32 < lon ~45 — a swap would invert"
  end

  # --- the derive -------------------------------------------------------------

  def test_producer_derives_the_cigs_slice_and_the_crosswalk
    db = store_test_db
    census = Nabu::CigsIndex::Producer.new(catalog: db).run("cigs", workdir: FIXTURES)
    assert_equal 8, census.places
    resolver = Nabu::Store::PlaceIndex.resolver(db, gazetteer: "cigs")
    assert_equal "Girsu", resolver.place("GIR").title
    assert_equal ["Umma"], resolver.titled("Umma (mod. Tell Jokha)").map(&:title),
                 "the cdli composite matches via the legacy_name key"
    xwalk = db[:place_crosswalk].where(source: "cigs")
    assert_equal %w[912855], xwalk.where(gazetteer_a: "cigs", id_a: "GIR", gazetteer_b: "pleiades")
                                  .select_map(:id_b)
    refute Nabu::Store::PlaceIndex.populated?(db), "a cigs derive never flips the pleiades default"
  end

  def test_derive_is_idempotent_and_wholesale_per_source
    db = store_test_db
    producer = Nabu::CigsIndex::Producer.new(catalog: db)
    producer.run("cigs", workdir: FIXTURES)
    first = db[:place_crosswalk].order(:id_a, :gazetteer_b, :id_b).all
    producer.run("cigs", workdir: FIXTURES)
    assert_equal first, db[:place_crosswalk].order(:id_a, :gazetteer_b, :id_b).all
  end

  def test_no_csv_is_an_honest_no_op
    Dir.mktmpdir do |dir|
      assert_nil Nabu::CigsIndex::Producer.new(catalog: store_test_db).run("cigs", workdir: dir)
    end
  end
end
