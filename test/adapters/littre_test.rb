# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Littré, Dictionnaire de la langue française — the oeuvres/littre TEI as
# one dictionary shelf (one document per letter file). Trimmed-real
# fixtures: 5 letter files carrying 8 articles + the three rejected
# grains' specimens (test/fixtures/littre/README.md). Dictionary-shape
# conformance, the DefinitionsShelfChecks stance.
class LittreTest < Minitest::Test
  include StoreTestDB

  ADAPTER = Nabu::Adapters::Littre

  def fixtures = Nabu::TestSupport.fixtures("littre")

  def documents
    @documents ||= begin
      adapter = ADAPTER.new
      adapter.discover(fixtures).map { |ref| adapter.parse(ref) }
    end
  end

  def test_manifest_carries_the_verbatim_license
    manifest = ADAPTER.manifest
    assert_equal "littre", manifest.id
    assert_match(/Paternité – Partage des Conditions Initiales à l'Identique – 2\.0 France/, manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/oeuvres/littre", manifest.upstream_url
    assert_equal "littre-tei", manifest.parser_family
    assert_equal :dictionary, ADAPTER.content_kind
  end

  def test_discover_yields_the_letter_files_in_order_and_nothing_before_a_fetch
    refs = ADAPTER.new.discover(fixtures).to_a
    assert_equal %w[littre:a.xml littre:b.xml littre:g.xml littre:i.xml littre:s.xml], refs.map(&:id)
    assert(refs.all? { |r| r.source_id == "littre" && r.metadata["dictionary"] == "littre" })
    Dir.mktmpdir { |empty| assert_empty ADAPTER.new.discover(empty).to_a }
  end

  def test_the_front_matter_and_the_test_sample_skip_by_rule_with_notes
    skips = ADAPTER.new.discovery_skips(fixtures)
    assert_equal 3, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_equal %w[xml/causerie.html xml/preface.html xml/test.tei], skips.notes.map { |n| n.split(":").first }.sort
    Dir.mktmpdir { |empty| assert_equal 0, ADAPTER.new.discovery_skips(empty).skipped_by_rule }
  end

  def test_parse_yields_one_fra_shelf_document_per_letter
    assert_equal [1, 2, 2, 1, 2], documents.map(&:size)
    documents.each do |document|
      assert_equal "littre", document.slug
      assert_equal "fra", document.language
    end
  end

  def test_a_known_entry_reads_with_its_definition
    baal = documents.flat_map(&:entries).find { |e| e.entry_id == "baal" }
    assert_equal "Grande divinité des Assyriens, que les Grecs assimilaient à leur Jupiter", baal.gloss
  end

  def test_entry_ids_are_unique_across_the_shelf_and_stable
    snapshot = lambda do
      adapter = ADAPTER.new
      adapter.discover(fixtures).flat_map { |ref| adapter.parse(ref).map(&:entry_id) }
    end
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  def test_entry_output_is_nfc_and_non_empty
    documents.flat_map(&:entries).each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
      refute_empty entry.body
    end
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "littre", name: "littre", adapter_class: ADAPTER.name,
      license: ADAPTER.manifest.license, license_class: "attribution"
    )
    load = -> { Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(ADAPTER.new, workdir: fixtures) }
    load.call
    urns = db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    load.call
    assert_equal urns, db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    assert_equal 8, urns.size
    assert(urns.all? { |urn, _| urn.start_with?("urn:nabu:dict:littre:") })
  end

  def test_registry_row_exists_unwired_with_manual_sync_policy
    entry = Nabu::SourceRegistry.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml"))["littre"]
    refute_nil entry
    assert_equal ADAPTER, entry.adapter_class
    assert_equal "manual", entry.sync_policy
  end
end
