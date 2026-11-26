# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "tmpdir"

# Nabu::Adapters::MedHeadwords — the Middle English Dictionary's
# headword / variant-spelling / entry-id list (University of Michigan; the
# editors' October 2023 list on medictionary.info) as a dictionary shelf.
# Dictionary-shaped, so it mirrors the conformance checks for the
# dictionary shape (the Sedra/Wilkens mold): manifest + license class,
# discover→parse round-trip, id uniqueness/stability, NFC, the
# DictionaryLoader contract, the vintage record, the rejected grain and the
# sha-pinned fetch.
class MedHeadwordsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("med-headwords")
  ADAPTER = Nabu::Adapters::MedHeadwords
  URL = "https://medictionary.info/pages/headwords_202310.xml"

  def adapter = ADAPTER.new

  def parsed = @parsed ||= adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }

  # --- manifest + content kind ----------------------------------------------

  def test_manifest_records_the_grant_and_the_courtesy
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "med-headwords", manifest.id
    assert_equal "nc", manifest.license_class
    assert_includes manifest.license, "to be used in whatever way you choose. No conditions whatever"
    assert_includes manifest.license, "Granted by email, 2026-11-06, by Paul F. Schaffner"
    assert_match(/never re-posted for download/, manifest.license)
    assert_match(/Middle English Dictionary/, manifest.credit)
    assert_equal URL, manifest.upstream_url
    assert_equal "med-headwords-xml", manifest.parser_family
  end

  def test_content_kind_is_dictionary_and_nothing_is_materialized
    assert_equal :dictionary, ADAPTER.content_kind
    assert_empty ADAPTER.materialized_paths, "the fetch lands upstream's one file (+ FileFetch state)"
  end

  # --- discover → parse round-trip ------------------------------------------

  def test_discover_yields_the_one_list_with_its_vintage
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["med-headwords:headwords_202310.xml"], refs.map(&:id)
    assert_equal "med-headwords", refs.first.metadata.fetch("dictionary")
    assert_equal "2023-10", refs.first.metadata.fetch("list_vintage")
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_enm_dictionary_document_titled_with_its_vintage
    assert_equal 1, parsed.size
    document = parsed.first
    assert_equal "med-headwords", document.slug
    assert_equal "enm", document.language
    assert_equal "Middle English Dictionary — headwords, variant spellings and entry ids (list of 2023-10)",
                 document.title
    assert_equal 15, document.size
    assert_equal "ā", document.entries.first.headword
  end

  def test_entry_ids_and_content_are_stable_across_independent_parses
    snapshot = lambda do
      ADAPTER.new.discover(FIXTURES).flat_map do |ref|
        ADAPTER.new.parse(ref).map { |entry| [entry.entry_id, Nabu::Store::ContentHash.dictionary_entry(entry)] }
      end
    end
    first = snapshot.call
    assert_equal first.map(&:first).uniq, first.map(&:first), "duplicate entry ids"
    assert_equal first, snapshot.call
  end

  def test_entry_output_is_nfc
    parsed.first.each do |entry|
      assert entry.headword.unicode_normalized?(:nfc), entry.entry_id
      assert entry.body.unicode_normalized?(:nfc), entry.entry_id
    end
  end

  # --- the discovery census ----------------------------------------------------

  def test_the_fixture_tree_has_no_rejected_grain
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 0, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
  end

  def test_another_vintage_of_the_list_is_skipped_by_rule_and_strays_are_named
    Dir.mktmpdir do |work|
      FileUtils.cp(File.join(FIXTURES, "headwords_202310.xml"), work)
      FileUtils.cp(File.join(FIXTURES, "headwords_202310.xml"), File.join(work, "headwords_202210.xml"))
      FileUtils.cp(File.join(FIXTURES, "headwords_202310.xml"), File.join(work, "linnaean.xml"))
      File.write(File.join(work, Nabu::FileFetch::STATE_FILE), "{}")
      skips = adapter.discovery_skips(work)
      assert_equal 1, skips.skipped_by_rule
      assert_equal 1, skips.unrecognized
      notes = skips.notes.join("\n")
      assert_match(/headwords_202210\.xml: another vintage of the MED headword list \(2022-10\)/, notes)
      assert_match(/linnaean\.xml: not the MED headword list/, notes)
      assert_equal ["med-headwords:headwords_202310.xml"], adapter.discover(work).map(&:id),
                   "only the pinned vintage is ever a document"
    end
  end

  # --- DictionaryLoader contract ---------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 0, first.errored
    assert_equal 15, db[:dictionary_entries].count
    second = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.errored
    assert_equal 15, db[:dictionary_entries].count, "a byte-identical reload upserts, never duplicates"
    assert_includes db[:dictionary_entries].select_map(:urn), "urn:nabu:dict:med-headwords:MED2.5"
  ensure
    db&.disconnect
  end

  def test_define_finds_an_entry_from_its_diacritic_spelling
    db = store_test_db
    Nabu::Store::DictionaryLoader.new(db: db, source: create_source(db)).load_from(adapter, workdir: FIXTURES)
    hits = Nabu::Query::Define.new(catalog: db, lila: nil, form_lemma: nil, verb_lemma: nil, lects: nil)
                              .run("zucarīne", limit: nil).map(&:urn)
    assert_includes hits, "urn:nabu:dict:med-headwords:MED54083", "the macron folds away on both sides"
  ensure
    db&.disconnect
  end

  # --- registry ----------------------------------------------------------------

  def test_registry_row_is_wired_and_manual
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["med-headwords"]
    refute_nil entry, "config/sources/ must register med-headwords"
    assert_equal ADAPTER, entry.adapter_class
    assert entry.wired, "wired since the verified first sync (57,094 entries)"
    assert_equal "manual", entry.sync_policy
  end

  # --- fetch (WebMock only) ---------------------------------------------------

  def body = @body ||= File.binread(File.join(FIXTURES, "headwords_202310.xml"))

  def test_fetch_lands_the_list_and_verifies_the_pin
    stub_request(:get, URL)
      .to_return(status: 200, body: body, headers: { "Last-Modified" => "Mon, 23 Feb 2026 18:34:10 GMT" })
    Dir.mktmpdir do |dir|
      report = ADAPTER.new(sha256: Digest::SHA256.hexdigest(body)).fetch(dir)
      assert_equal body, File.binread(File.join(dir, "headwords_202310.xml"))
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      state = File.read(File.join(dir, Nabu::FileFetch::STATE_FILE))
      assert_includes state, "Mon, 23 Feb 2026 18:34:10 GMT", "the served file date is recorded"
    end
  end

  def test_fetch_aborts_on_sha_drift_with_the_tree_untouched
    stub_request(:get, URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(dir) }
      assert_match(/drifted.*re-pin/, error.message)
      refute File.exist?(File.join(dir, "headwords_202310.xml"))
    end
  end

  def test_the_pin_and_the_vintage_are_the_fixture_readmes
    readme = File.read(File.join(FIXTURES, "README.md"))
    assert_includes readme, ADAPTER::LIST_SHA256
    assert_includes readme, ADAPTER::FILENAME
    assert_includes readme, "57,094"
  end

  private

  def create_source(_db)
    Nabu::Store::Source.create(slug: "med-headwords", name: "MED headwords",
                               adapter_class: "Nabu::Adapters::MedHeadwords", license_class: "nc")
  end
end
