# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The DÉRom adapter (P56-4): the Dictionnaire Étymologique Roman
# (ATILF & Universität des Saarlandes, dir. Buchi/Schweickard) from the
# openly downloadable Ortolang workspace `derom` — the Latin→Romance
# etymological bridge, a RECONSTRUCTION shelf in the la-vul (Proto-Romance /
# Vulgar Latin) code the crosswalk already speaks. Dictionary-shaped, so it
# mirrors the conformance checks the passage suite cannot cover (manifest
# validity, discover→parse round-trip, id uniqueness/stability, NFC, license
# class) and adds: the DÉRom phonological headword fold (stress marks
# dropped, β→b — upstream's own ASCII filename convention), the positional
# idiome→signifiant cognat walk (one cognat can interleave gal./port. runs),
# the renvoi and potiche shapes, the DictionaryLoader contract, the
# language-notes rider, and the define/etym acceptance renders.
#
# LICENSE (the P56-4 gate, fixture ortolang-item-license.json): CC BY-NC-SA
# 4.0 per the workspace's market item metadata → class `nc` — ingestible,
# MCP-surface-excluded.
class DeromTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("derom")

  LAKTE = "'lakt-e" # */ˈlakt-e/ "lait" — the flagship pan-Romance article
  KABALLU = "ka'Ball-u"  # */kaˈβall-u/ "cheval" — the β headword pin
  ARATURA = "ara't-ur-a" # renvoi stub (Lien → Mertens 2021 PDF)

  # --- manifest + content kind -----------------------------------------------------

  def test_manifest_identifies_the_derom_source_with_the_nc_license
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "derom", manifest.id
    assert_equal "nc", manifest.license_class, "CC BY-NC-SA → nc: ingestible, MCP-excluded"
    assert_match(/CC BY-NC-SA 4\.0/, manifest.license)
    assert_match(/Pas d'Utilisation Commerciale/, manifest.license,
                 "the Ortolang license label travels verbatim")
    assert_match(/ATILF/, manifest.credit)
    assert_match(/Buchi/, manifest.credit)
    assert_equal "https://repository.ortolang.fr/api/content/derom/latest", manifest.upstream_url
    assert_equal "derom-xml", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Derom.content_kind
  end

  # --- discover → parse round-trip -------------------------------------------------

  def test_discover_yields_one_ref_per_article_xml_and_nothing_before_a_first_fetch
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["derom:#{LAKTE}", "derom:#{KABALLU}", "derom:#{ARATURA}", "derom:'al-a"],
                 refs.map(&:id)
    assert_equal %w[derom], refs.map(&:source_id).uniq
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_the_la_vul_etymon_shelf
    ref = adapter.discover(FIXTURES).find { |r| r.id == "derom:#{LAKTE}" }
    document = adapter.parse(ref)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "derom", document.slug
    assert_equal "la-vul", document.language,
                 "Proto-Romance rides Wiktionary's la-vul — the code the crosswalk already speaks"
    assert_equal [LAKTE], document.map(&:entry_id)
  end

  def test_etymon_headwords_keep_the_derom_notation_and_fold_typeably
    entries = parse_all
    lakte = entries.fetch(LAKTE)
    assert_equal "ˈlakt-e", lakte.key_raw, "the Signifiant verbatim (U+02C8 stress mark)"
    assert_equal "ˈlakt-e", lakte.headword
    assert_equal "lakt-e", lakte.headword_folded, "stress mark dropped — the typeable lookup key"
    assert_equal "liquide blanchâtre (opaque, légèrement sucré) sécrété par les glandes mammaires",
                 lakte.gloss
    assert lakte.body.start_with?("s.n. « liquide blanchâtre"),
           "the lemma line (catgramm + signifié) opens the body"

    kaballu = entries.fetch(KABALLU)
    assert_equal "kaˈβall-u", kaballu.headword
    assert_equal "kaball-u", kaballu.headword_folded,
                 "β→b — upstream's own ASCII filename convention (ka'Ball-u.xml)"
  end

  # --- the positional cognat walk → reflexes ---------------------------------------

  def test_lakte_mints_the_pan_romance_reflex_set_in_document_order
    reflexes = parse_all.fetch(LAKTE).reflexes
    assert_equal 24, reflexes.size,
                 "24 signifiants, the ast. lleche repeat deduped, PLUS the gal./port. composite " \
                 "citation split into two rows (P57-5) — net +1 over the pre-split 23"
    first = reflexes.first
    assert_equal "ron", first.lang_code,
                 "P57-5: lang_code is now the RESOLVED catalog tag, not the idiome abbreviation verbatim"
    assert_equal "ron", first.language
    assert_equal "lapte", first.word
    assert_equal "lapte", first.word_folded
    refute first.borrowed

    assert_equal %w[lapte lapte lápti lápte látte], reflexes.first(5).map(&:word)
    assert_equal [%w[roh lat], %w[roh latg]],
                 reflexes.select { |r| r.lang_code == "roh" }.map { |r| [r.lang_code, r.word] },
                 "one idiome run (romanch.), two variant signifiants — two rows"
    assert_equal "lapti", reflexes[2].word_folded, "the acute folds off méglénoroum. lápti"
  end

  # P57-5: the idiome→ISO table is now COMPLETE — every idiome in the fixture
  # resolves to a real language code, so lang_code == language everywhere and
  # nothing stays display-only (the former gal./port. joint label is split
  # into two resolved rows, tested separately below).
  def test_idiome_mapping_speaks_iso_codes_for_every_reflex
    reflexes = parse_all.fetch(LAKTE).reflexes
    by_code = reflexes.group_by(&:lang_code)
    assert_equal ["srd"], by_code.fetch("srd").map(&:language)
    assert_equal ["dlm"], by_code.fetch("dlm").map(&:language)
    assert_equal ["ist"], by_code.fetch("ist").map(&:language)
    assert_equal ["vec"], by_code.fetch("vec").map(&:language)
    assert_equal %w[oci oci oci oci], by_code.fetch("oci").map(&:language),
                 "occit. (lait, lach) + lang. (lait) + gasc. (leit) all fold into the one oci code"
    assert_equal ["fra"], by_code.fetch("fra").map(&:language)
    refute reflexes.any? { |r| r.language.nil? }, "P57-5: no display-only reflex rows remain"
  end

  # P57-5: DÉRom's own composite citation shorthand ("gal./port. leite" — one
  # signifiant serving two idiomes at once) is not upstream error; splitting
  # it into two reflex rows is the smaller honest diff versus a synthetic
  # roa-opt code (chosen over the report's alternative — see class comment).
  def test_the_joint_gal_port_citation_splits_into_two_resolved_reflex_rows
    lakte = parse_all.fetch(LAKTE).reflexes.select { |r| r.word == "leite" }
    assert_equal([%w[glg glg leite], %w[por por leite]], lakte.map { |r| [r.lang_code, r.language, r.word] })
  end

  def test_an_interleaved_cognat_attaches_each_signifiant_to_its_preceding_idiome
    reflexes = parse_all.fetch(KABALLU).reflexes
    assert_equal 21, reflexes.size
    tail = reflexes.last(2).map { |r| [r.lang_code, r.language, r.word] }
    assert_equal [%w[glg glg cabalo], %w[por por cavalo]], tail,
                 "ONE cognat interleaves gal./port. runs — positional attachment, not first-idiome " \
                 "(these are already SEPARATE gal./port. idiome elements, not the joint citation)"
  end

  # P57-5: the report's remaining four idiomes (arag./végl./logoud./itsept.)
  # do not occur in the trimmed fixture — pinned directly against the
  # adapter's own table (the MW COGNATE_LANGS precedent) rather than faking
  # upstream XML that never shipped (CLAUDE.md's real-fixtures-only rule).
  def test_idiome_languages_table_resolves_the_p57_5_remaining_four
    table = Nabu::Adapters::DeromXmlParser::IDIOME_LANGUAGES
    assert_equal "arg", table.fetch("arag."), "Aragonese"
    assert_equal "dlm", table.fetch("végl."), "Vegliote — the island dialect of Dalmatian, same ISO as dalm."
    assert_equal "src", table.fetch("logoud."), "Logudorese Sardinian"
    assert_equal "it", table.fetch("itsept."),
                 "northern/septentrional Italian has no dedicated ISO code — mapped to `it` " \
                 "(ISO 639-1) DISTINCT from the plain it. idiome's `ita` (ISO 639-3), so the two " \
                 "stay distinguishable rather than conflated"
  end

  # P59-1: the live census surfaced 61 FINER sub-idiome labels (198 reflex
  # rows) riding the designed verbatim fallback — DÉRom cites dialect
  # geography below the language grain. All but four now resolve, following
  # the table's own folding precedent (gasc. → oci): a sub-idiome folds into
  # its ISO language. Pinned against the table (the P57-5 stance), one
  # exemplar per family plus every non-obvious identification.
  def test_idiome_languages_table_resolves_the_p59_1_sub_idiomes
    table = Nabu::Adapters::DeromXmlParser::IDIOME_LANGUAGES
    { "lomb." => %w[lmo Lombard], "piém." => %w[pms Piedmontese],
      "lig." => %w[lij Ligurian], "sic." => %w[scn Sicilian],
      "cors." => %w[cos Corsican], "campid." => ["sro", "Campidanese Sardinian"],
      "salent." => ["scn", "Salentino - the Extreme-South group"],
      "camp." => ["nap", "Campanian - Continental South, DISTINCT from campid."],
      "itmérid." => ["nap", "southern Italian collectively"],
      "tosc." => ["ita", "Tuscan - the base of Standard Italian"],
      "itcentr." => ["ita", "central Italian dialects"],
      "surs." => ["roh", "Sursilvan Romansh"], "bas-engad." => %w[roh Vallader],
      "haut-engad." => %w[roh Puter],
      "fasc." => ["lld", "Fascian Ladin"], "gherd." => %w[lld Gardenese],
      "bad." => %w[lld Badiot], "mar." => ["lld", "Mareo/Marebbano"],
      "carn." => ["fur", "Carnic Friulian"],
      "prov." => %w[oci Provencal], "béarn." => ["oci", "Bearnese Gascon"],
      "rouss." => ["cat", "Roussillonnais IS Northern Catalan, not Occitan"],
      "sav." => ["frp", "Savoyard francoprovencal"], "lyonn." => %w[frp Lyonnais],
      "aost." => %w[frp Aostan], "SRfrpr." => ["frp", "Suisse-romande frpr."],
      "pic." => %w[pcd Picard], "norm." => %w[nrf Norman], "wall." => %w[wln Walloon],
      "agn." => ["xno", "Anglo-Norman, its own ISO code"],
      "lorr." => ["fra", "codeless oil dialects fold into fra"],
      "oïl." => ["fra", "the langue d'oil group"],
      "mold." => ["ron", "ISO retired mol into ron"], "ban." => ["ron", "Banat dialect"],
      "baléar." => %w[cat Balearic], "cat. centr." => ["cat", "Central Catalan"] }
      .each do |idiome, (code, why)|
      assert_equal code, table.fetch(idiome), "#{idiome} — #{why}"
    end
  end

  def test_genuinely_ambiguous_sub_idiomes_stay_on_the_verbatim_fallback
    table = Nabu::Adapters::DeromXmlParser::IDIOME_LANGUAGES
    ["cal.", "itcentr.-mérid.", "trent.", "émil.-romagn."].each do |idiome|
      refute table.key?(idiome),
             "#{idiome} spans ISO boundaries (N/S Calabria, central-southern Italian, " \
             "Lombard-Venetian transition, the retired eml split) — the designed verbatim " \
             "fallback IS the honest resolution"
    end
  end

  # --- body: materials + commentary ------------------------------------------------

  def test_body_renders_subdivs_cognat_lines_and_the_commentaire
    body = parse_all.fetch(LAKTE).body
    assert_includes body, "I. Substantif neutre originel — */ˈlakt-e/"
    assert_includes body, "romanch. lat, latg"
    assert_includes body, "dacoroum. lapte s.n. « liquide blanchâtre (opaque, légèrement sucré) " \
                          "sécrété par les glandes mammaires, lait »"
    assert_includes body, "Tous les parlers romans sans exception", "the Commentaire rides the body"
    assert_includes parse_all.fetch(KABALLU).body, "gal. cabalo ; port. cavalo"
  end

  # --- the renvoi and potiche shapes -----------------------------------------------

  def test_a_renvoi_stub_is_an_entry_with_gloss_and_link_but_no_reflexes
    entry = parse_all.fetch(ARATURA)
    assert_equal "araˈt-ur-a", entry.headword
    assert_equal "arat-ur-a", entry.headword_folded
    assert_equal "action de labourer ; résultat de cette action", entry.gloss
    assert_empty entry.reflexes
    assert_includes entry.body, "Renvoi : http://www.atilf.fr/DERom/Liens/BiancaMertens/ara't-ur-a.pdf"
  end

  def test_a_potiche_placeholder_is_skipped_not_minted
    ref = adapter.discover(FIXTURES).find { |r| r.id == "derom:'al-a" }
    document = adapter.parse(ref)
    assert_empty document.entries,
                 "<NonRedige/> is upstream's own 'not written yet' flag — no entry claimed"
  end

  def test_entry_ids_are_unique_stable_and_output_is_nfc
    snapshot = -> { parse_all.keys }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
    parse_all.each_value do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
    end
  end

  # --- DictionaryLoader contract ---------------------------------------------------

  def loader_setup(canonical_dir: nil)
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "derom", name: "DÉRom", adapter_class: "Nabu::Adapters::Derom",
      license: "CC BY-NC-SA 4.0", license_class: "nc",
      upstream_url: "https://repository.ortolang.fr/api/content/derom/latest", enabled: false
    )
    [db,
     Nabu::Store::DictionaryLoader.new(db: db, source: source,
                                       language_shelf_dir: canonical_dir && File.join(canonical_dir, Nabu::LanguageShelf::SLUG))]
  end

  def test_loading_twice_is_idempotent_with_stable_urns_and_reflex_rows
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 3, first.added, "two articles + one renvoi; the potiche minted nothing"
    assert_equal 0, first.errored
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
    assert_equal "urn:nabu:dict:derom:#{LAKTE}",
                 db[:dictionary_entries].where(entry_id: LAKTE).get(:urn)
    assert_equal 45, db[:dictionary_reflexes].count,
                 "24 (lakt-e, the gal./port. split counted) + 21 (kaˈβall-u)"
    languages = db[:dictionary_reflexes].select_map(:language)
    %w[ron srd ita fra spa por glg oci].each { |code| assert_includes languages, code }
    refute_includes languages, nil, "P57-5: the idiome table is complete — nothing display-only remains"
  end

  # --- language-notes rider --------------------------------------------------------

  def test_load_accretes_the_la_vul_witness_section_idempotently
    Dir.mktmpdir do |root|
      db, loader = loader_setup(canonical_dir: root)
      loader.load_from(adapter, workdir: FIXTURES)
      shelf = Nabu::LanguageShelf.new(dir: File.join(root, Nabu::LanguageShelf::SLUG))
      section = shelf.load("la-vul").section("witness:derom")
      assert_equal "derom", section.source, "per-record provenance, the P18-5 contract"
      assert_match(/Dictionnaire Étymologique Roman/, section.body)
      assert_equal section.body,
                   db[:language_records].where(lang_code: "la-vul", kind: "witness:derom").get(:body)
      before = File.read(shelf.path_for("la-vul"))
      loader.load_from(adapter, workdir: FIXTURES)
      assert_equal before, File.read(shelf.path_for("la-vul")),
                   "re-loading writes nothing — the latest-body check"
    end
  end

  # --- acceptance renders (define / etym on the fixture shelf) ---------------------

  def test_define_finds_the_etymon_by_its_typeable_fold
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Define.new(catalog: db).run("lakt-e")
    assert_equal 1, results.size
    result = results.first
    assert_equal "ˈlakt-e", result.headword,
                 "la-vul is not a -pro shelf: no display asterisk (the wiktionary-cu precedent)"
    assert_empty result.reflexes,
                 "define's reflex panel is -pro-gated (the wiktionary-cu precedent; widening " \
                 "the recon predicate to la-vul is a flagged owner decision, not this packet's)"
    assert_includes result.body, "romanch. lat, latg",
                    "the cognat material still reads — it rides the body"
  end

  # Both lects lanes pinned EXPLICITLY (never :auto in a test — outcomes may
  # not depend on whether this box has canonical/nabu-lects synced): absent
  # module = the old -pro string test (la-vul unasterisked, the
  # wiktionary-cu treatment); present module = the D57-d RULED state (the
  # per-source override resolves derom's la-vul to roa:pro, mode
  # reconstructed → display asterisk).
  def test_etym_walks_a_romance_reflex_to_the_proto_romance_etymon
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Etym.new(catalog: db, lects: nil).run("lapte")
    assert_equal ["ˈlakt-e"], results.map(&:headword)
    assert_equal "derom", results.first.dictionary_slug
    assert_equal "lapte", results.first.matched_reflex.word
    cheval = Nabu::Query::Etym.new(catalog: db, lects: nil).run("cheval")
    assert_equal ["kaˈβall-u"], cheval.map(&:headword)
  end

  def test_etym_asterisks_the_etymon_when_the_lects_module_is_present
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    fixture_lects = Nabu::Lects.load(
      Nabu::TestSupport.fixtures("nabu-lects"),
      overrides_path: File.join(Nabu::TestSupport.fixtures("nabu-lects"), "lect_overrides.yml")
    )
    results = Nabu::Query::Etym.new(catalog: db, lects: fixture_lects).run("lapte")
    assert_equal ["*ˈlakt-e"], results.map(&:headword),
                 "D57-d ruled: derom la-vul → roa:pro (reconstructed) — the asterisk is earned via mode"
    assert_equal "roa:pro", results.first.lect_id
  end

  # --- fetch (WebMock only) --------------------------------------------------------

  BASE = "https://repository.ortolang.example/api/content/derom/latest"

  def stub_open_collections
    listings = { "1 Fichiers XML articles DERom 1" => "listing-1.html",
                 "2 Fichiers XML articles DERom 2" => "listing-2.html",
                 "3 Fichiers XML articles DERom 3" => "listing-3.html",
                 "5 Fichiers XML articles de renvoi a Mertens 2021" => "listing-5.html",
                 "6 Fichiers XML articles potiches en attente" => "listing-6.html" }
    listings.each do |collection, fixture|
      stub_request(:get, Nabu::DeromFetch.collection_url(BASE, collection))
        .to_return(status: 200, body: File.binread(File.join(FIXTURES, "fetch", fixture)),
                   headers: { "Content-Type" => "text/html" })
    end
    xml = File.binread(File.join(FIXTURES, "6 Fichiers XML articles potiches en attente", "'al-a.xml"))
    stub_request(:get, %r{#{Regexp.escape(BASE)}/.+\.xml\z})
      .to_return(status: 200, body: xml, headers: { "Content-Type" => "application/xml" })
  end

  def test_fetch_crawls_the_open_collections_and_discovers_in_place
    stub_open_collections
    Dir.mktmpdir do |workdir|
      report = adapter(base_url: BASE).fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      assert_match(/5 open collection indexes/, report.notes)
      landed = Dir.glob(File.join(workdir, "**", "*.xml")).map { |p| File.basename(p) }.sort
      assert_equal ["'Bakk-a.xml", "'akr-u.xml", "'al-a.xml", "'lakt-e.xml",
                    "ara't-ur-a.xml", "ka'Ball-u.xml"], landed
      assert File.file?(File.join(workdir, "1 Fichiers XML articles DERom 1", "'lakt-e.xml")),
             "records land under their upstream collection directory"
    end
  end

  def test_fetch_aborts_on_an_auth_gated_or_reshaped_listing
    stub_open_collections
    stub_request(:get, Nabu::DeromFetch.collection_url(BASE, "2 Fichiers XML articles DERom 2"))
      .to_return(status: 200, body: File.binread(File.join(FIXTURES, "fetch", "auth-gate.html")),
                 headers: { "Content-Type" => "text/html" })
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { adapter(base_url: BASE).fetch(workdir) }
      assert_match(/auth-gated or reshaped/, error.message)
      assert_empty Dir.glob(File.join(workdir, "**", "*.xml")), "abort lands nothing"
    end
  end

  def test_probe_heads_the_first_collection_listing
    assert_equal :http_zip, Nabu::Adapters::Derom.remote_probe_strategy
    targets = Nabu::Adapters::Derom.http_probe_targets
    assert_equal 1, targets.size
    assert_includes targets.first.zip_url, "1%20Fichiers%20XML%20articles%20DERom%201"
    assert_equal Nabu::DeromFetch::STATE_FILE, targets.first.state_file
  end

  # --- registry ---------------------------------------------------------------------

  def test_registry_row_exists_wired_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["derom"]
    refute_nil entry, "config/sources.yml must register derom"
    assert_equal Nabu::Adapters::Derom, entry.adapter_class
    assert entry.wired, "first sync owner-verified 2026-08-02 (513 docs / 233 entries) — the flip is the ruled state"
    assert_equal "manual", entry.sync_policy
    assert_includes entry.axes, "romance"
    assert_includes entry.axes, "etym"
  end

  private

  def adapter(base_url: nil)
    base_url ? Nabu::Adapters::Derom.new(delay: 0, base_url: base_url) : Nabu::Adapters::Derom.new(delay: 0)
  end

  def parse_all
    adapter.discover(FIXTURES).flat_map { |ref| adapter.parse(ref).entries }
                              .to_h { |entry| [entry.entry_id, entry] }
  end
end
