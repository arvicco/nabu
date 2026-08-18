# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::NabuLects (P57-3) — the nabu-lects lect registry
  # registered as a FEATURE MODULE (kind: module), not a text source:
  # discover yields NOTHING and parse is unreachable (the cldf-spine/
  # nabu-data shape). Its data is the pure read seam Nabu::Lects (exercised
  # in test/lects_test.rb); this file pins the module-row / manifest / fetch
  # contract (the nabu-data precedent).
  class NabuLectsTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["nabu-lects"]
      refute_nil entry, "nabu-lects must be registered in config/sources.yml"
      assert entry.feature_module?, "a lect resolver instrument is a kind: module row"
      assert entry.wired, "channel verified (the 2026-08-18 wired-semantics ruling)"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "etym"
    end

    def test_manifest_is_cc_by_attribution
      manifest = Nabu::Adapters::NabuLects.manifest
      assert_equal "nabu-lects", manifest.id
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC BY 4.0"
      assert_equal "https://github.com/arvicco/nabu-lects", manifest.upstream_url
      assert_equal "nabu-lects", manifest.parser_family
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::NabuLects.new
      assert_empty adapter.discover(FIXTURES).to_a, "a lect resolver instrument mints no documents"
      ref = Nabu::DocumentRef.new(source_id: "nabu-lects", id: "urn:nabu:nabu-lects:x",
                                  path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/parse is unreachable/, error.message)
    end

    def test_fetch_targets_the_published_repo_whole
      assert_equal "https://github.com/arvicco/nabu-lects.git", Nabu::Adapters::NabuLects::REPO_URL
    end
  end
end
