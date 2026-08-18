# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::Lila (P44-8) — the LiLa Lemma Bank registered as a FEATURE
  # MODULE (kind: module), not a text source: discover yields NOTHING and
  # parse is unreachable (the bridging/pleiades shape). Its data is the pure
  # read seam Nabu::Lila (exercised in test/lila_test.rb); this file pins the
  # module-row / manifest contract (the trismegistos precedent).
  class LilaTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("lila")

    def test_registry_carries_the_module_row_disabled_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["lila"]
      refute_nil entry, "lila must be registered in config/sources.yml"
      assert entry.feature_module?, "a lemma-spine instrument is a kind: module row"
      assert entry.wired, "channel verified (the 2026-08-18 wired-semantics ruling)"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "classical"
    end

    def test_manifest_is_by_sa_attribution_verbatim
      manifest = Nabu::Adapters::Lila.manifest
      assert_equal "lila", manifest.id
      assert_equal "attribution", manifest.license_class, "the house CC BY-SA class"
      assert_includes manifest.license, "CC BY-SA 4.0"
      assert_includes manifest.license, "Attribution-ShareAlike 4.0 International"
      assert_equal "lila-turtle", manifest.parser_family
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::Lila.new
      assert_empty adapter.discover(FIXTURES).to_a, "a lemma-spine instrument mints no documents"
      ref = Nabu::DocumentRef.new(source_id: "lila", id: "urn:nabu:lila:x", path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/lemma-spine instrument/, error.message)
    end

    def test_fetch_uses_the_git_sparse_cone
      assert_equal ["rdf/lemmaBank.ttl", "README.md", "LICENSE"], Nabu::Adapters::Lila::SPARSE_PATHS
    end
  end
end
