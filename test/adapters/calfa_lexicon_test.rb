# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# CalfaLexicon adapter tests: calfa-co/lexical-databases — the source files
# of the Calfa Classical Armenian dictionary, the library's first Armenian
# dictionary shelf (CC BY-NC 4.0 → class nc). Dictionary-shaped, so it
# cannot include the passage-shaped AdapterConformance suite; like
# DillmannTest/LexicaTest it mirrors those checks for the dictionary shape
# (manifest validity, discover→parse round-trip, id uniqueness/stability,
# NFC, license class) and adds the DictionaryLoader contract, the
# discovery census (the synonyms grain skipped by rule) and the
# source-specific pins.
#
# Three dictionaries under one source (the lexica precedent — slug per
# dictionary): calfa-en (Armenian–English), calfa-fr (Armenian–French) —
# each a definitions file plus a proper-name file (np: ids) — and
# calfa-acharian (Ačaṙean's etymological dictionary, 1926).
class CalfaLexiconTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("calfa-lexicon")

  def adapter = Nabu::Adapters::CalfaLexicon.new

  # --- manifest + content kind ----------------------------------------------

  def test_manifest_records_the_nc_grant_verbatim
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "calfa-lexicon", manifest.id
    assert_equal "nc", manifest.license_class
    assert_includes Nabu::SourceManifest::LICENSE_CLASSES, manifest.license_class
    assert_includes manifest.license, "These data can be freely used under a CC BY-NC 4.0 license"
    assert_match(/Łazarean/, manifest.license, "the in-copyright synonyms caveat rides the license line")
    assert_equal "https://github.com/calfa-co/lexical-databases", manifest.upstream_url
    assert_equal "calfa-tsv", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::CalfaLexicon.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------

  def test_discover_yields_one_ref_per_accepted_file_sorted
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["calfa-acharian:etymology/etymology01.xml",
                  "calfa-en:definitions/en-definitions01.tsv",
                  "calfa-en:definitions_proper/en-definitions01.tsv",
                  "calfa-fr:definitions/fr-definitions01.tsv",
                  "calfa-fr:definitions_proper/fr-definitions01.tsv"], refs.map(&:id)
    assert(refs.all? { |ref| ref.source_id == "calfa-lexicon" })
    refs.each { |ref| assert_equal ref.id.split(":").first, ref.metadata.fetch("dictionary") }
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_xcl_dictionary_documents_per_slug
    documents = parsed
    assert_equal %w[calfa-acharian calfa-en calfa-en calfa-fr calfa-fr], documents.map(&:slug)
    assert(documents.all? { |document| document.language == "xcl" })
    assert_equal [11, 14, 5, 13, 5], documents.map(&:size)
    titles = documents.to_h { |document| [document.slug, document.title] }
    assert_match(/Ačaṙean/, titles.fetch("calfa-acharian"))
    assert_match(/English/, titles.fetch("calfa-en"))
    assert_match(/French/, titles.fetch("calfa-fr"))
  end

  def test_entry_ids_are_unique_per_dictionary_and_stable_across_independent_passes
    snapshot = lambda do
      adapter.discover(FIXTURES).flat_map do |ref|
        adapter.parse(ref).map { |entry| [ref.metadata.fetch("dictionary"), entry.entry_id] }
      end
    end
    first = snapshot.call
    assert_equal first.uniq.sort, first.sort, "duplicate (dictionary, entry_id) pairs"
    assert_equal first, snapshot.call
  end

  def test_content_is_stable_across_independent_parses
    hashes = lambda do
      adapter.discover(FIXTURES).flat_map do |ref|
        adapter.parse(ref).map { |entry| Nabu::Store::ContentHash.dictionary_entry(entry) }
      end
    end
    assert_equal hashes.call, hashes.call
  end

  def test_entry_output_is_nfc
    parsed.each do |document|
      document.each do |entry|
        assert entry.headword.unicode_normalized?(:nfc), entry.entry_id
        assert entry.body.unicode_normalized?(:nfc), entry.entry_id
        assert entry.headword_folded.unicode_normalized?(:nfc), entry.entry_id
      end
    end
  end

  def test_the_proper_name_lane_shares_the_slug_under_np_ids
    en_ids = parsed.select { |document| document.slug == "calfa-en" }.flat_map { |document| document.map(&:entry_id) }
    assert_includes en_ids, "Աբաս", "the common noun 'father; abbot'"
    assert_includes en_ids, "np:Աբաս", "the proper name Abas — same headword, its own id"
  end

  # --- the discovery census: the rejected synonyms grain ---------------------

  def test_the_synonyms_file_is_skipped_by_rule_with_its_note
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert skips.clean?
    assert_match(%r{synonyms/synonyms01\.tsv}, skips.notes.join("\n"))
    assert_match(/Łazarean/, skips.notes.join("\n"), "the note names why")
    refute(adapter.discover(FIXTURES).any? { |ref| ref.path.include?("synonyms") })
  end

  def test_an_unknown_data_file_is_unrecognized_never_silent
    Dir.mktmpdir do |work|
      FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], work)
      FileUtils.cp(File.join(FIXTURES, "definitions", "en-definitions01.tsv"),
                   File.join(work, "definitions", "de-definitions01.tsv"))
      skips = adapter.discovery_skips(work)
      assert_equal 1, skips.unrecognized
      assert_match(/de-definitions01\.tsv/, skips.notes.join("\n"))
      refute(adapter.discover(work).any? { |ref| ref.path.end_with?("de-definitions01.tsv") })
    end
  end

  # --- DictionaryLoader contract ---------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 0, first.errored
    assert_equal 48, db[:dictionary_entries].count
    assert_equal %w[calfa-acharian calfa-en calfa-fr], db[:dictionaries].order(:slug).select_map(:slug)

    second = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.errored
    assert_equal 48, db[:dictionary_entries].count, "a byte-identical reload upserts, never duplicates"
    urns = db[:dictionary_entries].select_map(:urn)
    assert_includes urns, "urn:nabu:dict:calfa-en:Ահաբեկ"
    assert_includes urns, "urn:nabu:dict:calfa-acharian:+ԱՅՐ"
  ensure
    db&.disconnect
  end

  def test_cf_anchor_resolves_to_its_unique_headword_and_stays_honest_when_ambiguous
    db = store_test_db
    Nabu::Store::DictionaryLoader.new(db: db, source: create_source(db)).load_from(adapter, workdir: FIXTURES)
    define = Nabu::Query::Define.new(catalog: db)
    assert_equal ["urn:nabu:dict:calfa-en:Ահաբեկ"],
                 define.by_urn("urn:nabu:dict:calfa-en:Ահաբեկեմ").crossrefs.map(&:resolved_urn)
    assert_equal [nil], define.by_urn("urn:nabu:dict:calfa-fr:Ակնածեմ").crossrefs.map(&:resolved_urn),
                 "Ակն is a homograph pair in calfa-fr — unique-match-only leaves it unresolved"
  ensure
    db&.disconnect
  end

  def test_define_finds_all_three_dictionaries_from_one_lowercase_lemma
    db = store_test_db
    Nabu::Store::DictionaryLoader.new(db: db, source: create_source(db)).load_from(adapter, workdir: FIXTURES)
    hits = Nabu::Query::Define.new(catalog: db, lila: nil, form_lemma: nil, verb_lemma: nil, lects: nil)
                              .run("աբաս", limit: nil).map(&:urn)
    assert_includes hits, "urn:nabu:dict:calfa-en:Աբաս"
    assert_includes hits, "urn:nabu:dict:calfa-en:np:Աբաս"
    assert_includes hits, "urn:nabu:dict:calfa-fr:np:Աբաս"
    acharian = Nabu::Query::Define.new(catalog: db, lila: nil, form_lemma: nil, verb_lemma: nil, lects: nil)
                                  .run("այր", limit: nil).map(&:urn)
    assert_includes acharian, "urn:nabu:dict:calfa-acharian:+ԱՅՐ", "the capitals and the + mark fold away"
  ensure
    db&.disconnect
  end

  # --- registry ----------------------------------------------------------------

  def test_registry_row_exists_unwired_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["calfa-lexicon"]
    refute_nil entry, "config/sources.yml must register calfa-lexicon"
    assert_equal Nabu::Adapters::CalfaLexicon, entry.adapter_class
    refute entry.wired, "wired: false until the first real sync is verified"
    assert_equal "manual", entry.sync_policy
  end

  # --- fetch (local git only, no network) ------------------------------------

  def test_fetch_clones_the_repo_and_the_tree_is_discoverable
    Dir.mktmpdir("nabu-calfa-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      calfa = adapter
      calfa.define_singleton_method(:repo_url) { upstream }
      report = calfa.fetch(work)

      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert_equal 5, calfa.discover(work).count
      assert_equal 1, calfa.discovery_skips(work).skipped_by_rule
    end
  end

  private

  def parsed
    adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "calfa-lexicon", name: "Calfa Classical Armenian dictionary",
      adapter_class: "Nabu::Adapters::CalfaLexicon", license_class: "nc"
    )
  end

  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(upstream)
    %w[definitions definitions_proper etymology synonyms].each do |dir|
      FileUtils.cp_r(File.join(FIXTURES, dir), upstream)
    end
    Nabu::Shell.run("git", "init", "-q", upstream)
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
