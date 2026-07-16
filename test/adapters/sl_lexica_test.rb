# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The sl-lexica adapter (P23-2): the Slovenian historical dictionary shelf —
# Pleteršnik 1894–95 + Slovar jezika Janeza Svetokriškega + Besedje 16
# (three ZRC SAZU deposits on CLARIN.SI, one identical verbatim CC BY 4.0
# grant → ONE source, three dictionaries; census journaled in
# docs/backlog.md P23-2). Dictionary-shaped, so like StarlingTest/MwTest it
# MIRRORS the passage-shaped conformance suite (manifest validity,
# discover→parse round-trip, id uniqueness/stability, NFC, license class)
# and adds the packet pins: the toneme fold (abecę̑da typed as abeceda),
# the ge-vs-oi headword split (ábəł folds from its unaccented ge "abel"),
# JSV volume/page citations minted unresolved (cts_work nil — display-only
# until an IMP crosswalk exists), besedje16 attestation sigla verbatim in
# the body, the three-zip fetch, the DictionaryLoader contract, the
# language-notes rider, and the define acceptance render.
class SlLexicaTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("sl-lexica")

  ZIP_URLS = {
    "pletersnik" => "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1114/Pletersnik.zip",
    "jsv" => "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1092/JSV.zip",
    "besedje16" => "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1127/besedje16.zip"
  }.freeze

  def adapter = Nabu::Adapters::SlLexica.new

  def nfc(str) = Nabu::Normalize.nfc(str)

  # --- manifest + content kind ------------------------------------------------------

  def test_manifest_identifies_the_shelf_with_the_verbatim_clarin_grant
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "sl-lexica", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/Creative Commons - Attribution 4\.0 International \(CC BY 4\.0\)/, manifest.license,
                 "the deposit records' dc.rights travels verbatim")
    assert_match(%r{11356/1114}, manifest.license, "the license names its three records")
    assert_match(%r{11356/1092}, manifest.license)
    assert_match(%r{11356/1127}, manifest.license)
    assert_equal "zrc-xml", manifest.parser_family
  end

  def test_content_kind_is_dictionary_and_the_shelf_promises_no_reflexes
    assert_equal :dictionary, Nabu::Adapters::SlLexica.content_kind
    refute Nabu::Adapters::SlLexica.reflex_bearing?
  end

  # --- discover → parse round-trip --------------------------------------------------

  def test_discover_yields_one_ref_per_dictionary_in_registry_order
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["pletersnik:Pletersnik.xml", "jsv:JSV.xml", "besedje16:besedje16.xml"], refs.map(&:id)
    assert_equal %w[sl-lexica sl-lexica sl-lexica], refs.map(&:source_id)
    assert_equal(%w[pletersnik jsv besedje16], refs.map { |ref| ref.metadata.fetch("dictionary") })
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def parse(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.metadata.fetch("dictionary") == slug }
    adapter.parse(ref)
  end

  def test_parse_yields_three_sl_dictionary_documents
    %w[pletersnik jsv besedje16].each do |slug|
      document = parse(slug)
      assert_kind_of Nabu::DictionaryDocument, document
      assert_equal slug, document.slug
      assert_equal "sl", document.language, "one honest code — headwords are modernized orthography; " \
                                            "the period lives in the title and the language note"
    end
    assert_match(/1894/, parse("pletersnik").title)
    assert_match(/Svetokriškega/, parse("jsv").title)
    assert_match(/16th/i, parse("besedje16").title)
  end

  def test_entry_ids_are_the_zero_padded_geslo_ids_unique_and_stable
    { "pletersnik" => %w[000001 000002 000003 000005 000012 001934 102523],
      "jsv" => %w[000002 000003 000007 000026 000033],
      "besedje16" => %w[000004 000010 000011 000021 000125 000175] }.each do |slug, expected|
      first = parse(slug).map(&:entry_id)
      assert_equal expected, first, "#{slug}: geslo-id adopted verbatim, file order"
      assert_equal first, parse(slug).map(&:entry_id)
    end
  end

  def test_entry_output_is_nfc
    %w[pletersnik jsv besedje16].each do |slug|
      parse(slug).each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
      end
    end
  end

  # --- Pleteršnik: tonemes, homographs, German glosses ------------------------------

  def test_pletersnik_display_headword_is_the_accented_oi_folded_from_the_unaccented_ge
    entries = parse("pletersnik").entries.to_h { |e| [e.entry_id, e] }
    abeceda = entries["000005"]
    assert_equal nfc("abecę̑da"), abeceda.headword, "the toneme form is the display headword"
    assert_equal "abeceda", abeceda.key_raw, "the unaccented ge verbatim"
    assert_equal "abeceda", abeceda.headword_folded
    abel = entries["000012"]
    assert_equal nfc("ábəł"), abel.headword
    assert_equal "abel", abel.headword_folded,
                 "folded from ge — ə/ł in the accented form would never match a modern query"
  end

  def test_pletersnik_homograph_triple_shares_the_folded_key_and_keeps_ei_in_the_headline
    entries = parse("pletersnik").entries.to_h { |e| [e.entry_id, e] }
    assert_equal(%w[a a a], %w[000001 000002 000003].map { |id| entries[id].headword_folded })
    assert_equal "1. ȃ, interj.", entries["000002"].body.lines.first.chomp
    assert_equal "2. à, interj.", entries["000003"].body.lines.first.chomp
  end

  def test_pletersnik_gloss_is_the_first_german_po_and_body_lines_are_headline_ra_pi
    entries = parse("pletersnik").entries.to_h { |e| [e.entry_id, e] }
    abeceda = entries["000005"]
    assert_equal "das ABC, das Alphabet", abeceda.gloss
    assert_equal [nfc("abecę̑da, f."),
                  "das ABC, das Alphabet, Mur., Cig., Jan., Vod., nk., " \
                  "po abecedi, in alphabetischer Ordnung, Cig."],
                 abeceda.body.lines.map(&:chomp)
    assert_includes entries["000012"].body.lines.last,
                    "prim. bav. afel, gegen Berührungen besonders empfindliche Stelle der Haut",
                    "the pi etymology zone is its own body line"
    assert_equal nfc("blȃžji, -žja (nam. -žij, -žija), m."),
                 entries["001934"].body.lines.first.chomp,
                 "pr/vi inflection-variant zones interleave in document order"
  end

  def test_pletersnik_dodatek_entry_has_no_ra_and_an_honest_nil_gloss
    apnariti = parse("pletersnik").entries.to_h { |e| [e.entry_id, e] }["102523"]
    assert_nil apnariti.gloss
    assert_equal nfc("apnáriti, -ȃrim (nam. -im)."), apnariti.body
  end

  # --- JSV: Baroque quotes, citations, loanword etymologies -------------------------

  def test_jsv_gloss_is_the_modern_slovenian_po_and_quotes_keep_bohoric_orthography
    entries = parse("jsv").entries.to_h { |e| [e.entry_id, e] }
    a2 = entries["000002"]
    assert_equal "k", a2.gloss
    assert_equal "a 2 cit. predl. z daj.", a2.body.lines.first.chomp
    assert_includes a2.body, "Ah kulikain oblubi ſturj A S: Poloniæ",
                    "the attestation quote rides verbatim, long s and all"
    assert_includes a2.body, "← it. a za tvorbo dajalnika < lat. ad",
                    "the op loanword etymology is its own body line"
    assert_equal "a", entries["000003"].headword_folded, "à folds onto its homograph"
  end

  def test_jsv_volume_page_citations_are_minted_unresolved
    entries = parse("jsv").entries.to_h { |e| [e.entry_id, e] }
    citation = entries["000002"].citations.first
    assert_equal "(I/1, 184)", citation.label
    assert_equal "(I/1, 184)", citation.urn_raw
    assert_nil citation.cts_work, "no urn is invented — resolution against IMP is future work"
    assert_equal "I/1.184", citation.citation
    sequitur = entries["000033"].citations.first
    assert_equal "(II, 194 s.)", sequitur.label
    assert_equal "II.194", sequitur.citation, "the 's.' (and-following) suffix parses leniently"
    assert_empty entries["000007"].citations, "no ct, no rows"
  end

  def test_jsv_sense_numbers_land_on_their_own_lines
    abramov = parse("jsv").entries.to_h { |e| [e.entry_id, e] }["000026"]
    senses = abramov.body.lines.map(&:chomp).select { |line| line.start_with?("1.", "2.") }
    assert_equal 2, senses.size, "sp sense numbers split the pz block"
    assert senses[0].include?("Abrahamov")
    assert senses[1].include?("Abramov")
  end

  # --- besedje16: POS + attestation sigla verbatim -----------------------------------

  def test_besedje16_entries_are_one_line_bodies_with_the_sigla_verbatim
    entries = parse("besedje16").entries.to_h { |e| [e.entry_id, e] }
    a4 = entries["000004"]
    assert_equal "a", a4.headword
    assert_equal "a črka ♦ P: 11 (TA 1550, TA 1555, TA 1566, KB 1566, KPo 1567, TC 1575, " \
                 "DJ 1575, TT 1581-82, DB 1584, BH 1584, DC 1585)", a4.body,
                 "the per-word attestation sigla — DB 1584 is goo300k's zrc_00001-1584"
    assert_nil a4.gloss
    assert_equal "aamoriterski gl. amoriterski ♦ P: 1 (DB 1578)", entries["000010"].body,
                 "kaz cross-references linearize in place"
    assert_includes entries["000125"].body, "(ajrat blago) sam. s ♦ P: 1 (MTh 1603)",
                    "the second prav + sku/skupk group survives"
  end

  def test_besedje16_gloss_is_the_bracket_stripped_razl_when_present
    entries = parse("besedje16").entries.to_h { |e| [e.entry_id, e] }
    assert_equal "rabelj", entries["000011"].gloss
    assert_nil entries["000175"].gloss
  end

  # --- fetch (WebMock only) -----------------------------------------------------------

  def zip_bodies
    @zip_bodies ||= ZIP_URLS.to_h do |slug, _url|
      dir = File.join(FIXTURES, slug)
      Dir.mktmpdir do |tmp|
        zip = File.join(tmp, "#{slug}.zip")
        Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", zip, *Dir.children(dir)) }
        [slug, File.binread(zip)]
      end
    end
  end

  def test_fetch_downloads_all_three_zips_and_discovers_the_shelf
    ZIP_URLS.each { |slug, url| stub_request(:get, url).to_return(status: 200, body: zip_bodies[slug]) }
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal ZIP_URLS.values.sort, report.repos.keys.sort, "per-zip shas ride the report"
      refs = adapter.discover(workdir).to_a
      assert_equal ["pletersnik:Pletersnik.xml", "jsv:JSV.xml", "besedje16:besedje16.xml"], refs.map(&:id)
      assert_equal 7, adapter.parse(refs.first).size
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URLS.fetch("pletersnik")).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end

  def test_probe_heads_each_zip_with_per_dictionary_state
    assert_equal :http_zip, Nabu::Adapters::SlLexica.remote_probe_strategy
    targets = Nabu::Adapters::SlLexica.http_probe_targets
    assert_equal ZIP_URLS.values, targets.map(&:zip_url)
    assert_equal %w[pletersnik jsv besedje16], targets.map(&:state_subdir)
    targets.each do |target|
      assert_nil target.metadata_url, "the license lives on the record pages, not a probe-shaped endpoint"
      assert_equal Nabu::ZipFetch::STATE_FILE, target.state_file
    end
  end

  # --- DictionaryLoader contract ------------------------------------------------------

  def loader_setup(canonical_dir: nil)
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "sl-lexica", name: "sl-lexica", adapter_class: "Nabu::Adapters::SlLexica",
      license: Nabu::Adapters::SlLexica::MANIFEST.license, license_class: "attribution",
      upstream_url: Nabu::Adapters::SlLexica::MANIFEST.upstream_url, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source, canonical_dir: canonical_dir)]
  end

  def test_loading_twice_is_idempotent_with_stable_urns_and_citation_rows
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 18, first.added
    assert_equal 0, first.errored
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 18, second.skipped
    assert_equal 18, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
    assert_equal "urn:nabu:dict:pletersnik:000005",
                 db[:dictionary_entries].where(key_raw: "abeceda").get(:urn)
    assert_equal 2, db[:dictionary_citations].count, "the two JSV ct elements, nothing invented"
    assert_equal 3, db[:dictionaries].count
    assert_equal %w[sl], db[:dictionaries].select_map(:language).uniq
  end

  # --- language-notes rider ------------------------------------------------------------

  def test_load_accretes_the_sl_witness_section_idempotently
    Dir.mktmpdir do |root|
      _db, loader = loader_setup(canonical_dir: root)
      loader.load_from(adapter, workdir: FIXTURES)
      shelf = Nabu::LanguageShelf.new(dir: Nabu::LanguageShelf.dir(root))
      section = shelf.load("sl").section("witness:sl-lexica")
      assert_equal "sl-lexica", section.source
      assert_match(/Pleteršnik/, section.body)
      assert_match(/Svetokriški/, section.body)
      assert_match(/1550/, section.body)
      before = File.read(shelf.path_for("sl"))
      loader.load_from(adapter, workdir: FIXTURES)
      assert_equal before, File.read(shelf.path_for("sl"))
    end
  end

  # --- acceptance render: define, folded ------------------------------------------------

  def test_define_abeceda_reaches_the_pletersnik_entry_folded_both_ways
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Define.new(catalog: db).run("abeceda")
    assert_equal ["pletersnik"], results.map(&:dictionary_slug)
    result = results.first
    assert_equal nfc("abecę̑da"), result.headword, "the toneme display form"
    assert_equal "das ABC, das Alphabet", result.gloss
    assert_match(/CC BY 4\.0/, result.license)
    accented = Nabu::Query::Define.new(catalog: db).run(nfc("abecę̑da"))
    assert_equal results.map(&:urn), accented.map(&:urn), "the accented spelling folds to the same entry"
  end

  def test_define_a_unifies_all_three_dictionaries_on_one_folded_key
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    results = Nabu::Query::Define.new(catalog: db).run("a", lang: "sl", limit: 10)
    assert_equal %w[besedje16 jsv jsv pletersnik pletersnik pletersnik],
                 results.map(&:dictionary_slug),
                 "one lookup crosses the whole shelf — 16th-c., Baroque and 19th-c. Slovenian"
    citations = results.find { |r| r.urn == "urn:nabu:dict:jsv:000002" }.citations
    assert_equal ["(I/1, 184)"], citations.map(&:label)
    assert_nil citations.first.resolved_urn, "vol/page citations resolve nowhere yet — an honest miss"
  end

  # --- registry --------------------------------------------------------------------------

  def test_registry_row_is_live_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["sl-lexica"]
    refute_nil entry, "config/sources.yml must register sl-lexica"
    assert_equal Nabu::Adapters::SlLexica, entry.adapter_class
    assert entry.enabled, "live (owner sign-off 2026-07-16: synced 139,405 entries, eyeballed, flipped)"
    assert_equal "manual", entry.sync_policy
  end
end
