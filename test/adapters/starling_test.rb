# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The StarLing adapter (P22-0): Pokorny's IEW (Starostin/Lubotsky
# digitization) + Nikolayev's Walde-Pokorny-based PIE database from the
# Tower of Babel IE package, under G. Starostin's 2026-07-15 any-use-with-
# acknowledgment grant (per-base compiler credit REQUIRED — it must ride the
# manifest license string onto every serving surface). Dictionary-shaped, so
# like LivTest/MwTest it MIRRORS the passage-shaped conformance suite
# (manifest validity, discover→parse round-trip, id uniqueness/stability,
# NFC, license class) and adds the packet pins: the ἆ font-shift decode
# proven end to end on a real record, the branch-column reflex verdict
# (single-language attested columns mint rows, proto/mixed columns stay in
# the body), the pokorny↔piet crosslink, the DictionaryLoader contract, the
# language-notes rider, and define/etym acceptance renders.
class StarlingTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("starling")
  ZIP_URL = "https://starlingdb.org/download/IE.exe"

  def adapter = Nabu::Adapters::Starling.new

  # --- manifest: the grant and BOTH compiler credits are the license lane ---------

  def test_manifest_carries_the_grant_and_the_per_base_compiler_credits
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "starling", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/free for anybody to use for any purposes as long as the source is properly acknowledged/,
                 manifest.license, "the 2026-07-15 grant travels verbatim")
    assert_match(/George Starostin/, manifest.license, "pokorny credit: the scanner")
    assert_match(/Lubotsky/, manifest.license, "pokorny credit: the corrector")
    assert_match(/Nikolayev/, manifest.license, "piet credit: the compiler")
    assert_match(/S\. Starostin/, manifest.license, "piet credit: the Hittite/Tocharian reflexes")
    assert_equal ZIP_URL, manifest.upstream_url
    assert_equal "starling-dbf", manifest.parser_family
  end

  def test_content_kind_is_dictionary_and_the_source_promises_reflexes
    assert_equal :dictionary, Nabu::Adapters::Starling.content_kind
    assert Nabu::Adapters::Starling.reflex_bearing?
  end

  # --- discover → parse round-trip --------------------------------------------------

  def test_discover_yields_one_ref_per_base_in_registry_order
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["starling-pokorny:pokorny.dbf", "starling-piet:piet.dbf"], refs.map(&:id)
    assert_equal %w[starling starling], refs.map(&:source_id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def parse(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.metadata.fetch("dictionary") == slug }
    adapter.parse(ref)
  end

  def test_parse_pokorny_yields_the_ine_pro_root_shelf
    document = parse("starling-pokorny")
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "starling-pokorny", document.slug
    assert_equal "ine-pro", document.language
    assert_equal %w[1 721 1089], document.map(&:entry_id), "entry id = the stable upstream NUMBER"
  end

  def test_pokorny_headwords_stay_verbatim_and_fold_first_variant_minus_homonym_digits
    entries = parse("starling-pokorny").entries.to_h { |e| [e.entry_id, e] }
    assert_equal "ā", entries["1"].headword
    assert_equal "a", entries["1"].headword_folded
    assert_equal "gʷer(ə)-4", entries["721"].headword, "the IEW homonym digit stays in the display form"
    assert_equal "gwerə-", entries["721"].headword_folded, "§9 ine fold: ʷ→w, parens open, homonym digit off"
    assert_equal "kʷel-1, kʷelə-", entries["1089"].headword, "multi-variant lemma verbatim"
    assert_equal "kwel-", entries["1089"].headword_folded, "the FIRST variant is the lookup key"
    assert_equal "interjection", entries["1"].gloss, "MEANING is the gloss lane"
  end

  # THE decoder-against-reality pin: pokorny #1's MATERIAL carries the
  # survey's \x01\x83\xC2… byte run — the parse must surface the real ἆ.
  def test_pokorny_material_decodes_the_greek_font_shift_run_end_to_end
    body = parse("starling-pokorny").entries.first.body
    assert_includes body, "gr. ἆ Ausruf des Unwillens, Schmerzes, Erstaunens"
    assert_includes body, "German meaning: Ausruf der Empfindung"
    assert_includes body, "General comments: oft neugeschaffen"
    assert_includes body, "References: WP. I 1, WH. I 1, Loewe KZ. 54, 143."
    assert_includes body, "Pages: 1", "IEW page citations ride the body"
  end

  def test_pokorny_piet_crosslink_is_preserved_and_absent_when_zero
    entries = parse("starling-pokorny").entries.to_h { |e| [e.entry_id, e] }
    assert_includes entries["721"].body, "PIE database: #1763"
    assert_includes entries["1089"].body, "PIE database: #562"
    refute_includes entries["1"].body, "PIE database", "PIET=0 means no crosslink"
  end

  # The corpus's one stray byte pair (pokorny #1089, after τέλλω) surfaces
  # as an honest U+FFFD, never dropped.
  def test_the_upstream_stray_byte_pair_is_marked_not_lost
    assert_includes parse("starling-pokorny").entries.to_h { |e| [e.entry_id, e] }["1089"].body,
                    "τέλλω\u{FFFD}"
  end

  def test_parse_piet_yields_the_second_ine_pro_shelf_with_crosslinks
    entries = parse("starling-piet").entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 562 1501], entries.keys
    entry = entries["562"]
    assert_equal "kol-", entry.headword, "leading asterisk stripped (the kaikki convention)"
    assert_equal "*kol-", entry.key_raw
    assert_equal "neck", entry.gloss
    assert_includes entry.body, "Russ. meaning: шея"
    assert_includes entry.body, "Latin: collus, -ī m., collum , -ī n.", "branch columns verbatim in the body"
    assert_includes entry.body, "Pokorny: #1089", "REFERNUM crosslinks back to the pokorny shelf"
    assert_includes entry.body, "Baltic etymology: #1634"
    assert_includes entry.body, "Germanic etymology: #390"
    assert_includes entries["1501"].body, "Vasmer: #12561", "SLAVNUM points into the (future) vasmer base"
    assert_includes entries["1"].body, "Nostratic etymology: #721"
  end

  # --- the reflex verdict (journaled in docs/backlog.md P22-0) ---------------------

  def test_single_language_attested_columns_mint_reflex_rows
    reflexes = parse("starling-piet").entries.to_h { |e| [e.entry_id, e] }["562"].reflexes
    assert_equal [%w[IND san], %w[LAT lat], %w[ALB sq]],
                 reflexes.map { |r| [r.lang_code, r.language] },
                 "lang_code = the upstream column verbatim, language = the catalog tag"
    words = reflexes.to_h { |r| [r.lang_code, r] }
    assert_equal "kaṇṭhá-", words["IND"].word, "the leading citation form only — the rest is prose"
    assert_equal Nabu::Normalize.search_form("kaṇṭha", language: "san"), words["IND"].word_folded,
                 "member fold strips the trailing stem hyphen and lands on the gold-side §9 key"
    assert_equal "collus", words["LAT"].word
    assert_equal "qafɛ", words["ALB"].word
    assert_equal "Old Indian", words["IND"].lang_name, "the .inf field alias feeds the language census"
    assert words.values.none?(&:borrowed), "piet marks no loans — false is the honest parse"
  end

  def test_proto_branch_and_mixed_columns_mint_no_rows_even_when_clean
    entries = parse("starling-piet").entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[IND], entries["1501"].reflexes.map(&:lang_code),
                 "SLAV *sīgātī and GERM *xīg-ia- are Nikolayev-notation branch protoforms — body only"
    assert_includes entries["1501"].body, "Slavic: *sīgātī"
    assert_equal %w[AVEST], entries["1"].reflexes.map(&:lang_code),
                 "the Khowar-prefixed IND cell and the transcribed GREEK column mint nothing"
    assert_equal "ayarə", entries["1"].reflexes.first.word
  end

  def test_entry_ids_are_unique_stable_and_output_is_nfc
    %w[starling-pokorny starling-piet].each do |slug|
      first = parse(slug).map(&:entry_id)
      assert_equal first.uniq, first
      assert_equal first, parse(slug).map(&:entry_id)
      parse(slug).each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
      end
    end
  end

  # --- fetch (WebMock only) ---------------------------------------------------------

  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      %w[pokorny.dbf pokorny.var piet.dbf piet.var].each do |name|
        FileUtils.cp(File.join(FIXTURES, name), dir)
      end
      zip = File.join(dir, "IE.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", zip, *%w[pokorny.dbf pokorny.var piet.dbf piet.var]) }
      File.binread(zip)
    end
  end

  def test_fetch_unpacks_the_package_and_discovers_both_bases
    stub_request(:get, ZIP_URL).to_return(status: 200, body: zip_body)
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      refs = adapter.discover(workdir).to_a
      assert_equal ["starling-pokorny:pokorny.dbf", "starling-piet:piet.dbf"], refs.map(&:id)
      assert_equal 3, adapter.parse(refs.first).size
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end

  def test_probe_heads_the_package_zip
    assert_equal :http_zip, Nabu::Adapters::Starling.remote_probe_strategy
    targets = Nabu::Adapters::Starling.http_probe_targets
    assert_equal [ZIP_URL], targets.map(&:zip_url)
    assert_nil targets.first.metadata_url, "the grant lives in e-mail + descrip.php, not a probe endpoint"
    assert_equal Nabu::ZipFetch::STATE_FILE, targets.first.state_file
  end

  # --- DictionaryLoader contract -----------------------------------------------------

  def loader_setup(canonical_dir: nil)
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "starling", name: "StarLing IE", adapter_class: "Nabu::Adapters::Starling",
      license: Nabu::Adapters::Starling::MANIFEST.license, license_class: "attribution",
      upstream_url: ZIP_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source, canonical_dir: canonical_dir)]
  end

  def test_loading_twice_is_idempotent_with_stable_urns_reflex_rows_and_name_census
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 6, first.added
    assert_equal 0, first.errored
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 6, second.skipped
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
    assert_equal "urn:nabu:dict:starling-pokorny:1089",
                 db[:dictionary_entries].where(entry_id: "1089").get(:urn)
    assert_equal 5, db[:dictionary_reflexes].count, "AVEST + (IND, LAT, ALB) + IND"
    assert_equal ["Albanian", "Avestan", "Latin", "Old Indian"],
                 db[:language_names].select_map(:name).sort,
                 "the .inf aliases feed the language census reflex_bearing health checks"
  end

  # --- language-notes rider ----------------------------------------------------------

  def test_load_accretes_the_ine_pro_witness_section_idempotently
    Dir.mktmpdir do |root|
      _db, loader = loader_setup(canonical_dir: root)
      loader.load_from(adapter, workdir: FIXTURES)
      shelf = Nabu::LanguageShelf.new(dir: Nabu::LanguageShelf.dir(root))
      section = shelf.load("ine-pro").section("witness:starling")
      assert_equal "starling", section.source
      assert_match(/Pokorny/, section.body)
      assert_match(/Nikolayev/, section.body)
      before = File.read(shelf.path_for("ine-pro"))
      loader.load_from(adapter, workdir: FIXTURES)
      assert_equal before, File.read(shelf.path_for("ine-pro"))
    end
  end

  # --- acceptance renders (define / etym on the fixture shelves) ---------------------

  def test_define_a_pokorny_root_shows_the_credited_shelf_with_the_decoded_material
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Define.new(catalog: db).run("*kʷel-")
    assert_equal ["starling-pokorny"], results.map(&:dictionary_slug)
    result = results.first
    assert_equal "*kʷel-1, kʷelə-", result.headword, "the -pro display asterisk"
    assert_match(/properly acknowledged/, result.license,
                 "the grant + credits ride every define result")
    assert_includes result.body, "Material:"
  end

  def test_etym_walks_a_latin_reflex_to_the_piet_root
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Etym.new(catalog: db).run("collus")
    assert_equal ["*kol-"], results.map(&:headword)
    assert_equal "starling-piet", results.first.dictionary_slug
    assert_equal "collus", results.first.matched_reflex.word
  end

  # --- registry -----------------------------------------------------------------------

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["starling"]
    refute_nil entry, "config/sources.yml must register starling"
    assert_equal Nabu::Adapters::Starling, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first sync (checklist §5/§6)"
    assert_equal "manual", entry.sync_policy
  end
end
