# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Kitab + Nabu::KitabTextReuse (P43-4) — the KITAB Text Reuse
  # instrument registered as a FEATURE MODULE (kind: module), not a text source:
  # discover yields NOTHING and parse is unreachable (the trismegistos shape).
  # Its work is the links-journal producer #9 (exercised in
  # test/kitab_text_reuse_test.rb); here we pin the module row, the manifest's
  # two-fact license, and the module contract.
  class KitabTest < Minitest::Test
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("kitab")

    def setup
      @catalog = store_test_db
      @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    end

    def teardown
      @journal.disconnect
    end

    # --- the module row / manifest --------------------------------------------

    def test_registry_carries_the_module_row_disabled_manual_and_seeded
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["kitab"]
      refute_nil entry, "kitab must be registered in config/sources.yml"
      assert entry.feature_module?, "a links instrument is a kind: module row"
      refute entry.enabled, "a feature module serves no documents — enabled stays false permanently"
      assert_equal "manual", entry.sync_policy, "the sweep is owner-fired"
      assert_equal %w[arabic], entry.axes
      assert_equal %w[ALCorpus00001-ara2], entry.classes,
                   "the pilot folder allowlist is seeded with the P43-4 exemplar (the classes: seam)"
    end

    def test_manifest_records_both_license_facts_verbatim
      manifest = Nabu::Adapters::Kitab.manifest
      assert_equal "kitab", manifest.id
      assert_equal "nc", manifest.license_class, "the Zenodo record's CC BY-NC-SA class"
      assert_includes manifest.license, "CC BY-NC-SA 4.0"
      assert_includes manifest.license, "10.5281/zenodo.11501559"
      assert_includes manifest.license, "NO in-repo license file",
                      "the mirror's license silence is recorded, not mistaken for permission"
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = Nabu::Adapters::Kitab.new
      assert_empty adapter.discover(FIXTURES).to_a, "a links instrument mints no documents"
      assert Nabu::Adapters::Kitab.reference_edges?, "its data rides the links journal"
      ref = Nabu::DocumentRef.new(source_id: "kitab", id: "urn:nabu:kitab:x", path: FIXTURES, metadata: {})
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/links instrument/, error.message)
    end

    def test_adapter_reference_producer_is_the_text_reuse_producer
      producer = Nabu::Adapters::Kitab.reference_producer(catalog: @catalog, journal: @journal)
      assert_instance_of Nabu::KitabTextReuse, producer
    end

    # The registry builds the adapter with the entry's classes: (pilot folders)
    # — the construction seam sync/rebuild use.
    def test_registry_builds_the_adapter_with_the_pilot_allowlist
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      adapter = registry["kitab"].build_adapter
      assert_instance_of Nabu::Adapters::Kitab, adapter
    end
  end
end
