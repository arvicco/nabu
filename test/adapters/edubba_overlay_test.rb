# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::EdubbaOverlay (P72-6) — the sister school's didactic
  # overlay registered as a FEATURE MODULE (the osl/unikemet shape):
  # discover yields NOTHING, parse unreachable; the data is the
  # Nabu::EdubbaOverlay read seam (test/edubba_overlay_test.rb). Here we
  # pin the module row, the CC BY-SA contract line, and the module
  # contract.
  class EdubbaOverlayTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("edubba-overlay")

    def registry
      Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    end

    def test_registry_carries_the_module_row_in_the_signs_group
      entry = registry["edubba-overlay"]
      refute_nil entry, "edubba-overlay must be registered in config/sources.yml"
      assert entry.feature_module?, "a didactic instrument is a kind: module row"
      assert entry.wired, "channel verified (the 2026-08-18 wired-semantics ruling)"
      assert_equal "manual", entry.sync_policy, "course releases, owner-fired"
      assert_equal %w[egyptian cuneiform], entry.axes,
                   "P77-8: the cuneiform lanes shipped — axes follow capability"
      assert_equal %w[unikemet], entry.requires, "P77-r3: the Unikemet join target is a hard dep"
      assert_equal "signs", entry.group, "enable signs && sync signs restores the whole hiero card"
    end

    def test_manifest_records_the_contract_attribution_line
      manifest = Nabu::Adapters::EdubbaOverlay.manifest
      assert_equal "edubba-overlay", manifest.id
      assert_equal "attribution", manifest.license_class, "CC BY-SA → attribution (D51-a)"
      assert_includes manifest.license, "Didactic overlay: Edubba (edubba.ac) · CC BY-SA 4.0",
                      "the contract's attribution line is quoted verbatim"
      assert_equal "https://github.com/arvicco/nabu-edubba", manifest.upstream_url
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::EdubbaOverlay.new
      assert_empty adapter.discover(FIXTURES).to_a, "a didactic instrument mints no documents"
      ref = Nabu::DocumentRef.new(source_id: "edubba-overlay", id: "urn:nabu:edubba-overlay:x",
                                  path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/didactic instrument/, error.message)
    end

    def test_module_declares_no_enrichment_producer
      refute Nabu::Adapters::EdubbaOverlay.enrichment_producer?,
             "its data is the Nabu::EdubbaOverlay read seam, not enrichments rows"
    end

    def test_registry_builds_the_adapter
      adapter = registry["edubba-overlay"].build_adapter
      assert_instance_of Nabu::Adapters::EdubbaOverlay, adapter
    end
  end
end
