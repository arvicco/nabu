# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The AED adapter (P28-1): the Egyptian dictionary shelf. Dictionary-shaped,
# so it cannot include the passage-shaped AdapterConformance suite; like
# LexicaTest/BosworthTollerTest it mirrors those checks for the dictionary
# shape (manifest validity, discover→parse round-trip, id
# uniqueness/stability, NFC, license class) and adds the DictionaryLoader
# contract (idempotency, urn shape) plus THE JOIN CONTRACT: entry ids are
# the TLA lemmaIDs the AES corpus (P28-0) mints as gold lemmas, so
# urn:nabu:dict:aed:<lemmaID> resolves an AES lemma id end-to-end.
class AedTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("aed")

  def adapter = Nabu::Adapters::Aed.new

  # --- manifest + content kind --------------------------------------------------

  def test_manifest_identifies_the_aed_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "aed", manifest.id
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/Metadata and texts are released as Creative Commons/, manifest.license,
                 "the in-file <availability> grant is quoted verbatim")
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/simondschweitzer/aed-tei", manifest.upstream_url
    assert_equal "aed-tei", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Aed.content_kind
  end

  def test_fetch_is_sparse_scoped_to_the_dictionary_and_hiero_cone
    # The repo carries ~55,000 AES text files (651 MB working tree) that are
    # NOT this shelf; the sparse cone keeps a sync at dictionary weight.
    assert_equal ["files/dictionary.xml", "files/*_hiero.xml", "README.md"], Nabu::Adapters::Aed::SPARSE_PATHS
  end

  # --- discover → parse round-trip ----------------------------------------------

  def test_discover_yields_one_ref_for_the_dictionary_file
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["aed:dictionary.xml"], refs.map(&:id)
    assert_equal "aed", refs.first.source_id
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_egy_dictionary_document
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "aed", document.slug
    assert_equal "egy", document.language
    assert_equal 32, document.size
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = -> { adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  def test_entry_output_is_nfc
    adapter.parse(adapter.discover(FIXTURES).first).each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
    end
  end

  # --- DictionaryLoader contract (idempotency / urn) ------------------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "aed", name: "AED — Ägyptische Wortliste",
      adapter_class: "Nabu::Adapters::Aed",
      license: Nabu::Adapters::Aed::MANIFEST.license, license_class: "attribution",
      upstream_url: Nabu::Adapters::Aed::MANIFEST.upstream_url, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 32, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 32, second.skipped
    assert_equal 32, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    vulture = db[:dictionary_entries].where(entry_id: "tla1").first
    assert_equal "urn:nabu:dict:aed:tla1", vulture[:urn]
    assert_equal "ꜣ", vulture[:headword]
    assert_equal "a", vulture[:headword_folded]
    assert_equal 1, db[:dictionary_citations].where(dictionary_entry_id: vulture[:id]).count
  end

  # --- THE JOIN CONTRACT (P28-1's point) ------------------------------------------

  def test_an_aes_lemma_id_resolves_end_to_end_through_the_real_loader
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)

    # The AES corpus mints token lemma_id as upstream's lemmaID VERBATIM —
    # BARE digits ("123130" in the aes fixture; live census 2026-10-21:
    # 18,733 distinct ids, none prefixed) — while the AED shelf keeps the
    # dictionary's @xml:id verbatim ("tla550034", all 35,052 entries). The
    # urn an AES token predicts therefore carries the bare id, and show's
    # urn seam folds the "tla" prefix back on (every one of the 18,733
    # live ids lands that way; none lands on exact equality).
    aes_lemma_id = "550034"
    result = Nabu::Query::Define.new(catalog: db).by_urn("urn:nabu:dict:aed:#{aes_lemma_id}")
    refute_nil result, "the urn an AES token predicts must resolve on the shelf"
    assert_equal "urn:nabu:dict:aed:tla550034", result.urn, "resolves to the entry's own minted urn"
    assert_equal "nfr", result.headword
    assert_equal "egy", result.language
    assert_equal "gut; schön; vollkommen", result.gloss
    assert_equal "attribution", result.license_class

    canonical = Nabu::Query::Define.new(catalog: db).by_urn("urn:nabu:dict:aed:tla550034")
    assert_equal result.urn, canonical.urn, "the entry's own urn still resolves directly"
    assert_nil Nabu::Query::Define.new(catalog: db).by_urn("urn:nabu:dict:aed:999999999"),
               "the fold never invents an entry"
  end

  # --- define: folded transliteration lookups -------------------------------------

  def define_on_loaded_shelf
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    Nabu::Query::Define.new(catalog: db)
  end

  def test_define_nfr_finds_the_homograph_cluster
    results = define_on_loaded_shelf.run("nfr", limit: 10)
    refute_empty results
    assert(results.all? { |r| r.headword == "nfr" })
    assert_includes results.map(&:urn), "urn:nabu:dict:aed:tla550034"
    result = results.find { |r| r.urn == "urn:nabu:dict:aed:tla550034" }
    assert_match(/en: good; beautiful; perfect; finished/, result.body,
                 "the English lane rides the body verbatim")
    assert_match(/root: tla866216/, result.body, "the root xref is a body line")
  end

  def test_define_reaches_egyptological_letters_from_ascii
    define = define_on_loaded_shelf
    assert_equal ["urn:nabu:dict:aed:tla10"], define.run("aj.wj").map(&:urn), "ꜣj.wj via ꜣ→a"
    assert_equal ["urn:nabu:dict:aed:tla101340"], define.run("hap-r").map(&:urn),
                 "ḥꜣp-rʾ — generic ḥ strip + ꜣ→a + ʾ drop"
    assert_equal ["urn:nabu:dict:aed:tla866258"], define.run("aa").map(&:urn), "root ꜥꜣ via ꜥ→a"
  end

  # P124-3: the <xr> pointers resolve by TLA id within the shelf — the
  # fixture holds tla550034's root tla866216 (resolves) but not every
  # rootOf derivative (those stay verbatim).
  def test_xr_crossrefs_resolve_by_tla_id_and_render_through_define
    result = define_on_loaded_shelf.run("nfr", limit: 10)
                                   .find { |r| r.urn == "urn:nabu:dict:aed:tla550034" }
    by_kind = result.crossrefs.to_h { |c| [c.kind, c] }
    assert_equal %w[partOf root], result.crossrefs.map(&:kind)
    assert_equal "urn:nabu:dict:aed:tla866216", by_kind["root"].resolved_urn
    assert_equal "root tla866216", by_kind["root"].label
    assert_equal "urn:nabu:dict:aed:tla83470", by_kind["partOf"].resolved_urn
  end

  def test_xr_crossrefs_load_idempotently_and_unheld_targets_stay_verbatim
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    before = db[:dictionary_crossrefs].order(:id).all
    assert_equal 89, before.size
    loader.load_from(adapter, workdir: FIXTURES)
    assert_equal before, db[:dictionary_crossrefs].order(:id).all

    root = db[:dictionary_entries].where(entry_id: "tla866216").get(:id)
    rows = db[:dictionary_crossrefs].where(dictionary_entry_id: root, kind: "rootOf")
    assert_equal 56, rows.count
    assert_equal 5, rows.exclude(to_entry_id: nil).count, "the 5 derivatives held in the slice resolve"
    assert_equal 51, rows.where(to_entry_id: nil).count, "derivatives outside the slice stay verbatim"
  end

  def test_wb_citations_stay_unresolved_print_deep_links
    result = define_on_loaded_shelf.run("nfr", limit: 10)
                                   .find { |r| r.urn == "urn:nabu:dict:aed:tla550034" }
    assert_equal ["Wb 2, 253.1-256.15"], result.citations.map(&:label)
    assert_nil result.citations.first.resolved_urn,
               "a PRINT dictionary page resolves to nothing until a Wb scan is in the library"
  end

  # --- registry -------------------------------------------------------------------

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["aed"]
    refute_nil entry, "config/sources.yml must register aed"
    assert_equal Nabu::Adapters::Aed, entry.adapter_class
    assert entry.wired, "live (owner order 2026-07-18: all pre-P30 sources flipped, riding the P30 PR)"
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::Aed.manifest, entry.manifest
  end
end
