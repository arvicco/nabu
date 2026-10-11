# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Litopys (P117, row 252): the Izbornyk PD-edition subset —
# the Ipatiev chronicle after ПСРЛ т. 2 (СПб., 1908), one document per site
# page, one passage per edition COLUMN; plus the three PD glossaries of the
# «Лексикони» shelf as the declared dictionary lane. The packet is the
# EDITION TRIAGE (Litopys::TRIAGE): pinned here so the census and the rule
# can never drift apart.
#
# Fixtures (test/fixtures/litopys/, README there): real windows-1251 pages
# retrieved 2026-10-11 — ipat01 (cols 1–2 + 19–21: the print's heading, the
# first folio marks, the first annal-year keys), ipat05 (cols 89–94: the
# Mberid quirk, the mislabeled "58" anchor, a KF paragraph), ipat36 (cols
# 810–812: the "809п 810" continuation anchor), ipat40 whole (cols 895–903,
# the bracketed [II, N] marks), and the glossaries zyz100 (А + Ю letters),
# zyz101 and zyz102 whole.
class LitopysTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("litopys")
  Litopys = Nabu::Adapters::Litopys

  def conformance_adapter = Litopys.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "litopys"

  def adapter = Litopys.new

  def doc(stem)
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "urn:nabu:litopys:#{stem}" }
    flunk("no ref for #{stem}") unless ref
    adapter.parse(ref)
  end

  def passage(document, column)
    document.passages.find { |candidate| candidate.urn == "#{document.urn}:#{column}" } ||
      flunk("no column #{column} in #{document.urn}")
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_is_open_with_the_site_credit_and_the_pd_basis
    manifest = Litopys.manifest
    assert_equal "litopys", manifest.id
    assert_equal "open", manifest.license_class
    assert_equal "litopys-html", manifest.parser_family
    assert_match(/no license exists to cite/, manifest.license)
    assert_match(/1908/, manifest.license)
    assert_match(/Izbornyk|Ізборник/, manifest.credit)
    assert_equal "http://litopys.org.ua/", manifest.upstream_url, "plain http — the https cert is broken upstream"
  end

  # --- the edition triage -------------------------------------------------------

  def test_the_rule_excludes_every_tainted_statement_and_admits_every_admitted_one
    Litopys::TRIAGE.each do |entry|
      case entry.verdict
      when :edition_tainted
        assert Litopys.tainted?(entry.statement), "#{entry.path}: a tainted verdict must be the rule's verdict"
      when :admitted_chronicle, :admitted_glossary
        refute Litopys.tainted?(entry.statement), "#{entry.path}: an admitted statement must pass the rule"
      else
        assert_equal :apparatus, entry.verdict
      end
      refute_empty entry.basis, "#{entry.path}: every verdict records its reasoning"
    end
  end

  def test_the_census_admits_the_whole_chronicle_and_three_glossaries
    assert_equal 41, Litopys::ADMITTED_CHRONICLE.size
    assert_equal "ipatlet/ipat01.htm", Litopys::ADMITTED_CHRONICLE.first
    assert_equal "ipatlet/ipat41.htm", Litopys::ADMITTED_CHRONICLE.last
    assert_equal %w[zyzlex/zyz100.htm zyzlex/zyz101.htm zyzlex/zyz102.htm], Litopys::ADMITTED_GLOSSARIES
    excluded = Litopys::TRIAGE.select { |entry| entry.verdict == :edition_tainted }.map(&:path)
    assert_includes excluded, "berlex/be.htm", "Беринда rides Німчук's 1961 edition"
    assert_includes excluded, "zyzlex/zyz.htm", "the Лексис rides Німчук's 1964 edition"
    assert_equal Litopys::ADMITTED_CHRONICLE + Litopys::ADMITTED_GLOSSARIES, Litopys::FETCH_PAGES,
                 "only admitted texts are ever fetched"
  end

  def test_a_page_whose_statement_drifts_past_1930_is_skipped_at_discover
    Dir.mktmpdir("litopys-drift") do |work|
      FileUtils.cp_r(File.join(FIXTURES, "."), work)
      path = File.join(work, "ipatlet", "ipat40.htm")
      bytes = File.binread(path)
      drifted = bytes.sub(/(Vary_cent>[^\n]*?)1908/n) { "#{Regexp.last_match(1)}1997" }
      refute_equal bytes, drifted, "the statement's 1908 is rewritten to a post-1930 year"
      File.binwrite(path, drifted)

      ids = adapter.discover(work).map(&:id)
      refute_includes ids, "urn:nabu:litopys:ipat40"
      skips = adapter.discovery_skips(work)
      assert_equal 1, skips.skipped_by_rule
      assert_match(/EDITION_TAINT_POST_1930/, skips.notes.join)
    end
  end

  def test_discovery_accounts_for_every_fixture_file
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 0, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized, "the glossary pages belong to the lane, never strays"
  end

  # --- the chronicle --------------------------------------------------------------

  def test_one_document_per_page_with_the_section_and_column_range
    document = doc("ipat40")
    assert_equal "orv", document.language
    assert_match(/Галицко-Волынскій/, document.title)
    assert_match(/стлб\. 895–903/, document.title)
    assert_equal "895–903", document.metadata["columns"]
    assert_match(/СПб\., 1908/, document.metadata["edition"])
    assert_equal({ "not_before" => 1260, "not_after" => 1292,
                   "raw" => "Галицко-Волынскій сводъ — compiled 1260s–1290s (attributed)" },
                 document.metadata["era_band"])
    assert_equal "Galicia-Volhynia", document.metadata["place"]
    assert_equal({ "am_first" => 6792, "am_last" => 6795, "ad_first" => 1284, "ad_last" => 1287 },
                 document.metadata["annals"])
    assert_equal((895..903).to_a, document.passages.map { |p| p.annotations["column"] })
  end

  def test_a_column_carries_text_only_and_the_apparatus_rides_annotations
    column = passage(doc("ipat01"), 1)
    assert column.text.start_with?("ЛѢТОПИСЬ ПО ИПАТЬЕВСКОМУ СПИСКУ.\nСе же соуть имена кнѧземъ Києвьскым ."),
           "superscript letters inline, apparatus keys dropped, paragraphs on their own lines"
    refute_match(/\d/, column.text.lines.first(2).join, "no apparatus digits leak into the text")
    assert_equal ["2"], column.annotations["folios"], "<small id=lyst2>//</small> is codex folio 2"
    assert_match(/\A1 Х\. а се же суть\./, column.annotations["variants"].first)
    assert_match(/\AА Эта статья имѣется только въ Ип\. и Х\./, column.annotations["notes"].first)
  end

  def test_the_site_annal_keys_ride_annotations_never_text
    column = passage(doc("ipat01"), 21)
    assert_equal [{ "am" => 6413, "ad" => 904 }, { "am" => 6414, "ad" => 905 }, { "am" => 6415, "ad" => 906 }],
                 column.annotations["annal_years"]
    refute_includes column.text, "6413"
  end

  def test_upstream_marker_quirks_resolve_to_the_right_columns
    ipat05 = doc("ipat05")
    assert_equal (89..94).to_a, ipat05.passages.map { |p| p.annotations["column"] },
                 "Mberid=\"st91\" still marks 91; the mislabeled \"58\" anchor is column 92 (errata)"
    assert passage(ipat05, 93).text.start_with?("и смыслены"), "a KF paragraph is text"
    assert_equal ["41"], passage(ipat05, 93).annotations["folios"]

    ipat36 = doc("ipat36")
    assert_equal 810, ipat36.passages.first.annotations["column"], "the \"809п … 810\" anchor opens column 810"
  end

  def test_bracketed_site_references_are_marks
    assert_equal ["[II, 214]"], passage(doc("ipat40"), 898).annotations["marks"]
  end

  def test_the_font_hack_decodes_to_yat
    text = passage(doc("ipat40"), 895).text
    assert_includes text, "лѣт̑"
    refute_includes text, "Ђ"
  end

  # --- the glossary lane ------------------------------------------------------------

  def lane = Litopys.dictionary_lane

  def glossary(slug)
    ref = lane.discover(FIXTURES).find { |candidate| candidate.id == "litopys-glossary:#{slug}" }
    flunk("no glossary #{slug}") unless ref
    lane.parse(ref)
  end

  def test_the_lane_yields_three_glossary_shelves
    assert_equal %w[litopys-glossary:litopys-lexis-prosto litopys-glossary:litopys-rech-zhidovska
                    litopys-glossary:litopys-tlkovanie], lane.discover(FIXTURES).map(&:id)
    assert_equal :dictionary, lane.class.content_kind
  end

  def test_glossary_entries_split_headword_and_gloss
    lexis = glossary("litopys-lexis-prosto")
    first = lexis.entries.first
    assert_equal "1", first.entry_id
    assert_equal "Апосто(л)", first.headword
    assert_equal "посланникъ.", first.gloss
    refute(lexis.entries.any? { |entry| entry.headword == "по слове(н)ску" }, "the print's column header is no entry")
    assert_equal 50, lexis.size, "А (48) + Ю (2) in the trimmed fixture"

    rech = glossary("litopys-rech-zhidovska")
    assert_equal 174, rech.size
    assert_equal "Акелдама", rech.entries.first.headword
    assert_equal "село кръви.", rech.entries.first.gloss

    tlk = glossary("litopys-tlkovanie")
    assert_equal 61, tlk.size
    assert_equal "Свѣне", tlk.entries[4].headword, "<small>Ђ</small> decodes to ѣ inside headwords"
    assert_equal "кромѣ.", tlk.entries[4].gloss
  end

  def test_glossaries_load_idempotently_through_the_lane
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "litopys", name: "Izbornyk", adapter_class: "Nabu::Adapters::Litopys",
                                        license_class: "open")
    2.times do
      result = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(lane, workdir: FIXTURES)
      assert_equal 0, result.errored
      assert_equal 50 + 174 + 61, db[:dictionary_entries].count
    end
    assert_includes db[:dictionary_entries].select_map(:urn), "urn:nabu:dict:litopys-rech-zhidovska:1"
  ensure
    db&.disconnect
  end

  # --- fetch (WebMock: no network) ------------------------------------------------

  def fast_adapter
    adapter.tap { |instance| instance.define_singleton_method(:fetch_delay) { 0 } }
  end

  def test_fetch_gets_only_the_admitted_pages_and_pins_them
    stub_request(:get, %r{\Ahttp://litopys\.org\.ua/}).to_return(status: 200, body: "page")
    Dir.mktmpdir("litopys-fetch") do |work|
      report = fast_adapter.fetch(work)
      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{64}\z/, report.sha)
      assert_requested :get, %r{\Ahttp://litopys\.org\.ua/}, times: 44
      assert File.file?(File.join(work, "ipatlet", "ipat41.htm"))
      refute File.exist?(File.join(work, "berlex", "be.htm")), "an excluded text is never fetched"
    end
  end

  def test_fetch_failure_on_both_hosts_is_a_fetch_error
    stub_request(:get, /litopys\.org\.ua|izbornyk\.org\.ua/).to_return(status: 500)
    Dir.mktmpdir("litopys-fetch") do |work|
      error = assert_raises(Nabu::FetchError) { fast_adapter.fetch(work) }
      assert_match(/every host failed/, error.message)
    end
  end

  include StoreTestDB
end
