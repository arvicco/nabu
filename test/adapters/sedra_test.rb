# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# Sedra adapter tests: the Sedra V data release 5.0 of Beth Mardutho's
# Syriac lexical database (CC BY-NC 4.0 → class nc). Dictionary-shaped, so
# it cannot include the passage-shaped AdapterConformance suite; like
# CalfaLexiconTest it mirrors those checks for the dictionary shape
# (manifest validity, discover→parse round-trip, id uniqueness/stability,
# NFC, license class) and adds the DictionaryLoader contract, the
# discovery census (the Sedra IV duplicate, the paradigm tables and the
# unreferenced lookups skipped by rule) and the fetch pin.
class SedraTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("sedra")
  ADAPTER = Nabu::Adapters::Sedra

  def adapter = ADAPTER.new

  def parsed = @parsed ||= adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }

  # --- manifest + content kind ----------------------------------------------

  def test_manifest_records_the_nc_grant_verbatim
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "sedra", manifest.id
    assert_equal "nc", manifest.license_class
    assert_includes manifest.license, "The data in this release is licensed under the Creative Commons " \
                                      "Attribution-NonCommercial 4.0 International licence (CC BY-NC 4.0)"
    assert_includes manifest.license, "giving credit to Sedra and Beth Mardutho"
    assert_equal "sedra-jsonl", manifest.parser_family
    assert_match(/Kiraz and James Bennett/, manifest.credit)
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, ADAPTER.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------

  def test_discover_yields_the_one_joined_lexicon_ref
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["sedra:lexemes.jsonl.gz"], refs.map(&:id)
    assert_equal "sedra", refs.first.source_id
    assert_equal "sedra", refs.first.metadata.fetch("dictionary")
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_syc_dictionary_document
    assert_equal 1, parsed.size
    document = parsed.first
    assert_equal "sedra", document.slug
    assert_equal "syc", document.language
    assert_match(/Beth Mardutho, data release 5\.0/, document.title)
    assert_equal %w[1 3 225 607 3469 16413], document.map(&:entry_id)
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

  def test_the_rejected_grains_are_skipped_by_rule_with_their_notes
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 12, skips.skipped_by_rule, "sedra4/ ×5, the two paradigm tables, five unreferenced lookups"
    assert_equal 0, skips.unrecognized
    notes = skips.notes.join("\n")
    assert_match(%r{sedra4/lexemes\.jsonl\.gz: the Sedra IV format of the same rows}, notes)
    assert_match(/conjugation_templates\.jsonl\.gz: the conjugation paradigm templates/, notes)
    assert_match(/stems\.jsonl\.gz: verb-class descriptions/, notes)
    assert_match(/row 28521: no Syriac headword/, notes, "the headwordless row is named, never silent")
  end

  def test_an_unknown_table_is_unrecognized_never_silent
    Dir.mktmpdir do |work|
      FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], work)
      FileUtils.cp(File.join(FIXTURES, "roots.jsonl.gz"), File.join(work, "lemmata.jsonl.gz"))
      skips = adapter.discovery_skips(work)
      assert_equal 1, skips.unrecognized
      assert_match(/lemmata\.jsonl\.gz: not a recognized Sedra release file/, skips.notes.join("\n"))
    end
  end

  # --- DictionaryLoader contract ---------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 0, first.errored
    assert_equal 6, db[:dictionary_entries].count
    second = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.errored
    assert_equal 6, db[:dictionary_entries].count, "a byte-identical reload upserts, never duplicates"
    assert_includes db[:dictionary_entries].select_map(:urn), "urn:nabu:dict:sedra:607"
  ensure
    db&.disconnect
  end

  def test_define_finds_a_lexeme_from_its_vocalized_spelling
    db = store_test_db
    Nabu::Store::DictionaryLoader.new(db: db, source: create_source(db)).load_from(adapter, workdir: FIXTURES)
    hits = Nabu::Query::Define.new(catalog: db, lila: nil, form_lemma: nil, verb_lemma: nil, lects: nil)
                              .run("ܓ݁ܶܢܣܳܐ", limit: nil).map(&:urn)
    assert_includes hits, "urn:nabu:dict:sedra:607", "the vowel points fold away on both sides"
  ensure
    db&.disconnect
  end

  # --- registry ----------------------------------------------------------------

  def test_registry_row_is_unwired_and_manual
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["sedra"]
    refute_nil entry, "config/sources/ must register sedra"
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "wired: false until the first real sync is verified"
    assert_equal "manual", entry.sync_policy
  end

  # --- fetch (WebMock only) ---------------------------------------------------
  # The release zip carries ONE top directory (sedra-2026-10-24/), stripped
  # by ZipFetch so the tables land at canonical/sedra/.

  def zip_body
    @zip_body ||= Dir.mktmpdir do |tmp|
      stage = File.join(tmp, "sedra-2026-10-24")
      FileUtils.mkdir_p(stage)
      FileUtils.cp_r(Dir[File.join(FIXTURES, "*.jsonl.gz")] + [File.join(FIXTURES, "sedra4")], stage)
      Dir.chdir(tmp) { Nabu::Shell.run("zip", "-qr", File.join(tmp, "sedra.zip"), "sedra-2026-10-24") }
      File.binread(File.join(tmp, "sedra.zip"))
    end
  end

  def test_fetch_unpacks_the_release_sha_pinned_and_discover_finds_it
    stub_request(:get, ADAPTER::ZIP_URL)
      .to_return(status: 200, body: zip_body, headers: { "Last-Modified" => "Sat, 24 Oct 2026 23:13:00 GMT" })
    Dir.mktmpdir do |workdir|
      report = ADAPTER.new(pin: Digest::SHA256.hexdigest(zip_body)).fetch(workdir)
      assert_equal Digest::SHA256.hexdigest(zip_body), report.sha
      assert_match(/release 5\.0 zip sha256 pin verified/, report.notes)
      assert File.file?(File.join(workdir, "lexemes.jsonl.gz")), "the top directory is stripped"
      assert_equal ["sedra:lexemes.jsonl.gz"], adapter.discover(workdir).map(&:id)
    end
  end

  def test_a_pin_mismatch_aborts_before_the_tree_mutates
    stub_request(:get, ADAPTER::ZIP_URL).to_return(status: 200, body: zip_body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(workdir) }
      assert_match(/misses the sha256 pin/, error.message)
      refute File.exist?(File.join(workdir, "lexemes.jsonl.gz"))
    end
  end

  private

  def create_source(_db)
    Nabu::Store::Source.create(slug: "sedra", name: "Sedra", adapter_class: "Nabu::Adapters::Sedra",
                               license_class: "nc")
  end
end
