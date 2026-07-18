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

  def test_fetch_is_sparse_scoped_to_the_dictionary_cone
    # The repo carries ~55,000 AES text files (651 MB working tree) that are
    # NOT this shelf; the sparse cone keeps a sync at dictionary weight.
    assert_equal ["files/dictionary.xml", "README.md"], Nabu::Adapters::Aed::SPARSE_PATHS
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
    assert_equal 31, document.size
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
    assert_equal 31, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 31, second.skipped
    assert_equal 31, db[:dictionary_entries].count
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

    # HAND-MADE AES-SHAPED ANNOTATION (honestly labeled): the AES corpus
    # (P28-0, in flight) annotates tokens with TLA lemma references —
    # "tla:550034" in TEI prefix notation, normalized to the lemmaID
    # "tla550034" as the gold lemma id. This is that annotation's shape,
    # not P28-0's code; the contract both sides build to is
    # urn:nabu:dict:aed:<lemmaID>.
    aes_lemma_ref = "tla:550034"
    lemma_id = aes_lemma_ref.delete(":")
    predicted_urn = "urn:nabu:dict:aed:#{lemma_id}"

    result = Nabu::Query::Define.new(catalog: db).by_urn(predicted_urn)
    refute_nil result, "the urn an AES annotation predicts must resolve on the shelf"
    assert_equal "nfr", result.headword
    assert_equal "egy", result.language
    assert_equal "gut; schön; vollkommen", result.gloss
    assert_equal "attribution", result.license_class
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
    refute entry.enabled, "aed stays disabled until the owner-fired first real sync (checklist §6)"
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::Aed.manifest, entry.manifest
  end
end
