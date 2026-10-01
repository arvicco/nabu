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
  KART_URL = "https://starlingdb.org/download/KART.exe"

  # P104-3: the six further download packages (same shelf, same grant),
  # each a plain zip despite the .exe name, each in its own subdir.
  PACKAGE_URLS = {
    "kart" => KART_URL,
    "altaic" => "https://starlingdb.org/download/ALTAIC.exe",
    "cauc" => "https://starlingdb.org/download/CAUC.exe",
    "sintib" => "https://starlingdb.org/download/SINTIB.exe",
    "drav" => "https://starlingdb.org/download/DRAV.exe",
    "chukchee" => "https://starlingdb.org/download/CHUKCHEE.exe",
    "yenisey" => "https://starlingdb.org/download/YENISEY.exe"
  }.freeze

  ALL_BASE_IDS = ["starling-pokorny:pokorny.dbf", "starling-piet:piet.dbf",
                  "starling-vasmer:vasmer.dbf", "starling-germet:germet.dbf",
                  "starling-baltet:baltet.dbf", "starling-kart:kartet.dbf",
                  "starling-altet:altet.dbf", "starling-japet:japet.dbf",
                  "starling-caucet:caucet.dbf", "starling-stibet:stibet.dbf",
                  "starling-dravet:dravet.dbf", "starling-kamet:kamet.dbf",
                  "starling-chuket:chuket.dbf", "starling-itelet:itelet.dbf",
                  "starling-yenet:yenet.dbf", "starling-iranet:iranet.dbf",
                  "starling-lexstat-balt:balt.dbf", "starling-lexstat-germ:germ.dbf"].freeze

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

  # P46-6: the sixth base — the Kartvelian etymological dictionary (KART.exe,
  # a second package under the SAME 2026-07-15 site-wide grant). Credit is the
  # kartet.inf DBINFO sentence + the descrip.php roster item 6, both verbatim.
  def test_manifest_carries_the_kart_credit_verbatim
    manifest = adapter.manifest
    assert_match(/Kartvelian/, manifest.name)
    assert_match(/compiled by S\. Starostin on the basis of G\. Klimov's and Faehnrich-Sardhveladze's/,
                 manifest.license, "kart credit: the kartet.inf DBINFO sentence")
    assert_match(/Compiled by Sergei Starostin/, manifest.license, "kart credit: the roster's own words")
  end

  # P104-3: the six further packages' credits, each in ITS OWN upstream
  # words — the .inf DBINFO texts of the family-head bases (the grant's
  # express condition: name the specific compilers of each database).
  def test_manifest_carries_the_six_further_packages_credits_verbatim
    manifest = adapter.manifest
    assert_match(/Altaic/, manifest.name)
    license = manifest.license
    assert_match(/'Altaic Etymological Dictionary' by S\. Starostin, A\. Dybo and O\. Mudrak/,
                 license, "altet credit: the altet.inf DBINFO sentence")
    assert_match(/the Japanese part/, license, "japet credit: the japet.inf DBINFO sentence")
    assert_match(/S\. L\. Nikolayev, S\. A\. Starostin, 'A North Caucasian Etymological Dictionary', Moscow 1994/,
                 license, "caucet credit: the caucet.inf DBINFO sentence")
    assert_match(/based on Peiros-Starostin 1996, but containing improved reconstructions/,
                 license, "stibet credit: the stibet.inf DBINFO sentence")
    assert_match(/Lepcha data were input.*by Olga Mazo/, license, "stibet credit: the Lepcha compiler")
    assert_match(/T\. Burrow and M\. B\. Emeneau, revised and significantly modified by G\. Starostin/,
                 license, "dravet credit: the dravet.inf DBINFO sentence")
    assert_match(/O\. Mudrak's Chukchee-Kamchatkan database/, license,
                 "kamet/chuket/itelet credit: the .inf DBINFO texts")
    assert_match(/Comparative vocabulary of the Yenisseian languages, published as Starostin 1995/,
                 license, "yenet credit: the yenet.inf DBINFO sentence")
  end

  # P113-2: the IE package's LEXSTAT/ tables ride the license lane with
  # the provenance the package itself states (their .inf files carry no
  # DBINFO credit line).
  def test_manifest_carries_the_lexstat_tables_credit
    manifest = adapter.manifest
    assert_match(/lexicostatistical wordlists/, manifest.name)
    assert_match(/LEXSTAT/, manifest.license, "the wordlist shelves' provenance rides every serving surface")
  end

  def test_content_kind_is_dictionary_and_the_source_promises_reflexes
    assert_equal :dictionary, Nabu::Adapters::Starling.content_kind
    assert Nabu::Adapters::Starling.reflex_bearing?
  end

  # --- discover → parse round-trip --------------------------------------------------

  def test_discover_yields_one_ref_per_base_in_registry_order
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ALL_BASE_IDS, refs.map(&:id)
    assert_equal %w[starling] * 18, refs.map(&:source_id)
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
    assert_equal %w[got non no sv da ang ofs osx dum nl gml goh gmh de],
                 reflexes.map(&:lang_code),
                 "lang_code = the RESOLVED catalog tag (P57-5: the upstream column siglum used to " \
                 "leak through verbatim — GOT/ONORD/… — even though the adapter already resolved " \
                 "the proper code into `language`; now lang_code == language)"
    assert_equal reflexes.map(&:language), reflexes.map(&:lang_code), "lang_code and language now agree"
    words = reflexes.to_h { |r| [r.lang_code, r] }
    assert_equal "hals", words["got"].word
    assert_equal "heals", words["ang"].word, "the leading citation form only"
    assert_equal Nabu::Normalize.search_form("heals", language: "ang"), words["ang"].word_folded
    assert_equal "Gothic", words["got"].lang_name, "the .inf field alias feeds the language census"
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
    refute_includes entry.reflexes.map(&:lang_code), "OLFRANK", "OLFRANK never resolves — mints no row at all"
    got = entry.reflexes.find { |r| r.lang_code == "got" }
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
    assert_equal %w[lt lv], entry.reflexes.map(&:lang_code),
                 "OLITH/OPRUS are empty here; lang_code is now the RESOLVED code (P57-5), " \
                 "not the upstream LITH/LETT siglum"
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

  # --- the kart base (P46-6: the Kartvelian dictionary, second package) -------------

  # The Klimov pin: kartet #1 *abed- 'tinder' — decoded output verified
  # against the live starlingdb.org CGI rendering on 2026-07-26 (fixture
  # README). The shelf language ccs-pro is minted by the family-code +
  # -pro convention (the bat-pro precedent; ISO 639-5 ccs = Kartvelian).
  def test_parse_kart_yields_the_ccs_pro_shelf_pinned_against_klimov
    document = parse("starling-kart")
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "starling-kart", document.slug
    assert_equal "ccs-pro", document.language
    entry = document.entries.to_h { |e| [e.entry_id, e] }["1"]
    assert_equal "abed-", entry.headword, "headword = PROTO minus the display asterisk"
    assert_equal "*abed-", entry.key_raw, "the upstream asterisk stays verbatim in key_raw"
    assert_equal "abed-", entry.headword_folded, "root fold keeps the trailing stem hyphen"
    assert_equal "tinder", entry.gloss
    assert_includes entry.body, "Russian meaning: трут", "field labels are the kartet.inf aliases"
    assert_includes entry.body, "Georgian: abed-"
    assert_includes entry.body, "Svan: haböd-, habed-, hobed-"
    assert_includes entry.body, "Notes and references: ЭСКЯ 43."
  end

  def test_kart_single_language_columns_mint_reflex_rows
    entry = parse("starling-kart").entries.to_h { |e| [e.entry_id, e] }["1"]
    assert_equal %w[ka xmf sva lzz], entry.reflexes.map(&:lang_code),
                 "lang_code = the RESOLVED catalog tag (P57-5); language carries the same value"
    assert_equal entry.reflexes.map(&:language), entry.reflexes.map(&:lang_code)
    words = entry.reflexes.to_h { |r| [r.lang_code, r] }
    assert_equal "abed-", words["ka"].word
    assert_equal "obed-", words["xmf"].word
    assert_equal "haböd-", words["sva"].word, "the leading citation form only — variants stay in the body"
    assert_equal "Georgian", words["ka"].lang_name, "the .inf field alias feeds the language census"
    assert entry.reflexes.none?(&:borrowed)
  end

  def test_kart_nostratic_crosslink_rides_the_body_like_piets
    entry = parse("starling-kart").entries.to_h { |e| [e.entry_id, e] }["2"]
    assert_equal "ac̣-", entry.headword
    assert_includes entry.body, "Nostratic etymology: #1207",
                    "PRNUM points into the unheld nostret base — a body line, exactly piet's PRNUM"
  end

  # kart's own upstream NUMBER collision (censused on the full 1,310-record
  # base: 48 twice, 134 twice — the second 134 sits at file position 1133,
  # evidently a dropped leading "1", piet's #574 shape exactly). The fixture
  # keeps both 48 records; the mechanical -b suffix + body note apply.
  def test_kart_duplicate_numbers_disambiguate_stably
    entries = parse("starling-kart").entries.to_a
    assert_equal %w[1 2 21 48 48-b], entries.map(&:entry_id)
    assert_equal "berq-", entries[3].headword, "file order rules: the foot/step record wears the NUMBER"
    assert_equal "ćwet-", entries[4].headword
    assert_includes entries[4].body, "note: upstream NUMBER collision"
  end

  # --- the P104-3 packages: altet + japet (ALTAIC) -----------------------------------

  # The Starostin-Dybo-Mudrak Altaic Etymological Dictionary head base. All
  # five branch columns are branch PROTOFORMS (the piet SLAV/BALT/GERM
  # verdict) — body-only, with the five branch links riding as crosslink
  # lines under their .inf aliases verbatim.
  def test_parse_altet_yields_the_tut_pro_shelf_with_branch_links
    document = parse("starling-altet")
    assert_equal "tut-pro", document.language
    entries = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 2 1728], entries.keys
    entry = entries["1"]
    assert_equal "èbà", entry.headword
    assert_equal "*èbà", entry.key_raw
    assert_equal "to join, meet", entry.gloss
    assert_includes entry.body, "Russian meaning: соединять(ся), встречать"
    assert_includes entry.body, "Turkic: *ab-", "branch protoform columns ride the body verbatim"
    assert_includes entry.body, "Tungus-Manchu: *ebu-re-"
    assert_includes entry.body, "Jpn.->Japet: #632", "the .inf link alias verbatim — japet #632 is IN this fixture set"
    assert_includes entry.body, "Turk.->Turcet: #2001", "links into the DEFERRED branch bases still ride as body lines"
    refute_includes entry.body, "Nostratic", "PRNUM=0 means no crosslink"
    assert_empty entry.reflexes, "every altet column is a branch protoform — body-only by verdict"
    assert_includes entries["2"].gloss, "{rage, anger}", "upstream's brace notation stays verbatim"
  end

  # THE junk-pointer pin (the parser's P104-3 first lane): altet #1728's
  # TURC slot holds literal whitespace bytes where a var pointer belongs —
  # the field reads honestly empty and the record parses whole.
  def test_altet_record_with_the_whitespace_junk_pointer_parses_whole
    entry = parse("starling-altet").entries.to_h { |e| [e.entry_id, e] }["1728"]
    assert_equal "pā̀ró ( ~ p`-, -ŕ-)", entry.headword
    assert_equal "to buy, sell", entry.gloss
    refute_includes entry.body, "Turkic:", "the junk TURC cell mints no body line"
    assert_includes entry.body, "Tungus-Manchu: *pār-", "the intact columns still ride"
    assert_includes entry.body, "Kor.->Koret: #189"
  end

  def test_parse_japet_yields_the_jpx_pro_shelf_with_the_altet_crosslink_both_ways
    document = parse("starling-japet")
    assert_equal "jpx-pro", document.language
    entries = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 2 632], entries.keys
    entry = entries["632"]
    assert_equal "àp-", entry.headword
    assert_equal "to meet, join, fit, agree", entry.gloss
    assert_includes entry.body, "Old Japanese: ap-"
    assert_includes entry.body, "Tokyo: á-", "the accent-bearing dialect columns are body-only"
    assert_includes entry.body, "Altaic etymology: #1",
                    "PRNUM crosslinks into the altet shelf (both ways: altet #1 JAPNUM=632)"
    assert_equal "together with", entries["1"].gloss
    assert_includes entries["1"].body, "Russian meaning: вместе с"
  end

  # The japet reflex verdict: AJP is the one single-language ATTESTED
  # column (Old Japanese, 8th c. — the ojp gold's code); MJP has no clean
  # code and the modern dialect columns (Tokyo/Kyoto/Kagoshima/Nase/Shuri/
  # Hateruma/Yonakuni) are accent-transcription variety columns — body-only.
  def test_japet_old_japanese_column_mints_the_ojp_reflex_row
    entries = parse("starling-japet").entries.to_h { |e| [e.entry_id, e] }
    assert_equal [%w[ojp muta], %w[ojp pap(j)i], %w[ojp ap-]],
                 entries.values.map { |e| e.reflexes.map { |r| [r.lang_code, r.word] }.flatten },
                 "one ojp row per record; lang_code = the RESOLVED catalog tag (P57-5)"
    assert_equal "Old Japanese", entries["1"].reflexes.first.lang_name
  end

  # --- the P104-3 packages: caucet (CAUC) --------------------------------------------

  # The Nikolayev-Starostin NCED head base. Six branch columns are branch
  # protoforms (body-only); LAK and KHIN are ACTUAL single-language forms
  # by the caucet.inf DBINFO's own words ("The actual Lak form (no
  # Proto-Lak reconstruction is presented)"; same for Khinalug) — they
  # mint, under the honest names Lak/Khinalug rather than the aliases'
  # "Proto-" labels.
  def test_parse_caucet_yields_the_ccn_pro_shelf_with_branch_links
    document = parse("starling-caucet")
    assert_equal "ccn-pro", document.language
    entries = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 2 9], entries.keys
    entry = entries["1"]
    assert_equal "ḳwĭrV", entry.headword
    assert_equal "leg bone, leg (of animal)", entry.gloss
    assert_includes entry.body, "Proto-Nakh: *ḳurV-m"
    assert_includes entry.body, "Notes: Reconstructed for the PEC level. Cf. also HU forms: Hurr. u-krə"
    assert_includes entry.body, "Sino-Caucasian etymology: #487", "PRNUM points into the unheld sccet base"
    assert_includes entry.body, "> Nakh: #332", "branch links ride under the .inf aliases verbatim"
    assert_includes entry.body, "> Lezghian: #3"
    assert_empty entry.reflexes, "NAKH/LEZG are branch protoforms — body-only"
  end

  def test_caucet_actual_form_columns_mint_lak_and_khinalug_rows
    entry = parse("starling-caucet").entries.to_h { |e| [e.entry_id, e] }["2"]
    assert_equal %w[lbe kjj], entry.reflexes.map(&:lang_code)
    assert_equal %w[ḳa zäḳ], entry.reflexes.map(&:word)
    assert_equal %w[Lak Khinalug], entry.reflexes.map(&:lang_name),
                 "the DBINFO's honest names — the aliases' 'Proto-Lak'/'Proto-Khinalug' labels " \
                 "name columns that hold ACTUAL forms (caucet.inf DBINFO)"
  end

  # caucet carries 223 headword-less records (the germet #401 shape, at
  # scale) — the mechanical placeholder keeps every slot.
  def test_caucet_headword_less_records_keep_their_slot_with_their_content
    entry = parse("starling-caucet").entries.to_h { |e| [e.entry_id, e] }["9"]
    assert_equal "#9", entry.headword
    assert_includes entry.body, "Proto-Lezghian: *ḳosʷɨ-", "the content-bearing columns still ride"
    assert_includes entry.body, "> Lezghian: #11"
  end

  # --- the P104-3 packages: stibet (SINTIB) ------------------------------------------

  # The Sino-Tibetan etymological head base (Peiros-Starostin 1996 with
  # improved reconstructions). Reflex verdict: LEPCHA is the one minting
  # column (single language, clean citation leads); TIB is scholarly
  # TRANSLITERATION (script-mismatched against this catalog's
  # Tibetan-script gold — the piet GREEK treatment), CHIN is Starostin's
  # OC reconstruction led by a Big5-encoded character (below), BURM/LUSH
  # mix in Proto-Lolo-Burmese / Proto-Kuki-Chin forms, KACH carries
  # tone-digit notation that is not a clean citation form, KIR is a
  # branch protoform — all body-only. The unaliased STLSNUM column (a
  # LEXSTAT-lane link; LEXSTAT tables are out of scope here) rides
  # nowhere.
  def test_parse_stibet_yields_the_sit_pro_shelf
    document = parse("starling-stibet")
    assert_equal "sit-pro", document.language
    entries = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[2 5 8 2785], entries.keys
    entry = entries["2"]
    assert_equal "bā(H) / *phā(H)", entry.headword
    assert_equal "spread, extend; wide, vast", entry.gloss
    assert_includes entry.body, "Kachin: šəpa1 to extend, as a cobra its hood"
    assert_includes entry.body, "Old Chinese etymology: #3051", "CHINNUM points into the DEFERRED bigchina base"
    assert_includes entry.body, "Kiranti etymology: #645"
    assert_includes entry.body, "Sino-Caucasian etymology: #112"
    refute_includes entry.body, "824", "the unaliased STLSNUM lexstat link rides nowhere"
    assert_empty entry.reflexes
    assert_includes entries["5"].body, "Tibetan: ãphar board (in compounds).",
                    "the transliterated TIB column is body-only"
    assert_equal [%w[lep kŭm-bŭ Lepcha]],
                 entries["8"].reflexes.map { |r| [r.lang_code, r.word, r.lang_name] },
                 "LEPCHA mints; the tone-digit KACH lead (nbo1) does not"
  end

  # The Big5 pin: bigchina/stibet Chinese character cells are Big5-encoded
  # (bigchina.inf: "characters in Big5 encoding") — outside the StarLing
  # text encoding, so the starling-dbf lane decodes each to the honest
  # replacement character. The OC transcription after it survives whole.
  def test_stibet_big5_character_leads_decode_to_honest_replacements
    entry = parse("starling-stibet").entries.to_h { |e| [e.entry_id, e] }["2"]
    assert_includes entry.body, "Chinese: � *phāʔ be vast, wide"
  end

  # THE truncated-var pin (the parser's P104-3 second lane): stibet #2785's
  # seven var pointers sit entirely past the shipped stibet.var — every
  # affected cell reads as the replacement character, the record keeps its
  # slot, and nothing mints from replacement text.
  def test_stibet_record_past_the_truncated_var_parses_as_replacements
    entry = parse("starling-stibet").entries.to_h { |e| [e.entry_id, e] }["2785"]
    assert_equal "�", entry.headword
    assert_includes entry.body, "Lepcha: �"
    assert_empty entry.reflexes, "a replacement character is not a citation form"
  end

  # --- the P104-3 packages: dravet (DRAV) --------------------------------------------

  # The Burrow-Emeneau-based Proto-Dravidian head base (G. Starostin's
  # revision). Five branch columns are branch protoforms; BRA is Brahui,
  # an actual language — the one minting column.
  def test_parse_dravet_yields_the_dra_pro_shelf_with_branch_links
    document = parse("starling-dravet")
    assert_equal "dra-pro", document.language
    entries = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 2 16], entries.keys
    entry = entries["1"]
    assert_equal "ac-", entry.headword
    assert_equal "stamp, mould", entry.gloss
    assert_includes entry.body, "Proto-South Dravidian: *ac-"
    assert_includes entry.body, "South Dravidian etymology: #42"
    assert_includes entry.body, "Telugu etymology: #39"
    assert_empty entry.reflexes
    entry16 = entries["16"]
    assert_equal([%w[brh aḍ Brahui]],
                 entry16.reflexes.map { |r| [r.lang_code, r.word, r.lang_name] })
    assert_includes entry16.body, "Brahui etymology: #1"
  end

  # dravet's numeric link cells can overflow to dBase's "****" sentinel
  # (censused: 4 cells in the live base, three of them on #1) — a
  # crosslink line needs a real number.
  def test_dravet_overflowed_link_cells_mint_no_crosslink_lines
    entry = parse("starling-dravet").entries.first
    refute_includes entry.body, "****"
    refute_includes entry.body, "Gondi-Kui etymology", "#1's GNDNUM is the **** sentinel"
  end

  # --- the P104-3 packages: kamet + chuket + itelet (CHUKCHEE) -----------------------

  # O. Mudrak's Chukchee-Kamchatkan family: kamet is the head (PRNUM →
  # the unheld Nostratic base), chuket and itelet are its subordinate
  # branch bases (their PRNUM points back INTO kamet). Glosses are
  # Russian — upstream says so itself ("no English translation is
  # available yet") — the vasmer precedent.
  def test_parse_kamet_yields_the_family_head_with_links_into_both_subordinates
    document = parse("starling-kamet")
    assert_equal "qfa-cka-pro", document.language
    entries = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 2 689 689-b], entries.keys
    entry = entries["1"]
    assert_equal "maĺ'mɨ", entry.headword
    assert_equal "грудка, брюшко, желудок", entry.gloss
    assert_includes entry.body, "Proto-Chukchee-Koryak: *macbɨ #"
    assert_includes entry.body, "Proto-Itelmen: *məzə-m"
    assert_includes entry.body, "Nostratic etymology: #114"
    assert_includes entry.body, "> Chukchee-Koryak: #804", "chuket #804 is IN this fixture set"
    assert_includes entry.body, "> Itelmen: #1", "itelet #1 is IN this fixture set"
    assert_empty entry.reflexes, "both branch columns are protoforms — body-only"
    refute_includes entries["2"].body, "Nostratic", "an empty PRNUM cell means no crosslink"
  end

  def test_kamet_duplicate_numbers_disambiguate_stably
    entries = parse("starling-kamet").entries.to_a
    assert_equal "'el", entries[2].headword, "file order rules: the negation record wears the NUMBER"
    assert_equal "hehe", entries[3].headword
    assert_includes entries[3].body, "note: upstream NUMBER collision"
  end

  def test_parse_chuket_yields_the_branch_shelf_with_the_kamet_crosslink_both_ways
    document = parse("starling-chuket")
    assert_equal "qfa-chk-pro", document.language
    entries = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 804], entries.keys
    entry = entries["804"]
    assert_equal "macbɨ #", entry.headword, "upstream's trailing marker stays verbatim"
    assert_includes entry.body, "Chukchee: máco (macvé-jpə abl.) 1, 2"
    assert_includes entry.body, "Chukchee-Kamchatkan etymology: #1",
                    "PRNUM crosslinks into kamet (both ways: kamet #1 CHUKNUM=804)"
    assert_includes entries["1"].body, "Muravyeva reference: 496",
                    "the .inf-aliased reference columns ride the body"
    assert_includes entries["1"].body, "Nivkh-Yukaghir etymology: #402"
    refute_includes entries["1"].body, "проталина",
                    "the unaliased CHFUNC/KOFUNC/ALFUNC/STPRO columns (outside the .inf " \
                    "field_list) ride nowhere"
  end

  # The chuket reflex verdict: CHU/KOR/ALU are actual single languages
  # (ckt/kpy/alr); PAL (Palana) is a Koryak variety with no code of its
  # own — body-only, declared.
  def test_chuket_single_language_columns_mint_ckt_kpy_alr_rows
    entry = parse("starling-chuket").entries.first
    assert_equal([%w[ckt ɛ́lɛ-ɛl], %w[kpy alá-al], %w[alr ala-al]],
                 entry.reflexes.map { |r| [r.lang_code, r.word] })
    assert_equal %w[Chukchee Koryak Alutor], entry.reflexes.map(&:lang_name)
    assert_includes entry.body, "Palana: ele-el", "PAL rides the body only"
  end

  def test_parse_itelet_yields_the_proto_itelmen_shelf_with_the_dybowski_columns
    document = parse("starling-itelet")
    assert_equal "itl-pro", document.language
    entries = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 2], entries.keys
    entry = entries["1"]
    assert_equal "məźə-m", entry.headword
    assert_includes entry.body, "Western Kamchadal: mɨzɨm 1, mizim kumisi-zin 2"
    assert_includes entry.body, "West Kamchadal meaning: stomachus 1"
    assert_includes entry.body, "Number in Dybowsky (WK): 135, 136"
    assert_includes entry.body, "Chukchee-Kamchatkan etymology: #1",
                    "PRNUM crosslinks into kamet (both ways: kamet #1 ITELNUM=1)"
    refute_includes entry.body, "MɨZɨ-M", "the unaliased ICOST/WCOST columns ride nowhere"
    assert_empty entry.reflexes, "no ITE cell on #1 — Dybowski's Kamchadal columns are body-only"
    assert_equal([["itl", "meč'a-", "Itelmen (Napana)"]],
                 entries["2"].reflexes.map { |r| [r.lang_code, r.word, r.lang_name] })
  end

  # --- the P104-3 packages: yenet (YENISEY) ------------------------------------------

  # Starostin 1995's comparative Yenisseian vocabulary: all five language
  # columns are actual single languages (Ket/Yug/Kott/Arin/Pumpokol) and
  # mint where the lead token is a clean citation form.
  def test_parse_yenet_yields_the_proto_yenisseian_shelf_with_minting_columns
    document = parse("starling-yenet")
    assert_equal "qfa-yen-pro", document.language
    entries = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[1 904 904-b], entries.keys
    entry = entries["1"]
    assert_equal "ʔaʔd (~x-)", entry.headword
    assert_equal "bone", entry.gloss
    assert_includes entry.body, "Ket: aʔt, pl. aŕeŋ5 (Bak., Sur. adeŋ5)"
    assert_includes entry.body, "Kottish: araŋan, *araŋ 'limb, joint'"
    assert_includes entry.body, "Sino-Caucasian etymology: #1", "PRNUM points into the unheld sccet base"
    assert_equal([%w[ket aʔt], %w[yug aʔt], %w[zko araŋan]],
                 entry.reflexes.map { |r| [r.lang_code, r.word] })
    assert_equal %w[Ket Yug Kottish], entry.reflexes.map(&:lang_name)
  end

  def test_yenet_duplicate_numbers_disambiguate_stably_and_gate_unclean_leads
    entries = parse("starling-yenet").entries.to_a
    assert_equal "ʔa", entries[1].headword, "file order rules"
    assert_equal "qo- (~ꭓ-,-ɔ-)", entries[2].headword
    assert_includes entries[2].body, "note: upstream NUMBER collision"
    assert_equal [%w[zko d́-äja-ŋ]],
                 entries[1].reflexes.map { |r| [r.lang_code, r.word] },
                 "the affix-hyphen KET/SYM leads (-a, -e-) are not citation forms"
    assert_empty entries[2].reflexes, "qɔ: carries the length colon — not a clean citation form"
  end

  # --- the reflex verdict (journaled in docs/backlog.md P22-0) ---------------------

  def test_single_language_attested_columns_mint_reflex_rows
    reflexes = parse("starling-piet").entries.to_h { |e| [e.entry_id, e] }["562"].reflexes
    assert_equal %w[san lat sq], reflexes.map(&:lang_code),
                 "lang_code = the RESOLVED catalog tag (P57-5: the piet field siglum — IND/LAT/ALB — " \
                 "used to leak through verbatim even though `language` already resolved it)"
    assert_equal reflexes.map(&:language), reflexes.map(&:lang_code)
    words = reflexes.to_h { |r| [r.lang_code, r] }
    assert_equal "kaṇṭhá-", words["san"].word, "the leading citation form only — the rest is prose"
    assert_equal Nabu::Normalize.search_form("kaṇṭha", language: "san"), words["san"].word_folded,
                 "member fold strips the trailing stem hyphen and lands on the gold-side §9 key"
    assert_equal "collus", words["lat"].word
    assert_equal "qafɛ", words["sq"].word
    assert_equal "Old Indian", words["san"].lang_name, "the .inf field alias feeds the language census"
    assert words.values.none?(&:borrowed), "piet marks no loans — false is the honest parse"
  end

  def test_proto_branch_and_mixed_columns_mint_no_rows_even_when_clean
    entries = parse("starling-piet").entries.to_h { |e| [e.entry_id, e] }
    assert_equal %w[san], entries["1501"].reflexes.map(&:lang_code),
                 "SLAV *sīgātī and GERM *xīg-ia- are Nikolayev-notation branch protoforms — body only"
    assert_includes entries["1501"].body, "Slavic: *sīgātī"
    assert_equal %w[ae], entries["1"].reflexes.map(&:lang_code),
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
    %w[starling-pokorny starling-piet starling-vasmer starling-germet starling-baltet
       starling-altet starling-japet starling-caucet starling-stibet starling-dravet
       starling-kamet starling-chuket starling-itelet starling-yenet starling-iranet
       starling-lexstat-balt starling-lexstat-germ].each do |slug|
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
  # P113-2: IE.exe's LEXSTAT/ subtree (inline-only tables, no .var siblings).
  LEXSTAT_FILES = %w[LEXSTAT/balt.dbf LEXSTAT/germ.dbf LEXSTAT/iranet.dbf].freeze
  PACKAGE_FILES = {
    "kart" => %w[kartet],
    "altaic" => %w[altet japet],
    "cauc" => %w[caucet],
    "sintib" => %w[stibet],
    "drav" => %w[dravet],
    "chukchee" => %w[kamet chuket itelet],
    "yenisey" => %w[yenet]
  }.freeze

  def zip_of(dir_files)
    Dir.mktmpdir do |dir|
      dir_files.each do |src, name|
        FileUtils.mkdir_p(File.dirname(File.join(dir, name)))
        FileUtils.cp(src, File.join(dir, name))
      end
      zip = File.join(dir, "package.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", zip, *dir_files.map(&:last)) }
      File.binread(zip)
    end
  end

  def zip_body
    @zip_body ||= zip_of((BASE_FILES + LEXSTAT_FILES).map { |name| [File.join(FIXTURES, name), name] })
  end

  def package_zip_body(subdir)
    @package_zip_bodies ||= {}
    @package_zip_bodies[subdir] ||= zip_of(
      PACKAGE_FILES.fetch(subdir).flat_map do |base|
        ["#{base}.dbf", "#{base}.var"].map { |name| [File.join(FIXTURES, subdir, name), name] }
      end
    )
  end

  def stub_packages
    stub_request(:get, ZIP_URL).to_return(status: 200, body: zip_body)
    PACKAGE_URLS.each do |subdir, url|
      stub_request(:get, url).to_return(status: 200, body: package_zip_body(subdir))
    end
  end

  def test_fetch_unpacks_all_eight_packages_and_discovers_every_shelf
    stub_packages
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      refs = adapter.discover(workdir).to_a
      assert_equal ALL_BASE_IDS, refs.map(&:id)
      assert File.file?(File.join(workdir, "kart", "kartet.dbf")),
             "each follow-up package lands in its own subdir with its own fetch state"
      assert File.file?(File.join(workdir, "altaic", "altet.dbf"))
      assert File.file?(File.join(workdir, "yenisey", "yenet.dbf"))
      assert File.file?(File.join(workdir, "LEXSTAT", "balt.dbf")),
             "IE.exe's LEXSTAT/ subtree lands with the root package"
      assert_equal 3, adapter.parse(refs.first).size
    end
  end

  # Every follow-up subdir must survive a LATER IE.exe re-fetch: the root
  # ZipFetch's retention sweep would otherwise read the sibling packages as
  # upstream deletions and attic them (the P46-6 keep: contract, now over
  # all seven subdirs).
  def test_refetching_the_ie_package_never_attics_the_follow_up_subdirs
    stub_packages
    Dir.mktmpdir do |workdir|
      adapter.fetch(workdir)
      adapter.fetch(workdir)
      PACKAGE_FILES.each do |subdir, bases|
        assert File.file?(File.join(workdir, subdir, "#{bases.first}.dbf")),
               "#{subdir} survives the IE re-fetch sweep"
        refute Dir.exist?(File.join(workdir, ".attic", subdir)), "nothing #{subdir}-shaped was atticked"
      end
      assert_equal 18, adapter.discover(workdir).to_a.size
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end

  def test_probe_heads_all_eight_package_zips
    assert_equal :http_zip, Nabu::Adapters::Starling.remote_probe_strategy
    targets = Nabu::Adapters::Starling.http_probe_targets
    assert_equal [ZIP_URL, *PACKAGE_URLS.values], targets.map(&:zip_url)
    assert_equal ["", *PACKAGE_URLS.keys], targets.map(&:state_subdir),
                 "each follow-up package keeps its own .zip-fetch.json under its subdir"
    assert targets.all? { |t| t.metadata_url.nil? },
           "the grant lives in e-mail + descrip.php, not a probe endpoint"
    assert_equal [Nabu::ZipFetch::STATE_FILE] * 8, targets.map(&:state_file)
  end

  # --- DictionaryLoader contract -----------------------------------------------------

  def loader_setup(canonical_dir: nil)
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "starling", name: "StarLing IE", adapter_class: "Nabu::Adapters::Starling",
      license: Nabu::Adapters::Starling::MANIFEST.license, license_class: "attribution",
      upstream_url: ZIP_URL, enabled: false
    )
    [db,
     Nabu::Store::DictionaryLoader.new(db: db, source: source,
                                       language_shelf_dir: canonical_dir && File.join(canonical_dir, Nabu::LanguageShelf::SLUG))]
  end

  def test_loading_twice_is_idempotent_with_stable_urns_reflex_rows_and_name_census
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 119, first.added,
                 "3 records per IE base + 5 kart + 27 across the P104-3 bases (3 altet + 3 japet + " \
                 "3 caucet + 4 stibet + 3 dravet + 4 kamet + 2 chuket + 2 itelet + 3 yenet), " \
                 "both halves of each fixture NUMBER collision and every placeholder pin included; " \
                 "P113-2: + 3 iranet + 16 lexstat-balt + 49 lexstat-germ form cells"
    assert_equal 0, first.errored
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 119, second.skipped
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
    assert_equal "urn:nabu:dict:starling-pokorny:1089",
                 db[:dictionary_entries].where(entry_id: "1089").get(:urn)
    assert_equal "urn:nabu:dict:starling-vasmer:12561",
                 db[:dictionary_entries].where(entry_id: "12561").get(:urn),
                 "piet #1501's `Vasmer: #12561` body line now names a live entry id"
    assert_equal ["urn:nabu:dict:starling-baltet:76-b", "urn:nabu:dict:starling-kamet:689-b",
                  "urn:nabu:dict:starling-kart:48-b", "urn:nabu:dict:starling-lexstat-balt:26.lit-b",
                  "urn:nabu:dict:starling-lexstat-germ:58.aeg-b", "urn:nabu:dict:starling-lexstat-germ:58.hol-b",
                  "urn:nabu:dict:starling-piet:574-b", "urn:nabu:dict:starling-yenet:904-b"],
                 db[:dictionary_entries].where(Sequel.like(:entry_id, "%-b")).select_order_map(:urn),
                 "the duplicate-NUMBER disambiguation (and the LEXSTAT synonym slots) are urn-stable"
    assert_equal 72, db[:dictionary_reflexes].count,
                 "the LEXSTAT shelves mint none; piet 5 + germet 24 (10+14+0, stop-gated) + baltet 7 (3+2+2) + " \
                 "kart 18 (4+3+4+3+4) " \
                 "+ japet 3 + caucet 2 + stibet 1 + dravet 1 + chuket 6 + itelet 1 + yenet 4"
    assert_equal ["Albanian", "Alutor", "Avestan", "Brahui", "Chukchee", "Danish", "Dutch",
                  "English", "Georgian", "German", "Gothic", "Itelmen (Napana)", "Ket",
                  "Khinalug", "Koryak", "Kottish", "Lak", "Latin", "Laz", "Lepcha", "Lettish",
                  "Lithuanian", "Megrel", "Middle Dutch", "Middle High German",
                  "Middle Low German", "Norwegian", "Old English", "Old Frisian",
                  "Old High German", "Old Indian", "Old Japanese", "Old Norse", "Old Prussian",
                  "Old Saxon", "Svan", "Swedish", "Yug"],
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
      shelf = Nabu::LanguageShelf.new(dir: File.join(root, Nabu::LanguageShelf::SLUG))
      section = shelf.load("ine-pro").section("witness:starling")
      assert_equal "starling", section.source
      assert_match(/Pokorny/, section.body)
      assert_match(/Nikolayev/, section.body)
      # P23-0: one honest witness note per follow-up base's language
      assert_match(/Vasmer/, shelf.load("rus").section("witness:starling").body)
      assert_match(/Common Germanic/, shelf.load("gem-pro").section("witness:starling").body)
      assert_match(/Proto-Baltic/, shelf.load("bat-pro").section("witness:starling").body)
      assert_match(/Klimov/, shelf.load("ccs-pro").section("witness:starling").body)
      # P104-3: one honest witness note per new shelf language
      assert_match(/Altaic Etymological Dictionary/, shelf.load("tut-pro").section("witness:starling").body)
      assert_match(/Starostin 1975/, shelf.load("jpx-pro").section("witness:starling").body)
      assert_match(/North Caucasian Etymological Dictionary/,
                   shelf.load("ccn-pro").section("witness:starling").body)
      assert_match(/Peiros/, shelf.load("sit-pro").section("witness:starling").body)
      assert_match(/Burrow/, shelf.load("dra-pro").section("witness:starling").body)
      assert_match(/Mudrak/, shelf.load("qfa-cka-pro").section("witness:starling").body)
      assert_match(/Chukchee-Koryak/, shelf.load("qfa-chk-pro").section("witness:starling").body)
      assert_match(/Itelmen/, shelf.load("itl-pro").section("witness:starling").body)
      assert_match(/Starostin 1995/, shelf.load("qfa-yen-pro").section("witness:starling").body)
      # P113-2: the three LEXSTAT Indo-Iranian etymology tables
      assert_match(/Indo-Aryan/, shelf.load("inc-pro").section("witness:starling").body)
      assert_match(/Iranian/, shelf.load("ira-pro").section("witness:starling").body)
      assert_match(/Dardic/, shelf.load("inc-dar-pro").section("witness:starling").body)
      codes = %w[ine-pro rus gem-pro bat-pro ccs-pro tut-pro jpx-pro ccn-pro sit-pro dra-pro
                 qfa-cka-pro qfa-chk-pro itl-pro qfa-yen-pro inc-pro ira-pro inc-dar-pro]
      before = codes.map { |code| File.read(shelf.path_for(code)) }
      loader.load_from(adapter, workdir: FIXTURES)
      assert_equal before, codes.map { |code| File.read(shelf.path_for(code)) },
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

  # P104-3 acceptance: an altet root serves with the grant + the AED
  # compiler credit on its license lane, and a Ket reflex walks to the
  # yenet proto-form.
  def test_define_an_altaic_root_serves_the_aed_credit_line
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    # lects: nil pins the "-pro" string-test scope: this is an ADAPTER
    # acceptance test, and the registry-governed resolution would make
    # it depend on which nabu-lects release the box carries (tut-pro
    # rides the in-flight comparative-etymology mint).
    results = Nabu::Query::Define.new(catalog: db, lects: nil).run("*èbà")
    assert_equal ["starling-altet"], results.map(&:dictionary_slug)
    result = results.first
    assert_match(/properly acknowledged/, result.license, "the grant rides the result")
    assert_match(/S\. Starostin, A\. Dybo and O\. Mudrak/, result.license,
                 "the AED compiler credit rides the result")
    assert_includes result.body, "Tungus-Manchu:"
  end

  def test_etym_walks_a_ket_reflex_to_the_yenet_proto_form
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Etym.new(catalog: db).run("aʔt")
    assert_equal ["starling-yenet"], results.map(&:dictionary_slug).uniq
    assert(results.map(&:headword).any? { |headword| headword.include?("ʔaʔd") })
  end

  # P113-2 acceptance: a LEXSTAT form serves from its wordlist shelf with
  # the grant on the license lane and its cognation line naming the baltet
  # entry id (#1634 *kakla- is in this fixture set).
  def test_define_a_lexstat_form_serves_the_wordlist_entry_with_the_grant
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Define.new(catalog: db, lects: nil).run("kakls")
    assert_equal ["starling-lexstat-balt"], results.map(&:dictionary_slug)
    result = results.first
    assert_equal "urn:nabu:dict:starling-lexstat-balt:58.let", result.urn
    assert_equal "neck", result.gloss
    assert_match(/properly acknowledged/, result.license, "the grant rides the result")
    assert_includes result.body, "Baltic etymology: #1634"
  end

  # --- registry -----------------------------------------------------------------------

  def test_registry_row_is_live_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["starling"]
    refute_nil entry, "config/sources.yml must register starling"
    assert_equal Nabu::Adapters::Starling, entry.adapter_class
    assert entry.wired, "live (owner sign-off 2026-07-16: synced incl. piet 574-b, eyeballed, flipped)"
    assert_equal "manual", entry.sync_policy
  end
end
