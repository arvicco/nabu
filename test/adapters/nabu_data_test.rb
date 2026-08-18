# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::NabuData (P51-W6) — Nabu's own published datasets
  # registered back as a FEATURE MODULE (kind: module), not a text source:
  # discover yields NOTHING and parse is unreachable (the lila/cldf-spine
  # shape). Its data is the pure read seam Nabu::FormLemma (exercised in
  # test/form_lemma_test.rb); this file pins the module-row / manifest
  # contract (the lila precedent).
  class NabuDataTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("nabu-data")

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["nabu-data"]
      refute_nil entry, "nabu-data must be registered in config/sources.yml"
      assert entry.feature_module?, "a dataset-bundle instrument is a kind: module row"
      assert entry.wired, "channel verified (the 2026-08-18 wired-semantics ruling)"
      assert_equal "manual", entry.sync_policy
      assert_equal %w[indic tibetan], entry.axes.sort,
                   "the bundle rides its datasets' desks (san + xct)"
    end

    def test_manifest_is_cc_by_attribution_with_the_upstream_chain_named
      manifest = Nabu::Adapters::NabuData.manifest
      assert_equal "nabu-data", manifest.id
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC BY 4.0"
      assert_includes manifest.license, "Digital Corpus of Sanskrit",
                      "the per-dataset upstream attribution chain rides the license line"
      assert_equal "https://github.com/arvicco/nabu-data", manifest.upstream_url
      assert_equal "nabu-data", manifest.parser_family
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::NabuData.new
      assert_empty adapter.discover(FIXTURES).to_a, "a dataset-bundle instrument mints no documents"
      ref = Nabu::DocumentRef.new(source_id: "nabu-data", id: "urn:nabu:nabu-data:x",
                                  path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/parse is unreachable/, error.message)
    end

    def test_fetch_targets_the_published_repo_whole
      assert_equal "https://github.com/arvicco/nabu-data.git", Nabu::Adapters::NabuData::REPO_URL
    end
  end
end
