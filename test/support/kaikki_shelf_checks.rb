# frozen_string_literal: true

require "tmpdir"

# The shared checks for a per-language kaikki.org shelf on the
# WiktionaryKaikki base (the wiktionary-akk/hit tests' dictionary-shape
# conformance, factored for the South Asian seven). A dictionary shelf
# serves entries, not passages, so it mirrors AdapterConformance's
# checks for the dictionary shape: manifest validity and the verbatim
# kaikki dual license, one discover ref (nothing before a fetch),
# discover→parse round-trip, entry-id uniqueness and stability across
# two independent passes, NFC output, the reflex promise.
#
# Include into a Minitest::Test and define the hooks:
#
#   kaikki_adapter_class -> the WiktionaryKaikki subclass
#   kaikki_slug          -> the shelf slug (= manifest id)
#   kaikki_filename      -> the kaikki artifact name
#   kaikki_url           -> the per-language JSONL URL
#   kaikki_language      -> the stored language tag
#   kaikki_entry_count   -> the trimmed fixture's entry count
module KaikkiShelfChecks
  def kaikki_fixtures = Nabu::TestSupport.fixtures(kaikki_slug)

  def kaikki_document
    @kaikki_document ||= begin
      adapter = kaikki_adapter_class.new
      adapter.parse(adapter.discover(kaikki_fixtures).first)
    end
  end

  def kaikki_entry(headword)
    kaikki_document.entries.find { |entry| entry.headword == headword }
  end

  def test_manifest_identifies_the_kaikki_shelf
    manifest = kaikki_adapter_class.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal kaikki_slug, manifest.id
    assert_match(/CC-BY-SA and GFDL/, manifest.license, "the kaikki statement, verbatim")
    assert_equal "attribution", manifest.license_class
    assert_equal kaikki_url, manifest.upstream_url
    assert_equal "wiktionary-jsonl", manifest.parser_family
    assert_equal :dictionary, kaikki_adapter_class.content_kind
    assert kaikki_adapter_class.reflex_bearing?, "the descendant and etymon chains mint reflexes"
  end

  def test_discover_yields_one_ref_and_nothing_before_a_fetch
    adapter = kaikki_adapter_class.new
    refs = adapter.discover(kaikki_fixtures).to_a
    assert_equal ["#{kaikki_slug}:#{kaikki_filename}"], refs.map(&:id)
    assert_equal kaikki_slug, refs.first.source_id
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_the_dictionary_document
    assert_kind_of Nabu::DictionaryDocument, kaikki_document
    assert_equal kaikki_slug, kaikki_document.slug
    assert_equal kaikki_language, kaikki_document.language
    assert_equal kaikki_entry_count, kaikki_document.size
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = lambda do
      adapter = kaikki_adapter_class.new
      adapter.parse(adapter.discover(kaikki_fixtures).first).map(&:entry_id)
    end
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  def test_entry_output_is_nfc
    kaikki_document.entries.each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
    end
  end

  def test_probe_heads_the_jsonl
    targets = kaikki_adapter_class.http_probe_targets
    assert_equal [kaikki_url], targets.map(&:zip_url)
    assert_equal :http_zip, kaikki_adapter_class.remote_probe_strategy
  end
end
