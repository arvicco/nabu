# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "fileutils"
require "json"
require "tmpdir"
require "zlib"

module Adapters
  # nb-no: Nasjonalbiblioteket's public-domain books through api.nb.no —
  # item record + ALTO list + per-page ALTO (gzipped). Fixtures (retrieved
  # 2026-11-08, see test/fixtures/nb-no/README.md): three COMPLETE items —
  # Rhodius's 1660 Christiania Latin carmen (all 4 pages), Þorfinns saga
  # karlsefnis (Reykjavík 1902, Old Norse; ALTO list trimmed to 3 pages)
  # and Stockfleth's North Sámi ABC (Christiania 1837; trimmed to 3) —
  # one PARTIAL item (Edda Snorra Sturlusonar 1931: the full 353-page
  # list, one page held) and one NOT-public-domain record (a 1608
  # Grammaticae Hebraeae catalogue row, no scan).
  class NbNoTest < Minitest::Test
    include AdapterConformance

    ROOT = Nabu::TestSupport.fixtures("nb-no")
    FIXTURES = File.join(ROOT, "canonical")
    Adapter = Nabu::Adapters::NbNo
    RHODIUS = "urn:nabu:nb-no:digibok_2026030928001"
    SAGA = "urn:nabu:nb-no:digibok_2021052848605"
    ABC = "urn:nabu:nb-no:digibok_2009020300033"
    RHODIUS_ID = "3d460ef4040b4bc7a4c849f4b6ceec1b"
    SAGA_ID = "59aa6dee234eab2f582dd5ba75f57597"
    ABC_ID = "9353c8a56ea655710692a548673b9618"
    EDDA_ID = "0148f6ba555e6d8ec9b5aaea23d39cbc"
    NON_PD_ID = "0056d274e30fd6246b3d29373c35ab97"

    def conformance_adapter = Adapter.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "nb-no"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).to_h { |ref| [ref.id, conformance_adapter.parse(ref)] }
    end

    def quiet(**) = Adapter.new(delay: 0, backoff: 0, **)

    # -- documents ---------------------------------------------------------

    def test_discovers_the_complete_public_domain_items
      assert_equal [RHODIUS, SAGA, ABC], documents.keys
    end

    def test_one_passage_per_page_cited_by_the_page_urn_tail
      rhodius = documents.fetch(RHODIUS)
      assert_equal(%w[C1 I1 I3 C3], rhodius.map { |p| p.urn.delete_prefix("#{RHODIUS}:") },
                   "a leaflet's 'cover' is its title page: no tail skips by rule")
      assert_includes rhodius.find { |p| p.urn.end_with?(":I1") }.text, "Regum progenie"
      assert_equal(%w[0001 0003 0010], documents.fetch(SAGA).map { |p| p.urn.split(":").last })
    end

    def test_alto_lines_flatten_with_the_printed_hyphen_kept
      page = documents.fetch(SAGA).find { |p| p.urn.end_with?(":0010") }
      assert_includes page.text, "Einarr braut upp\nvarning sinn"
      assert_includes page.text, "varn-\ningr", "the line as printed — SUBS_CONTENT never applied"
      title = documents.fetch(RHODIUS).first.text
      assert_includes title, "WAN-\nDALORUM"
    end

    def test_page_annotations_carry_the_printed_number_and_confidence
      page = documents.fetch(SAGA).find { |p| p.urn.end_with?(":0010") }
      assert_equal "0010", page.annotations["page"]
      assert page.annotations["ocr_confidence"].to_s.match?(/\A0\.\d+\z/), page.annotations.inspect
    end

    def test_language_is_the_records_first_code
      assert_equal "lat", documents.fetch(RHODIUS).language
      assert_equal "non", documents.fetch(SAGA).language
      assert_equal "sme", documents.fetch(ABC).language
      assert_equal ["sme"], documents.fetch(ABC).metadata["languages"]
      assert_equal "nob", Adapter.primary_language(%w[mul nob non])
      assert_equal "mul", Adapter.primary_language(%w[mul und])
      assert_equal %w[lat heb], Adapter.language_codes({ "languages" => [{ "code" => "lat heb" }] })
    end

    def test_the_item_record_mines_the_axes
      meta = documents.fetch(ABC).metadata
      assert_equal "Kristianiast", meta["place"], "the print's own form, not the authority form"
      assert_equal "Norge - Oslo", meta["place_normalized"]
      assert_equal({ "not_before" => 1837, "not_after" => 1837, "raw" => "1837", "class" => "edition" }, meta["date"])
      assert_equal "Stockfleth, N.V. (Nils Vibe)", meta["author"]
      assert_equal %w[ABC-bøker Lesebøker Lærebøker], meta.dig("facets", "genre", "values")
      assert_equal "https://www.nb.no/items/URN:NBN:no-nb_digibok_2009020300033", meta["permalink"]
      assert_equal "machine-ocr", meta["text_nature"]
      assert_equal "publicdomain", meta["license"]
      assert_equal "tesseract 5.2.0", meta["ocr_software"], "the engine is per scan campaign"
      assert_equal "FineReader 12.0", documents.fetch(RHODIUS).metadata["ocr_software"]
      assert_equal 3, meta["page_count"]
      rhodius = documents.fetch(RHODIUS).metadata
      assert_equal "Christianiae", rhodius["place"]
      assert_equal "Rhodius, Ambrosius", rhodius["author"]
      assert_equal "Literis Michaelis Thomasonii", rhodius["publisher"]
      assert_equal "Reykjavík", documents.fetch(SAGA).metadata["place"]
    end

    def test_an_imprint_date_that_disagrees_with_the_catalogue_spans_both
      adapter = conformance_adapter
      meta = { "originInfo" => { "issued" => "1652", "issuedUntouched" => "1652" },
               "originInfoTypes" => [{ "eventType" => "publication", "issuedUntouched" => "MDCLVII [1657]" }] }
      assert_equal({ "not_before" => 1652, "not_after" => 1657, "raw" => "MDCLVII [1657] (catalogue: 1652)",
                     "class" => "edition" }, adapter.send(:date_envelope, meta))
    end

    def test_bracketed_places_unbracket_and_glosses_drop
      adapter = conformance_adapter
      assert_equal ["Christiania", nil], adapter.send(:places, { "geographic" => { "city" => "[Christiania]" } })
      assert_equal ["Lugduni Batavorum", nil],
                   adapter.send(:places, { "geographic" => { "city" => "Lugduni Batavorum [Leiden]" } })
      assert_equal ["Christianiæ", "Norge - Oslo"],
                   adapter.send(:places,
                                { "geographic" => { "placeString" => "Norge - Oslo", "city" => "Christianiæ" } })
    end

    def test_crawl_class_orders_the_cone
      assert_equal "non", Adapter.crawl_class(%w[nob mul non])
      assert_equal "greek", Adapter.crawl_class(%w[lat gre])
      assert_equal "sami", Adapter.crawl_class(%w[mul sme dan])
      assert_equal "lat", Adapter.crawl_class(%w[lat])
      assert_equal "pre1700", Adapter.crawl_class(%w[dan])
    end

    # -- discovery accounting ----------------------------------------------

    def test_partial_and_non_public_domain_items_skip_by_rule
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_includes skips.notes, "crawl incomplete: item #{EDDA_ID} (352 page(s) to go)"
      assert_includes skips.notes, "item #{NON_PD_ID}: not public domain (accessInfo) — never crawled"
      assert_equal 2, skips.skipped_by_rule
      assert skips.clean?
    end

    def test_a_directory_without_an_item_record_is_unrecognized
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], dir)
        FileUtils.mkdir_p(File.join(dir, "items", "deadbeef"))
        File.write(File.join(dir, "stray.txt"), "x")
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 2, skips.unrecognized
        assert_includes skips.notes, "item directory without an item record: items/deadbeef"
        assert_includes skips.notes, "non-corpus file: stray.txt"
      end
    end

    def test_a_ledgered_page_completes_its_item
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], dir)
        FileUtils.rm(File.join(dir, "items", SAGA_ID, "alto", "0003.xml.gz"))
        assert_equal [RHODIUS, ABC], conformance_adapter.discover(dir).map(&:id)
        File.write(File.join(dir, Adapter::LEDGER_FILE), JSON.generate({ "pages" => { SAGA_ID => ["0003"] } }))
        assert_equal [RHODIUS, SAGA, ABC], conformance_adapter.discover(dir).map(&:id)
        saga = conformance_adapter.parse(conformance_adapter.discover(dir).to_a[1])
        assert_equal ["0003"], saga.metadata["ledgered_pages"]
        assert_equal(%w[0001 0010], saga.map { |p| p.urn.split(":").last })
      end
    end

    # -- the census + the paced, resumable crawl (WebMock; delay 0) --------

    SEARCH = %r{\Ahttps://api\.nb\.no/catalog/v1/items\?}

    def fixture(*parts) = File.read(File.join(FIXTURES, "items", *parts), encoding: "UTF-8")

    def alto(id, tail) = Zlib.gunzip(File.binread(File.join(FIXTURES, "items", id, "alto", "#{tail}.xml.gz")))

    def stub_search(body = File.read(File.join(ROOT, "api", "search-cone.json")))
      stub_request(:get, SEARCH).to_return(status: 200, body: body)
    end

    def page_href(id, tail)
      urn = JSON.parse(fixture(id, "item.json")).dig("metadata", "identifiers", "urn")
      "https://api.nb.no/catalog/v1/metadata/#{id}/altos/#{urn}_#{tail}"
    end

    def stub_item(id, tails)
      stub_request(:get, format(Adapter::ITEM_URL, id)).to_return(status: 200, body: fixture(id, "item.json"))
      stub_request(:get, format(Adapter::ALTOS_URL, id)).to_return(status: 200, body: fixture(id, "altos.json"))
      tails.each { |tail| stub_request(:get, page_href(id, tail)).to_return(status: 200, body: alto(id, tail)) }
    end

    def test_the_census_reconciles_and_orders_the_crawl
      stub_search
      Dir.mktmpdir do |dir|
        report = quiet(items: []).fetch(dir)
        assert_match %r{census 4 item\(s\) / 458 page\(s\) by pageCount}, report.notes
        rows = File.readlines(File.join(dir, Adapter::CENSUS_TSV), chomp: true)
        assert_equal "id\turn\tyear\tlanguages\tpages\tclass", rows.first
        assert_equal [SAGA_ID, EDDA_ID, ABC_ID, RHODIUS_ID], rows.drop(1).map { |row| row.split("\t").first },
                     "non (oldest first) → Sámi → lat"
        assert_includes rows, "#{RHODIUS_ID}\tURN:NBN:no-nb_digibok_2026030928001\t1660\tlat\t4\tlat"
        assert_requested :get, SEARCH, times: 1
      end
    end

    def test_a_census_that_does_not_reconcile_aborts
      answer = JSON.parse(File.read(File.join(ROOT, "api", "search-cone.json")))
      answer["page"]["totalElements"] = 5
      stub_search(JSON.generate(answer))
      Dir.mktmpdir do |dir|
        error = assert_raises(Nabu::FetchError) { quiet.fetch(dir) }
        assert_match(/4 unique id\(s\) but the API counts 5/, error.message)
      end
    end

    def test_the_census_url_carries_the_cone
      url = Adapter.census_url(3)
      query = URI.decode_www_form(URI(url).query)
      assert_includes query, ["filter", "contentClasses:publicdomain"]
      assert_includes query, ["filter", "mediatype:bøker"]
      assert_includes query, ["filter", "year:[* TO 1699] OR languages:(non OR lat OR grc OR gre OR sme OR sma " \
                                        "OR smj OR smn OR sms OR sje OR sju OR smi)"]
      assert_includes query, %w[page 3]
    end

    def test_fetch_walks_an_item_and_writes_gzipped_alto
      stub_search
      stub_item(RHODIUS_ID, %w[C1 I1 I3 C3])
      Dir.mktmpdir do |dir|
        report = quiet(items: [RHODIUS_ID]).fetch(dir)
        assert_match %r{1/1 item\(s\) complete, 4/4 listed page\(s\) held \(\+6 file\(s\) this sync\)}, report.notes
        assert_equal alto(RHODIUS_ID, "I1"),
                     Zlib.gunzip(File.binread(File.join(dir, "items", RHODIUS_ID, "alto", "I1.xml.gz")))
        assert_equal File.binread(File.join(FIXTURES, "items", RHODIUS_ID, "alto", "I1.xml.gz")),
                     File.binread(File.join(dir, "items", RHODIUS_ID, "alto", "I1.xml.gz")), "byte-stable gzip"
        assert_equal [RHODIUS], Adapter.new.discover(dir).map(&:id)
      end
    end

    def test_fetch_resumes_at_the_file_grain_after_the_slice
      stub_search
      stub_item(RHODIUS_ID, %w[C1 I1 I3 C3])
      Dir.mktmpdir do |dir|
        first = quiet(items: [RHODIUS_ID], slice: 3).fetch(dir)
        assert_match(/\(\+3 file\(s\) this sync\); slice limit reached — resume next sync/, first.notes)
        assert_empty Adapter.new.discover(dir).to_a, "one of four pages: no document yet"
        second = quiet(items: [RHODIUS_ID]).fetch(dir)
        assert_match(/\(\+3 file\(s\) this sync\)\z/, second.notes)
        assert_requested :get, format(Adapter::ITEM_URL, RHODIUS_ID), times: 1
        assert_requested :get, page_href(RHODIUS_ID, "C1"), times: 1
        refute_equal first.sha, second.sha
      end
    end

    def test_fetch_ledgers_a_404_page_and_never_retries_it
      stub_search
      stub_item(RHODIUS_ID, %w[C1 I1 C3])
      stub_request(:get, page_href(RHODIUS_ID, "I3")).to_return(status: 404)
      Dir.mktmpdir do |dir|
        report = quiet(items: [RHODIUS_ID]).fetch(dir)
        assert_match(/1 page\(s\) ledgered/, report.notes)
        assert_equal({ RHODIUS_ID => ["I3"] }, JSON.parse(File.read(File.join(dir, Adapter::LEDGER_FILE)))["pages"])
        quiet(items: [RHODIUS_ID]).fetch(dir)
        assert_requested :get, page_href(RHODIUS_ID, "I3"), times: 1
        assert_equal [RHODIUS], Adapter.new.discover(dir).map(&:id)
      end
    end

    def test_an_item_no_longer_public_domain_is_ledgered_and_never_paged
      stub_search
      stub_request(:get, format(Adapter::ITEM_URL, RHODIUS_ID))
        .to_return(status: 200, body: fixture(NON_PD_ID, "item.json"))
      Dir.mktmpdir do |dir|
        report = quiet(items: [RHODIUS_ID]).fetch(dir)
        assert_match(/item\(s\) ledgered: 1 not-public-domain/, report.notes)
        assert_not_requested :get, format(Adapter::ALTOS_URL, RHODIUS_ID)
        assert_empty Adapter.new.discover(dir).to_a
      end
    end

    def test_a_held_record_is_rechecked_so_a_lost_ledger_never_pages_it
      stub_search
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "items", RHODIUS_ID))
        File.write(File.join(dir, "items", RHODIUS_ID, "item.json"), fixture(NON_PD_ID, "item.json"))
        quiet(items: [RHODIUS_ID]).fetch(dir)
        assert_not_requested :get, format(Adapter::ALTOS_URL, RHODIUS_ID)
        assert_equal({ RHODIUS_ID => "not-public-domain" },
                     JSON.parse(File.read(File.join(dir, Adapter::LEDGER_FILE)))["items"])
      end
    end

    def test_fetch_stops_cleanly_when_rate_limited
      stub_search
      stub_item(RHODIUS_ID, %w[C1])
      stub_request(:get, page_href(RHODIUS_ID, "I1")).to_return(status: 429)
      Dir.mktmpdir do |dir|
        report = quiet(items: [RHODIUS_ID]).fetch(dir)
        assert_match(/\(\+3 file\(s\) this sync\); rate limited — resume next sync/, report.notes)
      end
    end

    def test_a_transient_failure_retries_then_aborts_the_sync_resumably
      stub_search
      stub_item(RHODIUS_ID, %w[C1])
      stub_request(:get, page_href(RHODIUS_ID, "I1")).to_return(status: 503).then
                                                     .to_return(status: 200, body: alto(RHODIUS_ID, "I1"))
      stub_request(:get, page_href(RHODIUS_ID, "I3")).to_return(status: 503)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { quiet(items: [RHODIUS_ID]).fetch(dir) }
        assert File.file?(File.join(dir, "items", RHODIUS_ID, "alto", "I1.xml.gz")), "one 503 then 200: kept"
        assert_requested :get, page_href(RHODIUS_ID, "I3"), times: Adapter::RETRIES
      end
    end
  end
end
