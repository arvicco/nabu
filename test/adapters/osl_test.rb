# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::Osl (P53-1) — the Oracc Sign List registered as a FEATURE
  # MODULE (kind: module), not a text source: discover yields NOTHING and
  # parse is unreachable (the hypotactic/cldf-spine shape). Its data is the
  # Nabu::SignList read seam over canonical/osl/00lib/osl.asl (exercised in
  # test/sign_list_test.rb); here we pin the module row, the manifest's
  # verbatim CC0 license, and the module contract.
  class OslTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("osl")

    def registry
      Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    end

    # --- the module row / manifest --------------------------------------------

    def test_registry_carries_the_module_row_disabled_and_manual
      entry = registry["osl"]
      refute_nil entry, "osl must be registered in config/sources.yml"
      assert entry.feature_module?, "a sign-list instrument is a kind: module row"
      assert entry.wired, "channel verified (the 2026-08-18 wired-semantics ruling)"
      assert_equal "manual", entry.sync_policy, "the sync is owner-fired"
      assert_equal %w[cuneiform], entry.axes
    end

    def test_manifest_records_the_cc0_grant_verbatim
      manifest = Nabu::Adapters::Osl.manifest
      assert_equal "osl", manifest.id
      assert_equal "open", manifest.license_class, "CC0 → open"
      assert_includes manifest.license,
                      "CC0: osl.asl and its associated files are placed in the public domain " \
                      "under a CC0 licence.",
                      "the osl.asl header line is quoted verbatim"
      assert_equal "https://github.com/oracc/osl", manifest.upstream_url
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::Osl.new
      assert_empty adapter.discover(FIXTURES).to_a, "a sign-list instrument mints no documents"
      ref = Nabu::DocumentRef.new(source_id: "osl", id: "urn:nabu:osl:x",
                                  path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/sign-list instrument/, error.message)
    end

    def test_module_declares_no_enrichment_producer
      refute Nabu::Adapters::Osl.enrichment_producer?,
             "its data is the Nabu::SignList read seam, not enrichments rows"
    end

    def test_registry_builds_the_adapter
      adapter = registry["osl"].build_adapter
      assert_instance_of Nabu::Adapters::Osl, adapter
    end
  end
end
