# frozen_string_literal: true

require "test_helper"

# The follow-up packages' LEXSTAT/ wordlists (P118): 48 lexicostatistical
# tables inside ALTAIC / CAUC / YENISEY / SINTIB / DRAV / CHUKCHEE / KART.exe,
# the IE.exe wordlist shape (one entry per form cell, file position 0 the
# date row) read through PER-PACKAGE language maps — the same siglum names
# different languages across packages (MAN, KAN, CHE, KON, KOT, PUM, TAM,
# HAK, UBA …). Three waves:
#
# - A (altaic/cauc/yenisey, 15 tables): every alias in-package; a branch
#   table's own .inf wins over the union alt.inf where they disagree.
# - B (sintib, 30 tables): RESOLVE-OR-VERBATIM — a positive cognation
#   number links ("<label>: #N") only when the target base holds that
#   NUMBER; otherwise it rides verbatim ("Cognation number: N").
# - C (drav/kam/kart): the ruled standard readings of unaliased columns,
#   each declared "inferred, not documented upstream" (shelf title + entry);
#   kam's decimal date row; kart's proto = NONE (every number verbatim).
#
# Fixtures (test/fixtures/starling/<package>/LEXSTAT/, README "The
# follow-up packages' LEXSTAT wordlists"): trimmed REAL tables — the date
# row + 1–3 item rows each; yen.dbf is var-backed (a compacted yen.var).
# Resolution runs against the trimmed fixture BASES beside them, so a
# number that resolves live but whose target record was not kept in the
# fixture base reads verbatim here — the assertions say which is which.
class StarlingLexstatPackagesTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("starling")
  PACKAGES = Nabu::Adapters::StarlingLexstatPackages
  INFERRED = "inferred, not documented upstream"

  def adapter = Nabu::Adapters::Starling.new

  def parse(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.metadata.fetch("dictionary") == slug }
    refute_nil ref, "#{slug} must be discovered from the fixture tree"
    adapter.parse(ref)
  end

  def entries(slug) = parse(slug).entries.to_h { |e| [e.entry_id, e] }

  def language_line(entry) = entry.body[/^Language: (.*)$/, 1]

  # --- the census -------------------------------------------------------------------

  # census: 48, 2026-10-11, the follow-up packages' LEXSTAT/*.dbf minus the
  # three held tables (51 in all); 33,379 form entries dry-parsed at full
  # scale (altaic 11,512 / cauc 3,727 / yenisey 475 / sintib 13,586 / drav
  # 2,328 / chukchee 1,162 / kart 589), zero quarantines.
  WAVE_A = %w[alt jap kor mong tung turc aand abad cez darg khin lak lezg nakh yen].freeze
  WAVE_B = %w[aka bodo bur che chin dhim gur idu jar jnp kan kar kay kha kir knyk lep mag man
              miju mik mot naga nung sul syc tani tib trun tuja].freeze
  WAVE_C = %w[drav kam kart].freeze

  def test_the_three_waves_are_pinned_and_the_held_tables_stay_out
    slugs = PACKAGES::TABLES.keys
    assert_equal (WAVE_A + WAVE_B + WAVE_C).map { |stem| "starling-lexstat-#{stem}" }, slugs
    assert_equal 48, slugs.size
    %w[sino stls sinocalc].each do |held|
      refute_includes slugs, "starling-lexstat-#{held}",
                      "#{held} is held (Big5 lane / declined duplicate / not lexical)"
    end
    assert_equal Nabu::Adapters::StarlingLexstat::IE_TABLES.keys + slugs,
                 Nabu::Adapters::StarlingLexstat::TABLES.keys, "IE.exe's ten first, then the packages' 48"
  end

  def test_shelf_languages_are_registry_branch_codes_with_declared_sintib_coarseness
    languages = PACKAGES::TABLES.to_h { |slug, table| [slug.delete_prefix("starling-lexstat-"), table.fetch(:language)] }
    assert_equal %w[tut jpx qfa-kor xgn tuw trk], languages.values_at(*%w[alt jap kor mong tung turc])
    assert_equal %w[cau-ava cau-nwc cau-tsz cau-drg kjj lbe cau-lzg cau-nkh qfa-yen],
                 languages.values_at(*%w[aand abad cez darg khin lak lezg nakh yen])
    assert_equal "sit-kir", languages["kir"]
    assert_equal ["tbq"], languages.values_at(*(WAVE_B - ["kir"])).uniq,
                 "subgroups without a registry node file under Tibeto-Burman — declared coarseness"
    assert_equal %w[dra qfa-cka ccs], languages.values_at(*WAVE_C)
  end

  # --- the collision map ------------------------------------------------------------

  def label(package, siglum) = PACKAGES::LANGUAGES.fetch(package).fetch(siglum)[1]

  def test_the_same_siglum_names_different_languages_per_package
    assert_equal ["Spoken Manchu", "Manipuri", "Manda"],
                 [label("altaic", "MAN"), label("sintib", "MAN"), label("drav", "MAN")]
    assert_equal %w[Kanauri Kannada], [label("sintib", "KAN"), label("drav", "KAN")]
    assert_equal %w[Chechen Chepang], [label("cauc", "CHE"), label("sintib", "CHE")]
    assert_equal %w[Konyak Konda], [label("sintib", "KON"), label("drav", "KON")]
    assert_equal %w[Kottish Kota], [label("yenisey", "KOT"), label("drav", "KOT")]
    assert_equal %w[Pumpokol Pumi1], [label("yenisey", "PUM"), label("sintib", "PUM")]
    assert_equal %w[Tamang Tamil], [label("sintib", "TAM"), label("drav", "TAM")]
    assert_equal %w[Khakassian Haka], [label("altaic", "HAK"), label("sintib", "HAK")]
    assert_equal ["Upper-Bangni", "Upper Bal Svan"], [label("sintib", "UBA"), label("kart", "UBA")]
    ie = Nabu::Adapters::StarlingLexstat::LANGUAGES
    assert_equal %w[Kalmuck Kalasha], [label("altaic", "KAL"), ie.fetch("KAL")[1]]
    assert_equal %w[Tatar Tat], [label("altaic", "TAT"), ie.fetch("TAT")[1]]
  end

  # census: 19, 2026-10-11 — every siglum whose label differs across the
  # seven package maps and IE.exe's (computed, the module header's list).
  def test_the_collision_census_is_pinned
    maps = PACKAGES::LANGUAGES.merge("ie" => Nabu::Adapters::StarlingLexstat::LANGUAGES)
    labels = Hash.new { |hash, siglum| hash[siglum] = [] }
    maps.each_value { |map| map.each { |siglum, row| labels[siglum] << row[1] } }
    collisions = labels.select { |_, names| names.uniq.size > 1 }.keys.sort
    assert_equal %w[CHE GAL HAK KAB KAL KAN KHO KON KOT LSH MAN MAR MGR PAR PUM SHU TAM TAT UBA], collisions
  end

  def test_a_table_reads_only_its_own_package_map
    assert_equal "Spoken Manchu", language_line(entries("starling-lexstat-tung")["29.man"])
    assert_equal "Manipuri", language_line(entries("starling-lexstat-man")["5.man"])
    assert_equal "Manda (MAN — #{INFERRED})", language_line(entries("starling-lexstat-drav")["3.man"])
    assert_equal "Kottish", language_line(entries("starling-lexstat-yen")["10.kot"])
    assert_equal "Kota (KOT — #{INFERRED})", language_line(entries("starling-lexstat-drav")["3.kot"])
    assert_equal "Pumi1", language_line(entries("starling-lexstat-syc")["1.pum"])
  end

  # --- wave A -----------------------------------------------------------------------

  def test_alt_is_the_union_table_and_the_branch_inf_wins_over_alt_inf
    document = parse("starling-lexstat-alt")
    assert_equal "tut", document.language
    assert_match(/union table/, document.title)
    assert_equal 107, document.size, "6 + 48 (the two 'all' rows) + 53 (ashes); the date row mints nothing"
    by_id = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal "barčɨ", by_id["1.tat"].headword, "file position 1 is the sparse synonym row — it comes FIRST"
    assert_equal "böten", by_id["1.tat-b"].headword
    assert_equal "Spoken Manchu", language_line(by_id["1.man"]), "tung.inf wins over alt.inf's 'Literary Manchu'"
    assert_equal "tut", by_id["1.man"].language, "no code for Spoken Manchu — folds under the shelf"
    assert_equal "Literary Manchu", language_line(by_id["1.lma"])
    assert_equal "mnc", by_id["1.lma"].language
    assert_equal "Phyenyang", language_line(by_id["1.phn"]), "kor.inf wins over alt.inf's 'Modern Korean'"
    assert_equal "Azeri", language_line(by_id["1.azb"]), "turc.inf wins over alt.inf's 'Azerbaidzhan'"
    assert_equal "Middle Mongolian", language_line(by_id["1.amo"]), "mong.inf lacks AMO; alt.inf supplies it"
    assert_includes by_id["2.lma"].body, "Century (header row): 18"
    assert_includes by_id["1.atu"].body, "Century (header row): 8"
  end

  def test_alt_numbers_absent_from_the_trimmed_altet_fixture_ride_verbatim
    by_id = entries("starling-lexstat-alt")
    # Live, altet holds #1371 (every positive alt cell resolves, census);
    # the fixture's altet keeps only #1/#2/#1728, so here it reads verbatim.
    assert_includes by_id["1.trk"].body, "Cognation number: 1371"
    refute_match(/Altaic etymology/, by_id["1.trk"].body)
    assert_includes by_id["1.uig"].body, "Cognation number: -6"
  end

  def test_turc_resolves_into_turcet_and_an_upstream_dead_number_rides_verbatim
    by_id = entries("starling-lexstat-turc")
    assert_equal "trk", parse("starling-lexstat-turc").language
    assert_equal "kül", by_id["2.trk"].headword
    assert_equal "ashes", by_id["2.trk"].gloss
    assert_equal "tr", by_id["2.trk"].language
    assert_includes by_id["2.trk"].body, "Turkic etymology: #2", "turcet #2 *kül 'ashes' is IN this fixture set"
    chuvash = by_id["35.chv"]
    assert_equal "siməs (<?)", chuvash.headword
    assert_includes chuvash.body, "Cognation number: 3334",
                    "#3334 lies past turcet's last record upstream (turc: 2,177 of 2,181 resolve) — never a dead link"
    refute_match(/Turkic etymology/, chuvash.body)
    assert_includes by_id["35.hak"].body, "Cognation number: -2"
  end

  def test_tung_and_lezg_link_into_their_branch_bases
    tung = entries("starling-lexstat-tung")
    assert_includes tung["29.neg"].body, "Tungus-Manchu etymology: #42",
                    "tunget #42 *xol-sa 'fish' is IN this fixture set"
    assert_includes tung["29.man"].body, "Cognation number: 43", "#43 is live upstream, not kept in the tunget fixture"
    lezg = entries("starling-lexstat-lezg")
    assert_equal "cau-lzg", parse("starling-lexstat-lezg").language
    assert_equal "zun", lezg["42.lzg"].headword
    assert_equal "lez", lezg["42.lzg"].language
    assert_includes lezg["42.lzg"].body, "Lezghian etymology: #1"
    assert_includes lezg["7.udi"].body, "Lezghian etymology: #11"
  end

  def test_yen_is_var_backed_and_takes_yenet_inf_labels
    document = parse("starling-lexstat-yen")
    assert_equal "qfa-yen", document.language
    assert_equal %w[10.ket 10.sym 10.kot 44.ket 44.sym 44.kot 44.ari], document.map(&:entry_id)
    by_id = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal "aʔt", by_id["10.ket"].headword, "the WORD/form cells are var-pointers into yen.var"
    assert_equal "bone", by_id["10.ket"].gloss
    assert_equal "Yug", language_line(by_id["10.sym"]), "yen.inf has no aliases — yenet.inf's"
    assert_equal "zko", by_id["44.kot"].language
    assert_includes by_id["44.kot"].body, "Yenisseian etymology: #1"
    assert_includes by_id["44.kot"].body, "Century (header row): 19"
    assert_includes by_id["44.ari"].body, "Century (header row): 18"
  end

  # --- wave B: resolve-or-verbatim ---------------------------------------------------

  def test_kir_reads_yam_through_kiret_inf_and_links_into_kiret
    document = parse("starling-lexstat-kir")
    assert_equal "sit-kir", document.language
    by_id = document.entries.to_h { |e| [e.entry_id, e] }
    yamphu = by_id["5.yam"]
    assert_equal "bi:d- ; bi:-", yamphu.headword
    assert_equal "Yamphu", language_line(yamphu), "kir.inf lacks YAM; kiret.inf (same package) names it"
    assert_equal "ybi", yamphu.language
    assert_includes yamphu.body, "Kiranti etymology: #645", "kiret #645 is IN this fixture set"
    assert_includes by_id["8.kul"].body, "Cognation number: 4425",
                    "#4425 lies past kiret's last record upstream — verbatim, never a dead link"
    assert_includes by_id["8.dum"].body, "Cognation number: -1"
  end

  def test_sintib_tables_link_only_numbers_that_resolve_in_stibet
    tani = entries("starling-lexstat-tani")
    assert_includes tani["5.mil"].body, "Sino-Tibetan etymology: #2", "stibet #2 is IN this fixture set"
    assert_equal "Gallong", language_line(tani["5.gal"])
    assert_equal "adl", tani["5.gal"].language
    assert_includes tani["5.gal"].body, "Cognation number: 1453", "live in stibet, not kept in its fixture"
    syc = entries("starling-lexstat-syc")
    assert_includes syc["1.zhb"].body, "Cognation number: 4006",
                    "the sintib misses are numbers past stibet's 2,823 records (4000+)"
    assert_equal "thəm tćɛ TIB", syc["1.dao"].headword, "the borrowing marker rides verbatim"
    assert_includes syc["1.dao"].body, "Cognation number: -1"
    manipuri = entries("starling-lexstat-man")
    assert_equal %w[5.man], manipuri.keys, "the date row (WORD '20') mints nothing"
    assert_equal "mni", manipuri["5.man"].language
  end

  # --- wave C: the ruled readings ----------------------------------------------------

  def test_drav_declares_every_inferred_column_on_the_shelf_and_the_entry
    document = parse("starling-lexstat-drav")
    assert_equal "dra", document.language
    assert_equal 47, document.size
    assert_includes document.title,
                    "column readings #{INFERRED}: KOT Kota, TOD Toda, TEL Telugu, KOL Kolami, NAI Naikri, " \
                    "PAR Parji, GAD Gadba, GON Gondi, PEN Pengo, MAN Manda, KUW Kuwi"
    by_id = document.entries.to_h { |e| [e.entry_id, e] }
    assert_equal "Telugu (TEL — #{INFERRED})", language_line(by_id["3.tel"])
    assert_equal "te", by_id["3.tel"].language
    assert_equal "Kannada", language_line(by_id["3.kan"]), "sdret.inf documents KAN — no inference note"
    assert_equal "Gadba (GAD — #{INFERRED})", language_line(by_id["3.gad"])
    assert_equal "dra", by_id["3.gad"].language, "Gadba has no single code — folds under the shelf"
    assert_includes by_id["37.bra"].body, "Cognation number: 2300", "past dravet's records upstream"
    assert_includes by_id["3.yer"].body, "Cognation number: 5001"
  end

  def test_kam_takes_the_decimal_date_row_and_links_into_kamet
    document = parse("starling-lexstat-kam")
    assert_equal "qfa-cka", document.language
    refute document.entries.any? { |e| e.entry_id.start_with?("0.") }, "the 17.5-bearing date row is a date row"
    assert_match(/CHQ Chukchee, KRQ Koryak, PLQ Palana, KAR Karaga, ITL Itelmen, IRS Itelmen \(Khaloymova\)/,
                 document.title)
    by_id = document.entries.to_h { |e| [e.entry_id, e] }
    karaga = by_id["11.kar"]
    assert_equal "vašá-tꭓaš`", karaga.headword
    assert_includes karaga.body, "Century (header row): 17.5"
    assert_equal "Karaga (KAR — #{INFERRED})", language_line(karaga)
    assert_includes by_id["11.chq"].body, "Chukchee-Kamchatkan etymology: #1", "kamet #1 is IN this fixture set"
    assert_equal "ckt", by_id["11.chq"].language
    assert_includes by_id["7.chq"].body, "Cognation number: 2001", "past kamet's 1,099 records upstream"
    assert_equal "?", by_id["7.plq"].headword, "a bare doubt cell is a form cell (the dard precedent)"
    assert_equal "Alutor", language_line(by_id["7.alu"]), "chuket.inf documents ALU"
    assert_equal "Western Kamchadal", language_line(by_id["7.wit"])
  end

  def test_kart_has_no_target_so_every_number_rides_verbatim
    document = parse("starling-lexstat-kart")
    assert_equal "ccs", document.language
    assert_match(/proto = NONE/, document.title)
    assert_match(/GEO Georgian, UBA Upper Bal Svan, LSH Lashkh Svan, LEN Lentekh Svan/, document.title)
    by_id = document.entries.to_h { |e| [e.entry_id, e] }
    assert_includes by_id["1.geo"].body, "Cognation number: 1", "a table-internal class number, never a link"
    assert_equal "Georgian (GEO — #{INFERRED})", language_line(by_id["1.geo"])
    assert_equal "Megrel", language_line(by_id["1.meg"]), "kartet.inf documents MEG"
    assert_equal "sva", by_id["2.lsh"].language
    assert_equal "dəṭ", by_id["2.lsh"].headword
  end

  # --- guards and conformance --------------------------------------------------------

  def test_an_unknown_column_siglum_quarantines_the_package_table
    languages = PACKAGES::LANGUAGES.fetch("sintib").except("YAM")
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::StarlingLexstat.new.parse(
        slug: "starling-lexstat-kir", path: File.join(FIXTURES, "sintib", "LEXSTAT", "kir.dbf"), languages: languages
      )
    end
    assert_match(/YAM/, error.message)
  end

  def test_every_fixture_table_column_has_its_package_row
    Dir[File.join(FIXTURES, "*", "LEXSTAT", "*.dbf")].each do |path|
      package = File.basename(File.dirname(path, 2))
      names = Nabu::Adapters::StarlingDbfParser.new(dbf_path: path).fields.map(&:name)
      columns = names.select { |name| name != "NUMBER" && names.include?("#{name}NUM") }
      refute_empty columns
      columns.each { |column| assert PACKAGES::LANGUAGES.fetch(package).key?(column), "#{path}: #{column}" }
    end
  end

  def test_entry_ids_are_unique_stable_utf8_and_output_is_nfc
    (WAVE_A + WAVE_B + WAVE_C).each do |stem|
      slug = "starling-lexstat-#{stem}"
      ref = adapter.discover(FIXTURES).find { |r| r.metadata.fetch("dictionary") == slug } or next
      first = adapter.parse(ref).map(&:entry_id)
      assert_equal first.uniq, first
      assert_equal first, adapter.parse(ref).map(&:entry_id)
      adapter.parse(ref).each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
        refute_empty entry.headword_folded
        assert_equal Encoding::UTF_8, entry.entry_id.encoding
        assert_empty entry.reflexes, "wordlist cells mint no reflex edges"
      end
    end
  end

  # census: 12, 2026-10-11 — the fixture tables kept (README).
  def test_twelve_package_tables_are_discovered_from_the_fixture_tree
    found = adapter.discover(FIXTURES).map { |r| r.metadata.fetch("dictionary") } & PACKAGES::TABLES.keys
    assert_equal %w[alt tung turc lezg yen kir man syc tani drav kam kart].map { "starling-lexstat-#{_1}" }.sort,
                 found.sort
  end

  def test_loading_the_package_shelves_twice_is_idempotent
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "starling", name: "StarLing", adapter_class: "Nabu::Adapters::Starling",
      license: Nabu::Adapters::Starling::MANIFEST.license, license_class: "attribution",
      upstream_url: Nabu::Adapters::Starling::MANIFEST.upstream_url, enabled: false
    )
    loader = Nabu::Store::DictionaryLoader.new(db: db, source: source)
    loader.load_from(adapter, workdir: FIXTURES)
    lexstat = db[:dictionary_entries].where(Sequel.like(:urn, "urn:nabu:dict:starling-lexstat-%"))
    count = lexstat.count
    assert_equal 289 + 80, count, "289 package form cells + IE.exe's 16 balt + 49 germ + 15 mix"
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal count, lexstat.count
    assert_equal [1], lexstat.select_map(:revision).uniq
  end
end
