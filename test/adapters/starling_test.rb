# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The StarLing adapter (P22-0 + P23-0): the Tower of Babel IE package's
# five etymological bases — Pokorny's IEW (Starostin/Lubotsky digitization),
# Nikolayev's Walde-Pokorny-based PIE database, Vasmer's Russian dictionary,
# and the Common Germanic + Baltic subordinate bases — under G. Starostin's
# 2026-07-15 any-use-with-acknowledgment grant (per-base compiler credit
# REQUIRED — it must ride the manifest license string onto every serving
# surface). Dictionary-shaped, so like LivTest/MwTest it MIRRORS the
# passage-shaped conformance suite (manifest validity, discover→parse
# round-trip, id uniqueness/stability, NFC, license class) and adds the
# packet pins: the ἆ font-shift and chslav азъ decodes proven end to end on
# real records, the per-base reflex verdicts (single-language attested
# columns mint rows; proto/mixed/variety-ambiguous columns and label-led
# cells stay in the body), the upstream NUMBER collisions (piet #574 — the
# owner's live quarantine — and baltet's six) parsing whole with stable -b
# suffixes, the cross-base crosslinks both ways, the DictionaryLoader
# contract, the language-notes rider, gold attestation via ReflexViews, and
# define/etym acceptance renders.
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

  # P23-0: the three follow-up bases' credits, each in ITS OWN upstream
  # words — germet/baltet from their .inf DBINFO texts; vasmer's .inf is
  # BLANK, so its credit quotes the descrip.php roster paragraph verbatim
  # (the grant names the roster as the credit source).
  def test_manifest_carries_the_follow_up_bases_credits_verbatim
    license = adapter.manifest.license
    assert_match(/Common Germanic database, compiled by S\. Nikolayev and subordinate to the Common Indo-European/,
                 license, "germet credit: the germet.inf DBINFO sentence")
    assert_match(/Baltic database, compiled by S\. Nikolayev and subordinate to the Proto-Indo-European/,
                 license, "baltet credit: the baltet.inf DBINFO sentence")
    assert_match(/scanned, OCR'd, and database-converted versions of M\. Vasmer's etymological dictionary/,
                 license, "vasmer credit: the roster's actual words (vasmer.inf is blank)")
  end

  def test_content_kind_is_dictionary_and_the_source_promises_reflexes
    assert_equal :dictionary, Nabu::Adapters::Starling.content_kind
    assert Nabu::Adapters::Starling.reflex_bearing?
  end

  # --- discover → parse round-trip --------------------------------------------------

  def test_discover_yields_one_ref_per_base_in_registry_order
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["starling-pokorny:pokorny.dbf", "starling-piet:piet.dbf",
                  "starling-vasmer:vasmer.dbf", "starling-germet:germet.dbf",
                  "starling-baltet:baltet.dbf"], refs.map(&:id)
    assert_equal %w[starling] * 5, refs.map(&:source_id)
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
    assert_equal %w[1 562 574 1501 574-b 3278], entries.keys
    entry = entries["562"]
    assert_equal "kol-", entry.headword, "leading asterisk stripped (the kaikki convention)"
    assert_equal "*kol-", entry.key_raw
    assert_equal "neck", entry.gloss
    assert_includes entry.body, "Russ. meaning: шея"
    assert_includes entry.body, "Latin: collus, -ī m., collum , -ī n.", "branch columns verbatim in the body"
    assert_includes entry.body, "Pokorny: #1089", "REFERNUM crosslinks back to the pokorny shelf"
    assert_includes entry.body, "Baltic etymology: #1634"
    assert_includes entry.body, "Germanic etymology: #390"
    assert_includes entries["1501"].body, "Vasmer: #12561",
                    "SLAVNUM points into the vasmer base — #12561 is IN this fixture set (P23-0)"
    assert_includes entries["1"].body, "Nostratic etymology: #721"
  end

  # --- the P23-0 bases: vasmer -------------------------------------------------------

  def test_parse_vasmer_yields_the_russian_shelf_with_the_live_site_field_labels
    document = parse("starling-vasmer")
    assert_equal "starling-vasmer", document.slug
    assert_equal "rus", document.language
    entries = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 20 12561], entries.keys, "entry id = the stable upstream NUMBER"
    entry = entries["20"]
    assert_equal "абракада́бра", entry.headword
    assert_equal "абракадабра", entry.headword_folded, "generic fold strips the acute"
    assert_nil entry.gloss, "vasmer has no gloss column — an honest absence"
    # field labels: vasmer.inf is BLANK; these are the live CGI's own labels
    # (web-verified on #20, 2026-07-15)
    assert_includes entry.body, "Near etymology: \"заклинание на амулетах\"."
    assert_includes entry.body, "Further etymology: Скорее всего, через нем. Abrakadabra"
    assert_includes entry.body, "Trubachev's comments: [Гипотезу о фракийском первоисточнике"
    assert_includes entry.body, "Editorial comments: [Совр. знач. \"бессмыслица\". -- Ред.]"
    assert_includes entry.body, "Pages: 1,56"
  end

  def test_vasmer_headwords_stay_verbatim_and_mint_no_reflexes
    entries = parse("starling-vasmer").entries.to_h { |e| [e.entry_id, e] }
    assert_equal "сига́ть,", entries["12561"].headword,
                 "the dictionary's inflection-follows comma stays (the live site renders it too)"
    assert_equal "сигать", entries["12561"].headword_folded, "the fold takes the first comma-variant"
    assert_includes entries["12561"].body, "др.-инд. c̨īghrás", "ORIGIN rides as Further etymology"
    assert entries.values.all? { |e| e.reflexes.empty? },
           "vasmer's fields are scholarly prose — no reflex columns, body-only (the P23-0 verdict)"
  end

  # THE chslav pin: vasmer #1 GENERAL cites OCS азъ in the Church Slavonic
  # font range (\x01\x87…), decoded through the second vendored table.
  def test_vasmer_decodes_the_church_slavonic_font_range_end_to_end
    body = parse("starling-vasmer").entries.first.body
    assert_includes body, "Название: аз, ст.-слав. азъ \"я\"."
    refute_includes body, "\u{FFFD}", "no honest-replacement residue in the fixture records"
  end

  # --- the P23-0 bases: germet -------------------------------------------------------

  def test_parse_germet_yields_the_gem_pro_shelf_with_the_ie_crosslink
    document = parse("starling-germet")
    assert_equal "gem-pro", document.language
    entries = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 390 401 513], entries.keys
    entry = entries["390"]
    assert_equal "xálsa-z", entry.headword
    assert_equal "*xálsa-z", entry.key_raw
    assert_equal "xalsa-z", entry.headword_folded
    assert_equal "neck", entry.gloss
    assert_includes entry.body, "Gothic: hals m. (a) `neck'", "the .inf aliases label the body lines"
    assert_includes entry.body, "Old English: heals (hals), -es m. `neck, prow of a ship'"
    assert_includes entry.body, "IE etymology: #562",
                    "PRNUM crosslinks into the piet shelf (both ways: piet #562 GERMNUM=390)"
  end

  def test_germet_single_language_columns_mint_reflex_rows_that_join_the_gold_codes
    reflexes = parse("starling-germet").entries.to_h { |e| [e.entry_id, e] }["390"].reflexes
    assert_equal [%w[GOT got], %w[ONORD non], %w[NORW no], %w[SWED sv], %w[DAN da],
                  %w[OENGL ang], %w[OFRIS ofs], %w[OSAX osx], %w[MDUTCH dum], %w[DUTCH nl],
                  %w[MLG gml], %w[OHG goh], %w[MHG gmh], %w[HG de]],
                 reflexes.map { |r| [r.lang_code, r.language] },
                 "lang_code = upstream column verbatim; language = catalog gold tag (got/ang) " \
                 "or the Wiktionary code the kaikki crosswalk speaks"
    words = reflexes.to_h { |r| [r.lang_code, r] }
    assert_equal "hals", words["GOT"].word
    assert_equal "heals", words["OENGL"].word, "the leading citation form only"
    assert_equal Nabu::Normalize.search_form("heals", language: "ang"), words["OENGL"].word_folded
    assert_equal "Gothic", words["GOT"].lang_name, "the .inf field alias feeds the language census"
  end

  # The censused stop-token gate (P23-0): germet cells that LEAD with a
  # dialect/variety label (CrimGot, NIsl, OGutn, OWFris …) mint nothing —
  # the label is not a citation form. germet #513's GOT cell is Crimean
  # Gothic; the cell still rides the body verbatim.
  def test_dialect_label_prefixed_cells_mint_nothing_but_ride_the_body
    entries = parse("starling-germet").entries.to_h { |e| [e.entry_id, e] }
    assert_empty entries["513"].reflexes, "GOT `CrimGot marzus` is label-prefixed — no row"
    assert_includes entries["513"].body, "Gothic: CrimGot marzus `nuptiae'"
    assert_equal "marϑiō ?", entries["513"].headword, "doubt-marked root verbatim (canonical means canonical)"
  end

  # EASTFRIS and OLFRANK are variety-ambiguous columns (Fris./ONFrank/
  # SalFrank label mixes, censused ~47% label-led) — body-only by verdict,
  # like piet's mixed IRAN/ITAL/CELT/TOKH. germet #1's OLFRANK cell pins it.
  def test_variety_ambiguous_columns_stay_body_only
    entry = parse("starling-germet").entries.first
    assert_includes entry.body, "Old Franconian: ONFrank ēr"
    refute_includes entry.reflexes.map(&:lang_code), "OLFRANK"
    got = entry.reflexes.find { |r| r.lang_code == "GOT" }
    assert_equal "air", got.word, "the clean columns of the same record still mint"
  end

  # --- the P23-0 bases: baltet -------------------------------------------------------

  def test_parse_baltet_yields_the_bat_pro_shelf_with_the_ie_crosslink
    document = parse("starling-baltet")
    assert_equal "bat-pro", document.language
    entry = document.entries.to_h { |e| [e.entry_id, e] }["1634"]
    assert_equal "kakla-", entry.headword
    assert_equal "neck; throat", entry.gloss
    assert_includes entry.body, "Lithuanian: kãklas `шея; горло'"
    assert_includes entry.body, "Comments: kraklan 'breast'"
    assert_includes entry.body, "Indo-European etymology: #562",
                    "PRNUM crosslinks into the piet shelf (both ways: piet #562 BALTNUM=1634)"
    assert_equal [%w[LITH lt], %w[LETT lv]], entry.reflexes.map { |r| [r.lang_code, r.language] },
                 "OLITH/OPRUS are empty here — the minting columns speak Wiktionary codes"
    assert_equal "kãklas", entry.reflexes.first.word
  end

  # Upstream data defect, kept honest (P23-0 census): six baltet records
  # carry a NUMBER another record already used (76/95/248/689/1049/1394) —
  # exactly the six piet BALTNUM links that dangle. The FIRST record keeps
  # the NUMBER as its entry id; a repeat gets a stable file-order suffix.
  def test_baltet_duplicate_numbers_disambiguate_stably
    entries = parse("starling-baltet").entries.to_a
    assert_equal %w[76 76-b 1634], entries.map(&:entry_id)
    assert_equal "blus-ā̂ f.", entries[0].headword, "file order rules: the flea record wears the NUMBER"
    assert_equal "dal-i-s f., *dal-jā̂ f.", entries[1].headword
    assert_includes entries[1].body, "Indo-European etymology: #178", "each keeps its own PRNUM"
    assert_includes entries[1].body, "note: upstream NUMBER collision",
                    "the suffixed record says so honestly in its body"
    assert_equal %w[blusà blusa Bluskaym], entries[0].reflexes.map(&:word),
                 "LITH/LETT/OPRUS rows — Old Prussian's onomastic Bluskaym is a real citation form"
    assert_equal "dalìs", entries[1].reflexes.first.word, "the second duplicate mints its own rows"
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

  # THE OWNER'S LIVE QUARANTINE (2026-07-16): piet.dbf carries exactly one
  # upstream NUMBER collision — record #574 (*kōim- 'village') and, sitting
  # where the vacant 1574 belongs in an otherwise consecutive run, a second
  # record also stamped 574 (*kneuk- 'to shout'; evidently a dropped
  # leading "1"). The live CGI itself serves "Total of 2 records" for
  # number 574. The whole 3,291-entry file was quarantined by the duplicate
  # guard. Verdict: file parses whole; the first occurrence keeps the plain
  # id (so pokorny-side "#574" crosslinks resolve to the village root); the
  # second mints the stable -b suffix and says so in its body. Never
  # renumbered to 1574 — canonical means canonical.
  def test_piet_upstream_number_collision_parses_whole_with_a_stable_suffix_and_note
    entries = parse("starling-piet").entries.to_h { |e| [e.entry_id, e] }
    assert_equal "kōim-", entries["574"].headword, "the first occurrence wears the plain NUMBER"
    assert_equal "village", entries["574"].gloss
    refute_includes entries["574"].body, "note: upstream NUMBER collision",
                    "the plain-id record carries no note — nothing is wrong with it"
    collided = entries["574-b"]
    assert_equal "kneuk-, -g-", collided.headword
    assert_equal "to shout", collided.gloss
    assert_includes collided.body, "note: upstream NUMBER collision — this record shares NUMBER 574"
    assert_includes collided.body, "disambiguated mechanically as 574-b"
    assert_includes collided.body, "Pokorny: #985", "its own crosslinks are intact"
  end

  # The second whole-file quarantine class (P23-0 census): headword-less
  # records — piet carries six content-bearing Iranian stubs at the file
  # tail (the live CGI serves "Total of 0 records" for them; the content
  # exists only in the downloadable package), germet six and baltet seven
  # fully-empty numbered slots. They keep their slot under the mechanical
  # "#NUMBER" placeholder so nothing upstream is hidden and crosslinks at
  # those numbers stay resolvable.
  def test_headword_less_records_keep_their_slot_under_the_number_placeholder
    piet = parse("starling-piet").entries.to_h { |e| [e.entry_id, e] }["3278"]
    assert_equal "#3278", piet.headword
    assert_includes piet.body, "Other Iranian: Sogd. nɣz, Yag. naɣz 'good'",
                    "the content-bearing stub's real material rides the body"
    assert_empty piet.reflexes, "IRAN is a mixed column — body-only"
    empty = parse("starling-germet").entries.to_h { |e| [e.entry_id, e] }["401"]
    assert_equal "#401", empty.headword
    assert_equal "#401", empty.body, "a fully-empty numbered slot reads as its own placeholder"
    assert_nil empty.gloss
  end

  def test_entry_ids_are_unique_stable_and_output_is_nfc
    %w[starling-pokorny starling-piet starling-vasmer starling-germet starling-baltet].each do |slug|
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

  BASE_FILES = %w[pokorny piet vasmer germet baltet].flat_map { |base| ["#{base}.dbf", "#{base}.var"] }.freeze

  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      BASE_FILES.each { |name| FileUtils.cp(File.join(FIXTURES, name), dir) }
      zip = File.join(dir, "IE.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", zip, *BASE_FILES) }
      File.binread(zip)
    end
  end

  def test_fetch_unpacks_the_package_and_discovers_all_five_bases
    stub_request(:get, ZIP_URL).to_return(status: 200, body: zip_body)
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      refs = adapter.discover(workdir).to_a
      assert_equal ["starling-pokorny:pokorny.dbf", "starling-piet:piet.dbf",
                    "starling-vasmer:vasmer.dbf", "starling-germet:germet.dbf",
                    "starling-baltet:baltet.dbf"], refs.map(&:id)
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
    assert_equal 19, first.added,
                 "3 records per base + both halves of each fixture NUMBER collision + the two headword-less pins"
    assert_equal 0, first.errored
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 19, second.skipped
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
    assert_equal "urn:nabu:dict:starling-pokorny:1089",
                 db[:dictionary_entries].where(entry_id: "1089").get(:urn)
    assert_equal "urn:nabu:dict:starling-vasmer:12561",
                 db[:dictionary_entries].where(entry_id: "12561").get(:urn),
                 "piet #1501's `Vasmer: #12561` body line now names a live entry id"
    assert_equal ["urn:nabu:dict:starling-baltet:76-b", "urn:nabu:dict:starling-piet:574-b"],
                 db[:dictionary_entries].where(Sequel.like(:entry_id, "%-b")).select_order_map(:urn),
                 "the duplicate-NUMBER disambiguation is urn-stable"
    assert_equal 36, db[:dictionary_reflexes].count,
                 "piet 5 + germet 24 (10+14+0, stop-gated) + baltet 7 (3+2+2)"
    assert_equal ["Albanian", "Avestan", "Danish", "Dutch", "English", "German", "Gothic",
                  "Latin", "Lettish", "Lithuanian", "Middle Dutch", "Middle High German",
                  "Middle Low German", "Norwegian", "Old English", "Old Frisian",
                  "Old High German", "Old Indian", "Old Norse", "Old Prussian",
                  "Old Saxon", "Swedish"],
                 db[:language_names].select_map(:name).sort.uniq,
                 "the .inf aliases feed the language census reflex_bearing health checks"
  end

  # germet's GOT/OENGL columns JOIN THE GOLD (the P23-0 crosswalk question):
  # attested counts resolve at query time via ReflexViews against the
  # fulltext lemma index — got and ang are gold-lemma languages of this
  # catalog (Wulfila/PROIEL; the OE shelves).
  def test_germet_gothic_and_old_english_reflexes_resolve_attested_counts_against_gold
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    fulltext = Sequel.sqlite
    fulltext.create_table(:passage_lemmas) do
      String :lemma_folded, null: false
      String :lemma_raw, null: false
      Integer :passage_id, null: false
      String :urn, null: false
      String :language, null: false
      String :surface_forms, null: false
      index :lemma_folded
    end
    row = { lemma_raw: "hals", passage_id: 1, urn: "urn:nabu:test:1", surface_forms: "hals" }
    got_folded = Nabu::Normalize.search_form("hals", language: "got")
    ang_folded = Nabu::Normalize.search_form("heals", language: "ang")
    fulltext[:passage_lemmas].insert(row.merge(language: "got", lemma_folded: got_folded))
    fulltext[:passage_lemmas].insert(row.merge(language: "got", lemma_folded: got_folded, passage_id: 2))
    fulltext[:passage_lemmas].insert(row.merge(language: "ang", lemma_folded: ang_folded, lemma_raw: "heals"))
    entry_row_id = db[:dictionary_entries].where(entry_id: "390").get(:id)
    views = Nabu::Query::ReflexViews.new(catalog: db, fulltext: fulltext).for_entry(entry_row_id)
    counts = views.to_h { |v| [v.language, v.attested_count] }
    assert_equal 2, counts["got"], "Gothic hals joins the got gold lemma index"
    assert_equal 1, counts["ang"], "Old English heals joins the ang gold"
    assert_nil counts["nl"], "no Dutch gold here — an honest absence, never a zero claim"
  end

  # --- language-notes rider ----------------------------------------------------------

  def test_load_accretes_the_witness_sections_idempotently
    Dir.mktmpdir do |root|
      _db, loader = loader_setup(canonical_dir: root)
      loader.load_from(adapter, workdir: FIXTURES)
      shelf = Nabu::LanguageShelf.new(dir: Nabu::LanguageShelf.dir(root))
      section = shelf.load("ine-pro").section("witness:starling")
      assert_equal "starling", section.source
      assert_match(/Pokorny/, section.body)
      assert_match(/Nikolayev/, section.body)
      # P23-0: one honest witness note per follow-up base's language
      assert_match(/Vasmer/, shelf.load("rus").section("witness:starling").body)
      assert_match(/Common Germanic/, shelf.load("gem-pro").section("witness:starling").body)
      assert_match(/Proto-Baltic/, shelf.load("bat-pro").section("witness:starling").body)
      before = %w[ine-pro rus gem-pro bat-pro].map { |code| File.read(shelf.path_for(code)) }
      loader.load_from(adapter, workdir: FIXTURES)
      assert_equal before, %w[ine-pro rus gem-pro bat-pro].map { |code| File.read(shelf.path_for(code)) },
                   "a second load accretes nothing new"
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

  # P23-0 acceptance: a vasmer entry serves with the grant + the roster's
  # vasmer credit on its license lane (the render every surface shares).
  def test_define_a_vasmer_word_serves_the_credit_line_and_the_decoded_body
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Define.new(catalog: db).run("сигать")
    assert_equal ["starling-vasmer"], results.map(&:dictionary_slug)
    result = results.first
    assert_equal "urn:nabu:dict:starling-vasmer:12561", result.urn
    assert_match(/properly acknowledged/, result.license, "the grant rides the result")
    assert_match(/M\. Vasmer's etymological dictionary/, result.license,
                 "the roster's vasmer credit rides the result")
    assert_includes result.body, "Near etymology:"
  end

  def test_etym_walks_a_gothic_reflex_to_the_germet_proto_form
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Etym.new(catalog: db).run("hals")
    assert_equal ["starling-germet"], results.map(&:dictionary_slug).uniq
    assert(results.map(&:headword).any? { |headword| headword.include?("xálsa-z") })
  end

  # --- registry -----------------------------------------------------------------------

  def test_registry_row_is_live_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["starling"]
    refute_nil entry, "config/sources.yml must register starling"
    assert_equal Nabu::Adapters::Starling, entry.adapter_class
    assert entry.enabled, "live (owner sign-off 2026-07-16: synced incl. piet 574-b, eyeballed, flipped)"
    assert_equal "manual", entry.sync_policy
  end
end
