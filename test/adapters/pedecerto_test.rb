# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::Pedecerto (P44-7) — Latin metrical scansions registered as a
  # FEATURE MODULE (kind: module), not a text source: discover yields NOTHING
  # and parse is unreachable (the trismegistos/kitab shape). Its work is the
  # ENRICHMENT producer Nabu::PedecertoScansions (exercised in its own test);
  # this file pins the module contract, the manifest license, and the fetch
  # capability wiring.
  class PedecertoTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("pedecerto")

    # --- the module row / manifest --------------------------------------------

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["pedecerto"]
      refute_nil entry, "pedecerto must be registered in config/sources.yml"
      assert entry.feature_module?, "a meter-enrichment instrument is a kind: module row"
      refute entry.wired, "a feature module serves no documents — enabled stays false permanently"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "classical", "the meter layer rides the classical desk"
    end

    def test_manifest_is_nc_by_nc_nd_verbatim
      manifest = Nabu::Adapters::Pedecerto.manifest
      assert_equal "pedecerto", manifest.id
      assert_equal "nc", manifest.license_class, "CC BY-NC-ND → the nc class"
      assert_includes manifest.license, "BY-NC-ND 4.0"
      assert_includes manifest.license, "non vengano alterati"
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::Pedecerto.new
      assert_empty adapter.discover(FIXTURES).to_a, "a meter instrument mints no documents"
      ref = Nabu::DocumentRef.new(source_id: "pedecerto", id: "urn:nabu:pedecerto:x",
                                  path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/meter-enrichment instrument/, error.message)
    end

    # --- the enrichment producer capability (the seam SyncRunner/Rebuild use) --

    def test_adapter_declares_and_builds_the_enrichment_producer
      assert Nabu::Adapters::Pedecerto.enrichment_producer?, "its data rides the enrichments table"
      refute Nabu::Adapters::Pedecerto.reference_edges?, "meter is an enrichment, NOT a links edge"
      producer = Nabu::Adapters::Pedecerto.enrichment_producer(catalog: :db_placeholder)
      assert_instance_of Nabu::PedecertoScansions, producer
    end

    def test_base_adapter_default_has_no_enrichment_producer
      refute Nabu::Adapter.enrichment_producer?, "the capability is opt-in"
      assert_nil Nabu::Adapter.enrichment_producer(catalog: :db_placeholder)
    end

    # --- fetch is an http_zip source (the ORACC/Diorisis probe shape) ---------

    def test_remote_probe_is_http_zip_over_the_bulk_artifact
      assert_equal :http_zip, Nabu::Adapters::Pedecerto.remote_probe_strategy
      target = Nabu::Adapters::Pedecerto.http_probe_targets.first
      assert_equal "https://www.pedecerto.eu/allpedecertoscans.zip", target.zip_url
      assert_nil target.metadata_url, "the governing license lives in the artifact's own <rights>"
    end
  end
end
