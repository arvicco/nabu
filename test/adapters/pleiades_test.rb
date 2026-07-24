# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "zlib"
require "stringio"

module Adapters
  # Nabu::Adapters::Pleiades + Nabu::Pleiades (P43-3) — the ancient-world
  # gazetteer registered as a FEATURE MODULE (kind: module): discover yields
  # NOTHING, parse is unreachable, no catalog table, no migration. v1 is a
  # pure read seam resolving a place id → {title, representative point, place
  # types, time periods} off the canonical dump. Exercised against two REAL
  # per-place documents (retrieved 2026-07-24) assembled into a fixture dump
  # (test/fixtures/pleiades/README.md): 462492 Sicilia (island; time periods
  # only on names attestations, empty locations) and 570685 Sparta (populated
  # names AND locations, four place types).
  class PleiadesTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("pleiades")
    DUMP = File.join(FIXTURES, "dump.json")

    # --- the module row / manifest --------------------------------------------

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["pleiades"]
      refute_nil entry, "pleiades must be registered in config/sources.yml"
      assert entry.feature_module?, "a resolver instrument is a kind: module row"
      refute entry.enabled
      assert_equal "manual", entry.sync_policy
    end

    def test_manifest_is_cc_by_attribution_verbatim
      manifest = Nabu::Adapters::Pleiades.manifest
      assert_equal "pleiades", manifest.id
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "Creative Commons Attribution 3.0"
      refute Nabu::Adapters::Pleiades.reference_edges?, "pleiades mints no links — it is a read seam"
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::Pleiades.new
      assert_empty adapter.discover(FIXTURES).to_a
      ref = Nabu::DocumentRef.new(source_id: "pleiades", id: "urn:nabu:pleiades:x", path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/resolver instrument/, error.message)
    end

    # --- the resolver: round-trip on both fixture places ----------------------

    def test_resolves_the_island_place_sicilia
      place = Nabu::Pleiades.load(DUMP).place(462_492)
      refute_nil place
      assert_equal "462492", place.id
      assert_equal "Sicilia (island)", place.title
      assert_in_delta 37.5925, place.lat, 0.001, "lat is reprPoint[1] (GeoJSON [lon, lat])"
      assert_in_delta 14.0465, place.lon, 0.001, "lon is reprPoint[0]"
      assert_equal ["island"], place.place_types
      assert_includes place.time_periods, "archaic"
      assert_includes place.time_periods, "classical"
      assert_equal place.time_periods.uniq, place.time_periods, "distinct time periods only"
    end

    def test_resolves_the_settlement_place_570685_across_names_and_locations
      place = Nabu::Pleiades.load(DUMP).place("570685")
      refute_nil place, "id lookup accepts a string too"
      assert_equal "Sparta", place.title
      assert_in_delta 37.0817, place.lat, 0.001
      assert_in_delta 22.4246, place.lon, 0.001
      assert_equal %w[settlement temple temple-2 archaeological-site], place.place_types
      # Time periods aggregate names[].attestations + locations[].attestations.
      assert_includes place.time_periods, "roman"
      assert_includes place.time_periods, "hellenistic-republican"
    end

    def test_unknown_id_resolves_to_nil
      assert_nil Nabu::Pleiades.load(DUMP).place(999_999)
    end

    def test_dump_carries_both_fixture_places
      assert_equal 2, Nabu::Pleiades.load(DUMP).size
    end

    # --- the container/gzip flexibility (the first-sync seam) ------------------

    def test_accepts_a_graph_wrapped_container
      entries = JSON.parse(File.read(DUMP))
      Dir.mktmpdir do |dir|
        path = File.join(dir, "wrapped.json")
        File.write(path, JSON.generate({ "@graph" => entries }))
        assert_equal "Sparta", Nabu::Pleiades.load(path).place(570_685).title
      end
    end

    def test_accepts_a_gzipped_dump
      Dir.mktmpdir do |dir|
        path = File.join(dir, "dump.json.gz")
        io = StringIO.new
        gz = Zlib::GzipWriter.new(io)
        gz.write(File.read(DUMP))
        gz.close
        File.binwrite(path, io.string)
        assert_equal "Sicilia (island)", Nabu::Pleiades.load(path).place(462_492).title
      end
    end

    def test_accepts_a_single_place_object
      one = JSON.parse(File.read(File.join(FIXTURES, "pleiades-462492.json")))
      Dir.mktmpdir do |dir|
        path = File.join(dir, "one.json")
        File.write(path, JSON.generate(one))
        assert_equal 1, Nabu::Pleiades.load(path).size
      end
    end
  end
end
