# frozen_string_literal: true

require "tmpdir"

# The shared checks for a definitions-json dictionary shelf on the
# DefinitionsJsonShelf base (cleasby-vigfusson, zoega). A dictionary shelf
# serves entries, not passages, so — the KaikkiShelfChecks stance — it
# mirrors AdapterConformance for the dictionary shape: manifest validity
# and license class, one discover ref (nothing before a fetch), the
# rejected grain skipped by rule with its note, discover→parse
# round-trip, entry-id uniqueness and stability across two independent
# passes, NFC output, and the DictionaryLoader contract (idempotent load,
# stable urns).
#
# Include into a Minitest::Test (with StoreTestDB) and define the hooks:
#
#   shelf_adapter_class -> the DefinitionsJsonShelf subclass
#   shelf_slug          -> the shelf slug (= manifest id)
#   shelf_url           -> the upstream repo URL
#   shelf_language      -> the stored language tag
#   shelf_entry_count   -> the trimmed fixture's entry count
module DefinitionsShelfChecks
  def shelf_fixtures = Nabu::TestSupport.fixtures(shelf_slug)

  def shelf_document
    @shelf_document ||= begin
      adapter = shelf_adapter_class.new
      adapter.parse(adapter.discover(shelf_fixtures).first)
    end
  end

  def shelf_entry(id) = shelf_document.entries.find { |entry| entry.entry_id == id }

  def test_manifest_identifies_the_shelf
    manifest = shelf_adapter_class.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal shelf_slug, manifest.id
    assert_match(%r{MIT License / Copyright \(c\) 2020 Sampo Silvennoinen}, manifest.license, "LICENSE, verbatim")
    assert_equal "attribution", manifest.license_class
    assert_equal shelf_url, manifest.upstream_url
    assert_equal "definitions-json", manifest.parser_family
    assert_equal :dictionary, shelf_adapter_class.content_kind
  end

  def test_discover_yields_the_markup_file_only_and_nothing_before_a_fetch
    adapter = shelf_adapter_class.new
    refs = adapter.discover(shelf_fixtures).to_a
    assert_equal([File.basename(shelf_adapter_class::JSON_PATH)], refs.map { |ref| File.basename(ref.path) })
    assert_equal shelf_slug, refs.first.source_id
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  # The no-markup twin is pinned as a real specimen beside the accepted
  # file and skips by rule, counted with its note — never silently.
  def test_the_no_markup_twin_skips_by_rule_with_its_note
    skips = shelf_adapter_class.new.discovery_skips(shelf_fixtures)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_match(/no-markup\.json: skipped by rule — .*lossy twin/, skips.notes.first)
    Dir.mktmpdir { |empty| assert_equal 0, shelf_adapter_class.new.discovery_skips(empty).skipped_by_rule }
  end

  def test_parse_yields_the_dictionary_document
    assert_kind_of Nabu::DictionaryDocument, shelf_document
    assert_equal shelf_slug, shelf_document.slug
    assert_equal shelf_language, shelf_document.language
    assert_equal shelf_entry_count, shelf_document.size
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = lambda do
      adapter = shelf_adapter_class.new
      adapter.parse(adapter.discover(shelf_fixtures).first).map(&:entry_id)
    end
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  def test_entry_output_is_nfc_and_non_empty
    shelf_document.entries.each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
      refute_empty entry.body
    end
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: shelf_slug, name: shelf_slug, adapter_class: shelf_adapter_class.name,
      license: shelf_adapter_class.manifest.license, license_class: "attribution"
    )
    load = lambda do
      Nabu::Store::DictionaryLoader.new(db: db, source: source)
                                   .load_from(shelf_adapter_class.new, workdir: shelf_fixtures)
    end
    load.call
    urns = db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    load.call
    assert_equal urns, db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    assert_equal shelf_entry_count, urns.size
    assert(urns.all? { |urn, _| urn.start_with?("urn:nabu:dict:#{shelf_slug}:") })
  end

  def test_registry_row_exists_unwired_with_manual_sync_policy
    entry = Nabu::SourceRegistry.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml"))[shelf_slug]
    refute_nil entry, "config/sources.yml registers #{shelf_slug}"
    assert_equal shelf_adapter_class, entry.adapter_class
    assert_equal "manual", entry.sync_policy
  end
end
