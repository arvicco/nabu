# frozen_string_literal: true

require "test_helper"

# The StarLing branch-bases wave: the 28 subordinate etymological bases of the
# ALTAIC / CAUC / DRAV / SINTIB packages (held since P104-3, declared deferred
# there; G. Starostin's 2026-10-01 extension grant covers them under the
# 2026-07-15 conditions — per-base attribution on every serving surface).
# Pure BASES configuration (StarlingBranchBases), so the starling parse path
# reads them unchanged; this file pins the census, the per-base credits, the
# shelf-language and reflex verdicts, and the head⇄branch crosslinks both
# ways on trimmed REAL samples of one base per package plus a Leiden
# dictionary (test/fixtures/starling/, README "The branch-bases wave"):
# turcet (ALTAIC), lezget (CAUC), sdret + ktet (DRAV), kiret + limet (SINTIB).
class StarlingBranchBasesTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("starling")

  def adapter = Nabu::Adapters::Starling.new

  def parse(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.metadata.fetch("dictionary") == slug }
    refute_nil ref, "#{slug} must be discovered from the fixture tree"
    adapter.parse(ref)
  end

  def entries(slug) = parse(slug).entries.to_h { |e| [e.entry_id, e] }

  def reflex_rows(entry) = entry.reflexes.map { |r| [r.lang_code, r.word] }

  # --- the census -------------------------------------------------------------------

  # census: 28, 2026-10-07, branch .dbf bases in canonical/starling/{altaic,cauc,drav,
  # sintib}/ beyond the P104-3 head bases — every one except the excluded
  # bigchina (Big5 lane) and doc (support table). Upstream live records per
  # base, read from the .dbf headers and dry-parsed at full scale through
  # this adapter (zero quarantines): 42,247 entries in all.
  UPSTREAM_RECORDS = {
    "starling-turcet" => 2017, "starling-monget" => 2174, "starling-tunget" => 2435,
    "starling-koret" => 1206, "starling-nakhet" => 970, "starling-aandet" => 1539,
    "starling-cezet" => 1108, "starling-laket" => 955, "starling-darget" => 924,
    "starling-lezget" => 1569, "starling-khinet" => 349, "starling-abadet" => 817,
    "starling-sdret" => 4692, "starling-telet" => 2774, "starling-kogaet" => 1509,
    "starling-gndet" => 1428, "starling-gonet" => 1475, "starling-kuiet" => 1377,
    "starling-konet" => 961, "starling-ktet" => 1665, "starling-ndret" => 989,
    "starling-pemet" => 740, "starling-braet" => 269, "starling-kiret" => 994,
    "starling-dumet" => 1517, "starling-kulet" => 1466, "starling-limet" => 2354,
    "starling-yamet" => 1974
  }.freeze

  def test_the_branch_base_census_is_pinned_and_every_base_rides_the_adapter
    branch = Nabu::Adapters::StarlingBranchBases::BASES
    assert_equal UPSTREAM_RECORDS.keys, branch.keys, "registry order = package order, head-link order within"
    assert_equal 42_247, UPSTREAM_RECORDS.values.sum
    branch.each do |slug, base|
      assert_same base, Nabu::Adapters::Starling::BASES.fetch(slug), "#{slug} rides Starling::BASES"
      assert_equal %i[dbf language title headword gloss body crosslinks reflexes], base.keys,
                   "#{slug} is an ordinary BASES row"
      assert_includes base.fetch(:crosslinks).keys, "PRNUM", "#{slug} links up to its head base"
    end
    assert_equal Nabu::Adapters::Starling::BASES.keys.last(31).first(28), branch.keys,
                 "the wave rides after the P104-3 heads and before the IE LEXSTAT etymology tables"
  end

  # Shelf languages: the branch proto code where the base is PROTO-shaped,
  # the language's own code where the headword IS a single attested
  # language. Coined Dravidian sub-branch codes are declared in the module.
  def test_shelf_languages_are_the_declared_branch_or_language_codes
    languages = Nabu::Adapters::StarlingBranchBases::BASES.transform_values { |base| base.fetch(:language) }
    assert_equal({
                   "starling-turcet" => "trk-pro", "starling-monget" => "xgn-pro",
                   "starling-tunget" => "tuw-pro", "starling-koret" => "qfa-kor-pro",
                   "starling-nakhet" => "cau-nkh-pro", "starling-aandet" => "cau-ava-pro",
                   "starling-cezet" => "cau-tsz-pro", "starling-laket" => "lbe",
                   "starling-darget" => "cau-drg-pro", "starling-lezget" => "cau-lzg-pro",
                   "starling-khinet" => "kjj", "starling-abadet" => "cau-nwc-pro",
                   "starling-sdret" => "dra-sou-pro", "starling-telet" => "dra-tel-pro",
                   "starling-kogaet" => "dra-cen-pro", "starling-gndet" => "dra-gki-pro",
                   "starling-gonet" => "dra-gon-pro", "starling-kuiet" => "dra-kui-pro",
                   "starling-konet" => "kfc", "starling-ktet" => "dra-tkt-pro",
                   "starling-ndret" => "dra-nor-pro", "starling-pemet" => "dra-pem-pro",
                   "starling-braet" => "brh", "starling-kiret" => "sit-kir-pro",
                   "starling-dumet" => "dus", "starling-kulet" => "kle", "starling-limet" => "lif",
                   "starling-yamet" => "ybi"
                 }, languages)
  end

  # The reflex verdict: single attested languages with an unambiguous code
  # mint; branch protoforms, mixed-source and code-less variety columns, and
  # single-language shelves' own form columns ride the body only.
  def test_the_reflex_verdict_per_base
    minting = Nabu::Adapters::StarlingBranchBases::BASES.transform_values { |base| base.fetch(:reflexes).keys }
    assert_equal 27, minting["starling-turcet"].size, "27 of turcet's 29 language columns mint"
    refute_includes minting["starling-turcet"], "ATU", "Old Turkic mixes Orkhon and Old Uyghur sources"
    refute_includes minting["starling-turcet"], "CHG", "Middle Turkic mixes Chagatai and Kypchak sources"
    refute_includes minting["starling-monget"], "MOGH", "71.5% clean: the ZM label leads"
    refute_includes minting["starling-sdret"], "KT", "Proto-Nilgiri is a branch protoform"
    assert_equal %w[KON], minting["starling-gndet"], "only Konda is an attested form in the Gondwan base"
    %w[starling-laket starling-khinet starling-konet starling-braet starling-gonet
       starling-dumet starling-kulet starling-limet starling-yamet].each do |slug|
      assert_empty minting[slug], "#{slug} mints nothing"
    end
    assert_equal 107, minting.values.sum(&:size), "minting columns across the wave"
  end

  # The grant's express condition: name the compilers of EACH database —
  # their own DBINFO words, on the license lane every surface renders.
  def test_manifest_carries_every_branch_base_credit
    license = adapter.manifest.license
    assert_includes license, Nabu::Adapters::StarlingBranchBases::CREDITS
    assert_match(/the Turkic part of the Altaic Etymological Dictionary/, license)
    assert_match(/Comparative Dictionary of Tungus-Manchu Languages compiled by Tsintsius et al\./, license)
    assert_match(/koret\.inf carries no DBINFO/, license, "the Korean base's credit is the package's, declared")
    assert_match(/in S\. Nikolayev's reconstruction/, license)
    assert_match(/The Lezghian part.*in S\. Starostin's reconstruction/, license)
    assert_match(/subordinate to the Common Dravidian database/, license)
    assert_match(/Allen, Hale, Toba, Van Driem and Tolsma/, license)
    assert_match(/The Dumi dictionary provided by G\. Van Driem, published in Van Driem 1993/, license)
    assert_match(/The Kulung dictionary provided by G\. Tolsma, published in Tolsma 1999/, license)
    assert_match(/The Limbu dictionary provided by G\. Van Driem, published in Van Driem 1987/, license)
    assert_match(/The Yamphu dictionary provided by R\. Rutgers, published in Rutgers 2000/, license)
  end

  # --- turcet (ALTAIC) ------------------------------------------------------------------

  def test_parse_turcet_yields_the_trk_pro_shelf_with_the_altet_crosslink_both_ways
    document = parse("starling-turcet")
    assert_equal "trk-pro", document.language
    by_id = entries("starling-turcet")
    assert_equal %w[2 1931 1931-b 2001], by_id.keys
    entry = by_id["2001"]
    assert_equal "ab-", entry.headword
    assert_equal "*ab-", entry.key_raw
    assert_equal "to crowd, come together", entry.gloss
    assert_includes entry.body, "Russian meaning: собираться, встречаться"
    assert_includes entry.body, "Altaic etymology: #1",
                    "PRNUM crosslinks into altet (both ways: altet #1 TURCNUM=2001, IN this fixture set)"
    assert_includes entry.body, "Old Turkic: av- (OUygh.)", "the mixed-source column rides the body"
    assert_equal [%w[xqa av-]], reflex_rows(entry), "only Karakhanid mints; Old Turkic is body-only"
  end

  def test_turcet_language_columns_mint_reflex_rows_under_the_inf_aliases
    entry = entries("starling-turcet")["2"]
    assert_equal "kül", entry.headword
    assert_equal "ashes", entry.gloss
    rows = reflex_rows(entry)
    assert_equal 27, rows.size, "every minting column is filled on #2 *kül"
    assert_equal %w[xqa kül], rows.first
    assert_includes rows, %w[cv kəʷl]
    assert_includes rows, %w[tyv xül]
    assert_includes rows, %w[sah kül]
    refute(rows.any? { |code, _| %w[otk chg].include?(code) }, "ATU/CHG never mint")
    assert_equal "Azerbaidzhan", entry.reflexes.find { |r| r.lang_code == "az" }.lang_name,
                 "the .inf alias feeds the language census verbatim"
    assert_includes entry.body, "Middle Turkic: kül"
  end

  def test_turcet_duplicate_numbers_disambiguate_stably
    list = parse("starling-turcet").entries.to_a
    assert_equal "bẹŕ-", list[1].headword, "file order rules: the first 1931 keeps the plain id"
    assert_equal "jabĺan", list[2].headword
    assert_equal "1931-b", list[2].entry_id
    assert_includes list[2].body, "note: upstream NUMBER collision"
    assert_equal [%w[xqa japčan], %w[tk jovšan], %w[tyv čašpan]], reflex_rows(list[2])
  end

  # THE frame-breaking pointer pins (the live parse-only sync quarantined
  # tunget #42 on the NULs its Solon cell leaked into the INSERT): the
  # damaged cells read as U+FFFD and mint nothing; the record lands whole.
  def test_tunget_records_with_damaged_var_pointers_land_whole
    by_id = entries("starling-tunget")
    assert_equal %w[42 1821], by_id.keys
    fish = by_id["42"]
    assert_equal "xol-sa", fish.headword
    assert_includes fish.body, "Solon: �", "the damaged Solon cell renders as the replacement character"
    refute_match(/[\x00\x12]/, fish.body)
    assert_includes fish.body, "Comments: ТМС 2, 14."
    assert_equal %w[evn eve neg ulc oaa gld oac ude], fish.reflexes.map(&:lang_code)
    eagle = by_id["1821"]
    assert_includes eagle.body, "Literary Manchu: �"
    refute_match(/[\x00\x12]/, eagle.body)
    assert_equal [%w[evn kīran], %w[ude käi]], reflex_rows(eagle),
                 "the damaged Manchu cell (a misdirected copy of the Udihe form) mints no mnc row"
  end

  def test_monget_overrun_payload_ends_at_its_frame
    entry = entries("starling-monget")["2161"]
    assert_equal "čubali", entry.headword
    assert_includes entry.body, "Middle Mongolian: čubali (MA 136)"
    assert_equal [%w[xng čubali]], reflex_rows(entry)
  end

  # --- lezget (CAUC) --------------------------------------------------------------------

  def test_parse_lezget_yields_the_lezgic_shelf_with_the_caucet_crosslinks_both_ways
    document = parse("starling-lezget")
    assert_equal "cau-lzg-pro", document.language
    by_id = entries("starling-lezget")
    assert_equal %w[1 3 11], by_id.keys
    entry = by_id["3"]
    assert_equal "ḳʷir(a)", entry.headword
    assert_equal "1 hoof 2 leg (of animal)", entry.gloss
    assert_includes entry.body, "Archi: ḳʷiri 2"
    assert_includes entry.body, "North Caucasian etymology: #1",
                    "caucet #1 carries LEZGNUM=3 — both ways inside this fixture set"
    assert_includes entry.body, "Comments: 3d class in Arch. and Kryz.",
                    "the alias-less COMMENT column rides under the DBINFO's own item name"
    assert_includes by_id["11"].body, "North Caucasian etymology: #9",
                    "caucet #9 (the headword-less placeholder) carries LEZGNUM=11"
  end

  def test_lezget_language_columns_mint_and_the_tense_mark_gates_a_lead
    by_id = entries("starling-lezget")
    assert_equal [%w[lez zun], %w[tab uzu], %w[agx zun], %w[rut zɨ], %w[tkr zu], %w[kry zɨn],
                  %w[bdk zɨn], %w[aqc zon], %w[udi zu]], reflex_rows(by_id["1"])
    assert_equal [%w[lez ḳasun], %w[kry ḳɨsäǯ], %w[bdk ḳusu]], reflex_rows(by_id["11"]),
                 "the Udi lead k:aIšpsun carries the ':' tense mark — not a citation form, body only"
    assert_includes by_id["11"].body, "Udi: k:aIšpsun"
  end

  # --- sdret (DRAV) ---------------------------------------------------------------------

  def test_parse_sdret_yields_the_south_dravidian_shelf_with_the_dravet_crosslink_both_ways
    document = parse("starling-sdret")
    assert_equal "dra-sou-pro", document.language
    by_id = entries("starling-sdret")
    assert_equal %w[2 42 384], by_id.keys
    entry = by_id["42"]
    assert_equal "ac-", entry.headword
    assert_equal "mould, type", entry.gloss
    assert_includes entry.body, "Kodagu meaning: cake of jaggery sugar with hollow in middle (formed in a mould)"
    assert_includes entry.body, "Proto-Nilgiri: *as (*-c)", "the KT protoform rides the body"
    assert_includes entry.body, "Number in DED: 0047", "the inline DED number cell verbatim"
    assert_includes entry.body, "Dravidian etymology: #1",
                    "dravet #1 carries SDRNUM=42 — both ways inside this fixture set"
    assert_includes entry.body, "Nilgiri etymology: #1157", "KTNUM links into the ktet base"
    refute_match(/^F$|CHECKED|: F$/, entry.body, "the logical CHECKED flag rides nowhere")
    assert_equal [%w[ta accu], %w[ml accu], %w[kn accu], %w[kfa acci], %w[tcy acci]], reflex_rows(entry)
    refute_includes entries("starling-sdret")["2"].body, "Nilgiri etymology", "KTNUM 0 means no crosslink"
  end

  # sdret carries 807 headword-less records upstream (no protoform yet) —
  # the mechanical "#NUMBER" placeholder keeps each slot and its material.
  def test_sdret_headword_less_records_keep_their_slot_and_still_mint
    entry = entries("starling-sdret")["384"]
    assert_equal "#384", entry.headword
    assert_nil entry.gloss
    assert_includes entry.body, "Tamil meaning: mistletoe berry thorn, Azima tetracantha"
    refute_includes entry.body, "Dravidian etymology", "PRNUM 0 means no crosslink"
    assert_equal [%w[ta icaŋku], %w[ml iyaŋku], %w[kn egaci]], reflex_rows(entry)
  end

  # ktet (the Nilgiri base, subordinate to sdret): #1157 is sdret #42's
  # KTNUM target — both ways inside the fixture set — and #766 is THE
  # bare-"?" protoform (upstream: no reconstruction offered), whose fold is
  # empty: the entry keeps "?" verbatim and folds under its NUMBER (the
  # regression pin for the ASCII-8BIT numeric-cell defect).
  def test_parse_ktet_yields_the_nilgiri_shelf_linked_both_ways_with_sdret
    by_id = entries("starling-ktet")
    assert_equal %w[766 1157], by_id.keys
    entry = by_id["1157"]
    assert_equal "as (*-c)", entry.headword
    assert_includes entry.body, "South Dravidian etymology: #42", "sdret #42 carries KTNUM=1157"
    assert_equal [%w[kfe ac]], reflex_rows(entry)
    doubt = by_id["766"]
    assert_equal "?", doubt.headword
    assert_equal "766", doubt.headword_folded, "an empty fold falls back to the NUMBER"
    assert_equal Encoding::UTF_8, doubt.headword_folded.encoding
    assert_equal [%w[kfe tugūṛ-], %w[tcx tǖs̱]], reflex_rows(doubt)
  end

  # --- kiret + limet (SINTIB) ------------------------------------------------------------

  def test_parse_kiret_yields_the_kiranti_shelf_linked_both_ways
    document = parse("starling-kiret")
    assert_equal "sit-kir-pro", document.language
    by_id = entries("starling-kiret")
    assert_equal %w[2 645], by_id.keys
    entry = by_id["645"]
    assert_equal "bhä́[p]", entry.headword
    assert_includes entry.body, "Sino-Tibetan etymology: #2",
                    "stibet #2 carries KIRNUM=645 — both ways inside this fixture set"
    assert_includes entry.body, "->Kulet: #19", "the sub-base link aliases verbatim"
    assert_includes entry.body, "Kaling: 'bhäppä"
    assert_equal [%w[tdh bhapa], %w[kle baipa], %w[ybi beʔe]], reflex_rows(entry),
                 "the stress-led Kaling lead gates; the rest mint"
    two = by_id["2"]
    assert_includes two.body, "->Limet: #460"
    refute_includes two.body, "Sino-Tibetan etymology", "PRNUM 0 means no crosslink"
    assert_equal [%w[klr unä], %w[lif iŋmā], %w[ybi imma]], reflex_rows(two)
  end

  # The Leiden dictionaries are single-language shelves (headword = the
  # attested word), linked up into kiret.
  def test_parse_limet_yields_the_limbu_dictionary_shelf
    document = parse("starling-limet")
    assert_equal "lif", document.language
    by_id = entries("starling-limet")
    assert_equal %w[1 460], by_id.keys
    entry = by_id["460"]
    assert_equal "iNmaʔ, -iN-", entry.headword
    assert_equal "buy, purchase.", entry.gloss
    assert_includes entry.body, "Grammar: vt."
    assert_includes entry.body, "Kiranti etymology: #2", "kiret #2 carries LIMNUM=460 — both ways"
    assert_empty entry.reflexes
    assert_equal "Grammar: pf.", by_id["1"].body
  end

  # --- acceptance renders (define / etym through the loader) ---------------------------

  def loaded_catalog
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "starling", name: "StarLing", adapter_class: "Nabu::Adapters::Starling",
      license: Nabu::Adapters::Starling::MANIFEST.license, license_class: "attribution",
      upstream_url: Nabu::Adapters::Starling::MANIFEST.upstream_url, enabled: false
    )
    Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    db
  end

  def test_define_a_turkic_root_serves_the_turcet_credit_line
    results = Nabu::Query::Define.new(catalog: loaded_catalog, lects: nil).run("*kül")
    assert_equal ["starling-turcet"], results.map(&:dictionary_slug)
    assert_match(/properly acknowledged/, results.first.license, "the grant rides the result")
    assert_match(/the Turkic part of the Altaic Etymological Dictionary/, results.first.license,
                 "the turcet DBINFO credit rides the result")
  end

  def test_etym_walks_a_lezgian_reflex_to_the_lezget_proto_form
    results = Nabu::Query::Etym.new(catalog: loaded_catalog).run("zun")
    assert_equal ["starling-lezget"], results.map(&:dictionary_slug).uniq
    assert(results.map(&:headword).any? { |headword| headword.include?("zo-n") })
  end

  # --- stability, NFC, and the language-notes rider -----------------------------------

  def test_entry_ids_are_unique_stable_and_output_is_nfc
    %w[starling-turcet starling-monget starling-tunget starling-lezget starling-sdret starling-ktet
       starling-kiret starling-limet].each do |slug|
      first = parse(slug).map(&:entry_id)
      assert_equal first.uniq, first
      assert_equal first, parse(slug).map(&:entry_id)
      parse(slug).each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
      end
    end
  end

  def test_every_new_shelf_language_carries_one_witness_note
    notes = Nabu::Adapters::Starling.language_notes.to_h { |code, kind, body| [[code, kind], body] }
    Nabu::Adapters::StarlingBranchBases::BASES.each_value do |base|
      body = notes[[base.fetch(:language), "witness:starling"]]
      refute_nil body, "#{base.fetch(:language)} needs a witness:starling note"
    end
    assert_equal Nabu::Adapters::Starling.language_notes.size,
                 Nabu::Adapters::Starling.language_notes.map { |code, kind, _| [code, kind] }.uniq.size,
                 "one note per (code, kind)"
  end
end
