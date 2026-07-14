# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The LIV adapter (P18-6): Rix's Lexikon der indogermanischen Verben as LiLa
# Linked Open Data — the FIRST non-Wiktionary reconstruction shelf. Dictionary-
# shaped, so it mirrors the conformance checks the passage suite cannot cover
# (manifest validity, discover→parse round-trip, id uniqueness/stability, NFC,
# license class) and adds: the stem-type body layer (the survey's NEW
# annotation axis — entry payload rendered by define, no schema change), the
# Latin reflex minting through the §9 u/v fold (the survey's uireo pin), the
# DictionaryLoader contract, the language-notes rider, and the define/etym
# acceptance renders.
class LivTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("liv")
  RAW_URL = "https://raw.githubusercontent.com/CIRCSE/LIV/master/ttl/LIV.ttl"

  DHUEH = "56350916536173684873874157618509590909"  # *dʰu̯eh₂-{1} (suffio)
  UEIS  = "255358900949995430917747026003964285"    # 1.*u̯ei̯s-{1} (uireo)
  LEID  = "3056929752157742125"                     # *lei̯d- (ludo)

  def adapter = Nabu::Adapters::Liv.new

  # --- manifest + content kind ---------------------------------------------------

  def test_manifest_identifies_the_liv_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "liv", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/The publisher of the dictionary allowed us/, manifest.license,
                 "the README permission grant travels verbatim")
    assert_equal RAW_URL, manifest.upstream_url
    assert_equal "lila-ttl", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Liv.content_kind
  end

  # --- discover → parse round-trip -------------------------------------------------

  def test_discover_yields_one_ref_and_nothing_before_a_first_fetch
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["liv:LIV.ttl"], refs.map(&:id)
    assert_equal "liv", refs.first.source_id
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_the_ine_pro_etymon_shelf
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "liv", document.slug
    assert_equal "ine-pro", document.language
    assert_equal [DHUEH, UEIS, LEID], document.map(&:entry_id),
                 "one entry per LIV etymon, file order"
  end

  def test_etymon_headwords_clean_the_liv_markers_but_key_raw_stays_verbatim
    entries = adapter.parse(adapter.discover(FIXTURES).first).entries.to_h { |e| [e.entry_id, e] }
    assert_equal "*dʰu̯eh₂-{1}", entries[DHUEH].key_raw
    assert_equal "dʰu̯eh₂-", entries[DHUEH].headword, "homonym marker {1} and asterisk stripped"
    assert_equal "dhueh₂-", entries[DHUEH].headword_folded, "§9 ine proto fold (ʰ→h, u̯→u)"
    assert_equal "1.*u̯ei̯s-{1}", entries[UEIS].key_raw
    assert_equal "u̯ei̯s-", entries[UEIS].headword, "leading homonym index 1. stripped too"
    assert_nil entries[DHUEH].gloss, "the LOD carries relations only, no meanings — nil is honest"
  end

  # --- the stem-type layer (the packet's NEW annotation axis) ---------------------

  def test_body_carries_stem_type_lines_with_their_latin_continuations
    entries = adapter.parse(adapter.discover(FIXTURES).first).entries.to_h { |e| [e.entry_id, e] }
    assert_equal "present stem *dʰu̯éh₂-/dʰuh₂- → pres suffio", entries[DHUEH].body
    assert_equal "essive stem *u̯is-h₁i̯é- → pres uireo", entries[UEIS].body
    # *lei̯d- pins the shared placeholder theme (label "–", an upstream em-dash
    # node reused across etymons): only THIS etymon's links may attach to it.
    assert_equal ["aorist stem – → perf lusi",
                  "present stem ?*lé-loi̯d/lid- → pres ludo"],
                 entries[LEID].body.split("\n")
  end

  # --- Latin reflexes through the u/v fold (survey pin) ----------------------------

  def test_latin_entries_mint_reflexes_joining_gold_lat_through_the_uv_fold
    entries = adapter.parse(adapter.discover(FIXTURES).first).entries.to_h { |e| [e.entry_id, e] }
    uireo = entries[UEIS].reflexes
    assert_equal 1, uireo.size
    reflex = uireo.first
    assert_equal "lat", reflex.lang_code
    assert_equal "lat", reflex.language
    assert_equal "uireo", reflex.word, "LIV writtenReps are u-spelling"
    assert_equal "uireo", reflex.word_folded
    assert_equal Nabu::Normalize.search_form("vireo", language: "lat"), reflex.word_folded,
                 "a v-spelled gold lemma folds onto the same key — the §9 u/v merge"
    refute reflex.borrowed
    assert_equal %w[suffio], entries[DHUEH].reflexes.map(&:word)
    assert_equal %w[ludo], entries[LEID].reflexes.map(&:word)
  end

  def test_entry_ids_are_unique_stable_and_output_is_nfc
    snapshot = -> { adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
    adapter.parse(adapter.discover(FIXTURES).first).each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
    end
  end

  # --- fetch (WebMock only) --------------------------------------------------------

  def test_fetch_downloads_the_ttl_and_discovers_in_place
    stub_request(:get, RAW_URL).to_return(status: 200, body: File.read(File.join(FIXTURES, "LIV.ttl")))
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      refs = adapter.discover(workdir).to_a
      assert_equal ["liv:LIV.ttl"], refs.map(&:id)
      assert_equal 3, adapter.parse(refs.first).size
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, RAW_URL).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end

  def test_probe_heads_the_raw_file
    assert_equal :http_zip, Nabu::Adapters::Liv.remote_probe_strategy
    targets = Nabu::Adapters::Liv.http_probe_targets
    assert_equal [RAW_URL], targets.map(&:zip_url)
    assert_nil targets.first.metadata_url,
               "the grant lives in the repo README, not a probe-shaped endpoint"
    assert_equal Nabu::FileFetch::STATE_FILE, targets.first.state_file
  end

  # --- DictionaryLoader contract ---------------------------------------------------

  def loader_setup(ledger: nil, canonical_dir: nil)
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "liv", name: "LIV", adapter_class: "Nabu::Adapters::Liv",
      license: "CC BY-SA 4.0", license_class: "attribution",
      upstream_url: RAW_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source, ledger: ledger, canonical_dir: canonical_dir)]
  end

  def test_loading_twice_is_idempotent_with_stable_urns_and_reflex_rows
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 3, second.skipped
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
    assert_equal "urn:nabu:dict:liv:#{DHUEH}",
                 db[:dictionary_entries].where(entry_id: DHUEH).get(:urn)
    assert_equal 3, db[:dictionary_reflexes].count
    assert_equal ["lat"], db[:dictionary_reflexes].select_map(:language).uniq
  end

  # --- language-notes rider (P18-6, redirected to dossier sections by P19-1) --------

  def test_load_accretes_the_ine_pro_witness_section_idempotently
    Dir.mktmpdir do |root|
      db, loader = loader_setup(canonical_dir: root)
      loader.load_from(adapter, workdir: FIXTURES)
      shelf = Nabu::LanguageShelf.new(dir: Nabu::LanguageShelf.dir(root))
      section = shelf.load("ine-pro").section("witness:liv")
      assert_equal "liv", section.source, "per-record provenance, the P18-5 contract"
      assert_match(/305 .*verbal roots/, section.body)
      assert_equal section.body,
                   db[:language_records].where(lang_code: "ine-pro", kind: "witness:liv").get(:body),
                   "the derived record refreshes at accretion time"
      before = File.read(shelf.path_for("ine-pro"))
      loader.load_from(adapter, workdir: FIXTURES)
      assert_equal before, File.read(shelf.path_for("ine-pro")),
                   "re-loading writes nothing — the latest-body check, rehomed"
    end
  end

  # --- acceptance renders (define / etym on the fixture shelf) ---------------------

  def test_define_on_a_liv_etymon_shows_stem_types_and_latin_reflexes
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Define.new(catalog: db).run("*dʰu̯eh₂-")
    assert_equal 1, results.size
    result = results.first
    assert_equal "*dʰu̯eh₂-", result.headword, "the -pro display asterisk"
    assert_includes result.body, "present stem *dʰu̯éh₂-/dʰuh₂- → pres suffio"
    assert_equal %w[suffio], result.reflexes.map(&:word)
  end

  def test_etym_walks_a_v_spelled_latin_lemma_to_the_liv_etymon
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Etym.new(catalog: db).run("vireo")
    assert_equal ["*u̯ei̯s-"], results.map(&:headword)
    assert_equal "liv", results.first.dictionary_slug
    assert_equal "uireo", results.first.matched_reflex.word, "matched through the u/v fold"
  end

  # --- registry ---------------------------------------------------------------------

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["liv"]
    refute_nil entry, "config/sources.yml must register liv"
    assert_equal Nabu::Adapters::Liv, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first sync (CLAUDE.md checklist §6)"
    assert_equal "manual", entry.sync_policy
  end
end
