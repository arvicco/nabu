# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Mahan Kosh (1930), the Gurmukhi lane of the Sikhi.io JSON packaging, as
# one dictionary shelf. Trimmed-real fixture: 4 grid rows (one excluded)
# + their 2 Gurmukhi bodies (test/fixtures/mahan-kosh/README.md).
# Dictionary-shape conformance, the DefinitionsShelfChecks stance.
class MahanKoshTest < Minitest::Test
  include StoreTestDB

  ADAPTER = Nabu::Adapters::MahanKosh

  def fixtures = Nabu::TestSupport.fixtures("mahan-kosh")

  def document
    @document ||= begin
      adapter = ADAPTER.new
      adapter.parse(adapter.discover(fixtures).first)
    end
  end

  def test_manifest_carries_the_verbatim_license
    manifest = ADAPTER.manifest
    assert_equal "mahan-kosh", manifest.id
    assert_match(/is in the public domain\. This compiled dataset/, manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal "mahan-kosh-json", manifest.parser_family
    assert_equal :dictionary, ADAPTER.content_kind
  end

  def test_discover_needs_both_files_and_yields_one_ref
    refs = ADAPTER.new.discover(fixtures).to_a
    assert_equal ["mahan-kosh:core.json"], refs.map(&:id)
    assert_equal "mahan-kosh", refs.first.source_id
    Dir.mktmpdir do |dir|
      assert_empty ADAPTER.new.discover(dir).to_a
      FileUtils.mkdir_p(File.join(dir, "core"))
      FileUtils.cp(File.join(fixtures, "core", "core.json"), File.join(dir, "core"))
      assert_empty ADAPTER.new.discover(dir).to_a, "the grid alone is not the shelf"
    end
  end

  def test_parse_yields_the_pan_dictionary_document
    assert_equal "mahan-kosh", document.slug
    assert_equal "pan", document.language
    assert_equal 3, document.size
  end

  def test_entry_ids_are_unique_and_stable_and_output_nfc
    adapter = ADAPTER.new
    again = adapter.parse(adapter.discover(fixtures).first).map(&:entry_id)
    assert_equal document.map(&:entry_id), again
    assert_equal again.uniq, again
    document.each do |entry|
      assert entry.body.unicode_normalized?(:nfc)
      refute_empty entry.body
    end
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "mahan-kosh", name: "mahan-kosh", adapter_class: ADAPTER.name,
      license: ADAPTER.manifest.license, license_class: "attribution"
    )
    load = -> { Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(ADAPTER.new, workdir: fixtures) }
    load.call
    urns = db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    load.call
    assert_equal urns, db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    assert_equal 3, urns.size
    assert(urns.all? { |urn, _| urn.start_with?("urn:nabu:dict:mahan-kosh:") })
  end

  def test_probe_heads_both_files
    base = "https://raw.githubusercontent.com/redroyals/mahan-kosh-multilingual/main/data/entries"
    assert_equal ["#{base}/core.json", "#{base}/gurmukhi.json"], ADAPTER.http_probe_targets.map(&:zip_url)
    assert_equal %w[core gurmukhi], ADAPTER.http_probe_targets.map(&:state_subdir)
  end

  def test_registry_row_exists_unwired_with_manual_sync_policy
    entry = Nabu::SourceRegistry.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml"))["mahan-kosh"]
    refute_nil entry
    assert_equal ADAPTER, entry.adapter_class
    assert_equal "manual", entry.sync_policy
  end
end
