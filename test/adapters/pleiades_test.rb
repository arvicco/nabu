# frozen_string_literal: true

require "test_helper"
require "fileutils"
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
      refute entry.wired
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

    # --- ref_id: the shared upstream-ref → numeric id helper (P44-2) ----------
    #
    # The parsers capture ONLY ids upstream asserts (no fuzzy matching, ever);
    # this helper is the one normalization seam — a pleiades.stoa.org place
    # URL in either scheme spelling (both occur in real I.Sicily headers), or
    # bare digits (the oracc/EDH CSV spelling), to the numeric id string.

    def test_ref_id_reads_both_scheme_spellings_of_the_place_url
      assert_equal "462487", Nabu::Pleiades.ref_id("https://pleiades.stoa.org/places/462487")
      assert_equal "462372", Nabu::Pleiades.ref_id("http://pleiades.stoa.org/places/462372")
      assert_equal "432808", Nabu::Pleiades.ref_id("https://pleiades.stoa.org/places/432808/"),
                   "a trailing slash is still the same upstream assertion"
    end

    def test_ref_id_accepts_bare_digits
      assert_equal "570685", Nabu::Pleiades.ref_id("570685")
    end

    def test_ref_id_rejects_everything_not_a_pleiades_place_ref
      assert_nil Nabu::Pleiades.ref_id(nil)
      assert_nil Nabu::Pleiades.ref_id("")
      assert_nil Nabu::Pleiades.ref_id("https://sws.geonames.org/3164966"), "GeoNames is not Pleiades"
      assert_nil Nabu::Pleiades.ref_id("https://pleiades.stoa.org/places/"), "no id, no capture"
      assert_nil Nabu::Pleiades.ref_id("https://pleiades.stoa.org/places/462487/json"),
                 "a sub-resource URL is not the place assertion shape"
    end

    # --- titled: exact case-insensitive title match (nabu place, P44-2) -------

    def test_titled_matches_exact_titles_case_insensitively
      resolver = Nabu::Pleiades.load(DUMP)
      assert_equal ["570685"], resolver.titled("sparta").map(&:id)
      assert_equal ["Sicilia (island)"], resolver.titled("SICILIA (ISLAND)").map(&:title)
    end

    def test_titled_is_exact_never_fuzzy
      resolver = Nabu::Pleiades.load(DUMP)
      assert_empty resolver.titled("Sicilia"), "a title prefix is not an exact match — no fuzzy, by design"
      assert_empty resolver.titled("Spart")
    end

    # --- load_default: feature detection (the LiLa precedent) ------------------

    def test_load_default_is_nil_without_a_canonical_dump
      Dir.mktmpdir do |root|
        config = Nabu::Config.load(root: root)
        assert_nil Nabu::Pleiades.load_default(config: config),
                   "no canonical/pleiades dump → nil resolver → consumers degrade byte-identically"
      end
    end

    def test_load_default_finds_the_synced_gzip_dump
      Dir.mktmpdir do |root|
        dir = File.join(root, "canonical", "pleiades")
        FileUtils.mkdir_p(dir)
        File.binwrite(File.join(dir, "pleiades-places.json.gz"), gzip(File.read(DUMP)))
        resolver = Nabu::Pleiades.load_default(config: Nabu::Config.load(root: root))
        refute_nil resolver
        assert_equal "Sparta", resolver.place("570685").title
      end
    end

    def test_load_default_accepts_an_uncompressed_dump_too
      Dir.mktmpdir do |root|
        dir = File.join(root, "canonical", "pleiades")
        FileUtils.mkdir_p(dir)
        FileUtils.cp(DUMP, File.join(dir, "pleiades-places.json"))
        resolver = Nabu::Pleiades.load_default(config: Nabu::Config.load(root: root))
        refute_nil resolver
        assert_equal 2, resolver.size
      end
    end

    def gzip(text)
      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      gz.write(text)
      gz.close
      io.string
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
