# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Bridging (P34-1) — the ETCBC/bridging OSHB↔BHSA word
  # crosswalk, registered as a FEATURE MODULE row, not a text source: its
  # tf/2021 osm/osm_sf node features share the BHSA tf/2021 slot space and
  # surface exclusively through the bhsa adapter's token lane (see
  # test/adapters/bhsa_test.rb). discover yields NOTHING by design, so the
  # shared conformance suite (which asserts non-empty passages) deliberately
  # does not apply — the row exists to give the owner the sanctioned
  # GitFetch path (`nabu sync bridging`) into canonical/bridging.
  class BridgingTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("bridging")

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["bridging"]
      refute_nil entry, "bridging must be registered in config/sources.yml"
      refute entry.enabled, "a feature module serves no documents — enabled stays false permanently"
      assert_equal "manual", entry.sync_policy
      assert_equal "bridging", entry.adapter_class.manifest.id
    end

    def test_manifest_is_mit_attribution_with_the_license_verbatim
      manifest = Nabu::Adapters::Bridging.manifest
      assert_equal "attribution", manifest.license_class, "MIT notice-preservation → attribution, the corph posture"
      assert_includes manifest.license, "MIT License"
      assert_includes manifest.license, "Dirk Roorda"
      assert_equal "text-fabric", manifest.parser_family
      assert_equal "https://github.com/ETCBC/bridging", manifest.upstream_url
    end

    def test_discover_yields_no_documents_by_design
      adapter = Nabu::Adapters::Bridging.new
      assert_empty adapter.discover(FIXTURES).to_a,
                   "a feature module mints no documents — its data rides bhsa tokens"
      Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
    end

    def test_parse_is_unreachable_and_says_so
      ref = Nabu::DocumentRef.new(source_id: "bridging", id: "urn:nabu:bridging:x", path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { Nabu::Adapters::Bridging.new.parse(ref) }
      assert_match(/feature module/, error.message)
    end

    def test_fetch_cone_pins_the_2021_dataset_and_the_license
      assert_equal ["tf/2021", "yaml", "README.md", "LICENSE"], Nabu::Adapters::Bridging::SPARSE_PATHS,
                   "the sparse cone IS the version pin — tf/2017 (the 88%-era build) never materializes"
    end

    def test_fixture_headers_pin_the_bhsa_2021_slot_space
      header = File.readlines(File.join(FIXTURES, "tf", "2021", "osm.tf")).take_while { |l| l.start_with?("@") }
      assert_includes header, "@coreData=BHSA\n", "the module declares its core dataset"
      assert_includes header, "@version=2021\n", "the same frozen version dir the bhsa adapter pins"
      assert_includes header, "@source_url=https://github.com/openscriptures/morphhb\n",
                      "the OSHB side of the crosswalk, machine-readable in the feature header"
    end

    def test_fixture_slices_parse_with_the_family_and_stay_verbatim
      osm = Nabu::Adapters::TextFabric::Feature.load(File.join(FIXTURES, "tf", "2021", "osm.tf"))
      count = 0
      osm.each_pair { count += 1 }
      assert_equal 2881, count, "every content slot of the bhsa fixture slice carries a tag"
      assert_equal "HC", osm.fetch(298_558), "Jona 1:1 opens with the conjunction, OSM-tagged HC"
      osm_sf = Nabu::Adapters::TextFabric::Feature.load(File.join(FIXTURES, "tf", "2021", "osm_sf.tf"))
      sf_count = 0
      osm_sf.each_pair { sf_count += 1 }
      assert_equal 369, sf_count, "the slice's two-morpheme words (suffix lane)"
      assert_equal "HSp3fs", osm_sf.fetch(298_578)
    end
  end
end
