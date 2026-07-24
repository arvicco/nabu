# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::Hypotactic (P44-6) — Chamberlain's Greek metrical scansions
  # registered as a FEATURE MODULE (kind: module), not a text source: discover
  # yields NOTHING and parse is unreachable (the trismegistos/kitab shape). Its
  # work is the meter enrichment producer (exercised in
  # test/hypotactic_meter_test.rb); here we pin the module row, the manifest's
  # license + attribution, and the module contract on the P44-7 enrichment seam.
  class HypotacticTest < Minitest::Test
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("hypotactic")

    def setup
      @catalog = store_test_db
    end

    # --- the module row / manifest --------------------------------------------

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["hypotactic"]
      refute_nil entry, "hypotactic must be registered in config/sources.yml"
      assert entry.feature_module?, "a meter instrument is a kind: module row"
      refute entry.enabled, "a feature module serves no documents — enabled stays false permanently"
      assert_equal "manual", entry.sync_policy, "the sync is owner-fired"
      assert_equal %w[classical], entry.axes
    end

    def test_manifest_records_license_and_attribution_verbatim
      manifest = Nabu::Adapters::Hypotactic.manifest
      assert_equal "hypotactic", manifest.id
      assert_equal "attribution", manifest.license_class, "CC BY 4.0 → attribution"
      assert_includes manifest.license, "CC BY 4.0"
      assert_includes manifest.license, "reference me (David Chamberlain)",
                      "Chamberlain's own reference statement is recorded verbatim"
      assert_includes manifest.license, "GREEK lane only", "the Latin lane is JS-blocked, not ours"
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::Hypotactic.new
      assert_empty adapter.discover(FIXTURES).to_a, "a meter instrument mints no documents"
      ref = Nabu::DocumentRef.new(source_id: "hypotactic", id: "urn:nabu:hypotactic:x",
                                  path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/meter instrument/, error.message)
    end

    # The P44-7 enrichment seam, not the links-journal reference seam: SyncRunner
    # and Rebuild find the meter producer through these two declarations.
    def test_adapter_declares_the_meter_enrichment_producer
      assert Nabu::Adapters::Hypotactic.enrichment_producer?, "its data rides the enrichments table"
      refute Nabu::Adapters::Hypotactic.reference_edges?, "a scansion is not a links edge"
      producer = Nabu::Adapters::Hypotactic.enrichment_producer(catalog: @catalog)
      assert_instance_of Nabu::HypotacticMeter, producer
    end

    def test_registry_builds_the_adapter
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      adapter = registry["hypotactic"].build_adapter
      assert_instance_of Nabu::Adapters::Hypotactic, adapter
    end
  end
end
