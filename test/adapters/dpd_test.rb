# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# DPD — the Digital Pāḷi Dictionary's release text export as one
# dictionary shelf. Trimmed-real fixture: 4 blocks of dpd.txt
# (test/fixtures/dpd/README.md). Dictionary-shape conformance, the
# DefinitionsShelfChecks stance.
class DpdTest < Minitest::Test
  include StoreTestDB

  ADAPTER = Nabu::Adapters::Dpd

  def fixtures = Nabu::TestSupport.fixtures("dpd")

  def document
    @document ||= begin
      adapter = ADAPTER.new
      adapter.parse(adapter.discover(fixtures).first)
    end
  end

  def test_manifest_carries_the_verbatim_license
    manifest = ADAPTER.manifest
    assert_equal "dpd", manifest.id
    assert_match(%r{Copyright \(c\) Bodhirasa Bhikkhu / SPDX-License-Identifier: CC-BY-NC-SA-4\.0}, manifest.license)
    assert_equal "nc", manifest.license_class
    assert_equal "dpd-txt", manifest.parser_family
    assert_equal :dictionary, ADAPTER.content_kind
  end

  def test_discover_yields_one_ref_and_nothing_before_a_fetch
    refs = ADAPTER.new.discover(fixtures).to_a
    assert_equal ["dpd:dpd.txt"], refs.map(&:id)
    Dir.mktmpdir { |empty| assert_empty ADAPTER.new.discover(empty).to_a }
  end

  def test_parse_yields_the_pli_dictionary_document
    assert_equal "dpd", document.slug
    assert_equal "pli", document.language
    assert_equal 4, document.size
  end

  def test_a_known_entry_reads_with_its_gloss
    assert_equal "smooth", document.entries.find { |e| e.headword == "akakkasa" }.gloss
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
      slug: "dpd", name: "dpd", adapter_class: ADAPTER.name,
      license: ADAPTER.manifest.license, license_class: "nc"
    )
    load = -> { Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(ADAPTER.new, workdir: fixtures) }
    load.call
    urns = db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    load.call
    assert_equal urns, db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    assert_equal 4, urns.size
    assert(urns.all? { |urn, _| urn.start_with?("urn:nabu:dict:dpd:") })
  end

  def test_probe_heads_the_latest_release_zip
    assert_equal [Nabu::Adapters::Dpd::ZIP_URL], ADAPTER.http_probe_targets.map(&:zip_url)
  end

  def test_registry_row_exists_unwired_with_manual_sync_policy
    entry = Nabu::SourceRegistry.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml"))["dpd"]
    refute_nil entry
    assert_equal ADAPTER, entry.adapter_class
    assert_equal "manual", entry.sync_policy
  end
end
