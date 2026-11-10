# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "support/paced_crawl_conformance"
require "fileutils"
require "json"
require "tmpdir"

module Adapters
  # korpus16: Korpus 16, the 16th-century Slovene Protestant writers
  # (ZRC SAZU, fran.si/korpus16). Fixtures (retrieved 2026-11-05, whole
  # raw GETs at ~1 req/s): the portal index trimmed to five books' tiles
  # (each book tiles twice — the all-authors tab and its author tab), the
  # three portal pages (Info, Colofon, Bibliography — a rejected grain),
  # two COMPLETE books — Trubar's TM 1555 (7 pages, the last blank) and
  # TPs 1579 (8 pages) — and three PARTIAL ones (the 1584 Bible's pages 1
  # and 200, the first pages of TPs 1567 and TT 1581-82), which skip by
  # rule as crawls in progress.
  class Korpus16Test < Minitest::Test
    include AdapterConformance
    include PacedCrawlConformance

    FIXTURES = Nabu::TestSupport.fixtures("korpus16")
    Adapter = Nabu::Adapters::Korpus16
    PRAYER = "urn:nabu:korpus16:9"
    PSALM = "urn:nabu:korpus16:39"
    PAGE_URL_PATTERN = %r{\Ahttps://fran\.si/korpus16/Knjiga/(\d+)/[^?]+\?stran=(\d+)\z}

    def conformance_adapter = Adapter.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "korpus16"

    # The paced-crawl conformance drives the page lane through its real
    # wiring: the on-disk index lists one book per conformance id (the
    # real tile anchor, re-pointed), each id is that book's page 1 (the
    # sizing request), held = books/<id>/00001.html, and the script answers
    # over the stubbed reading pages. An :ok page is a real page 1 whose
    # pager says one page, so a stored id sizes its book to itself and the
    # universe stays exactly +ids+.
    def paced_crawl_engine(dir:, ids:, slice:, script:)
      write_index(dir, ids)
      stub_request(:get, PAGE_URL_PATTERN).to_return do |request|
        book = request.uri.path[%r{/Knjiga/(\d+)/}, 1]
        page = request.uri.query[/stran=(\d+)/, 1]
        case script.call(page == "1" ? book : "#{book}:#{page}")
        when :ok then { status: 200, body: one_page_book }
        when :denied then { status: 403, body: PacedCrawlConformance::PC_REFUSAL_BODY }
        when :empty then { status: 200, body: File.read(File.join(FIXTURES, "map", "about-Info.html")) }
        when :timeout then raise Net::ReadTimeout
        when :fatal then { status: 500, body: "" }
        end
      end
      quiet(slice: slice).page_crawl(dir)
    end

    def paced_crawl_hold!(dir, id)
      FileUtils.mkdir_p(File.join(dir, "books", id))
      File.write(File.join(dir, "books", id, "00001.html"), one_page_book)
    end

    def write_index(dir, ids)
      anchor = File.read(File.join(FIXTURES, "map", "korpus16.html"))[%r{<a href="/korpus16/Knjiga/9/[^>]*>}]
      tiles = ids.map { |id| "#{anchor.sub('/Knjiga/9/', "/Knjiga/#{id}/")}tile</a>" }
      FileUtils.mkdir_p(File.join(dir, "map"))
      File.write(File.join(dir, "map", "korpus16.html"), "<html><body>#{tiles.join("\n")}</body></html>")
    end

    def one_page_book = page_html(9, 1).sub('max="7"', 'max="1"')

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).to_h { |ref| [ref.id, conformance_adapter.parse(ref)] }
    end

    def quiet(**) = Adapter.new(delay: 0, backoff: 0, **)

    # -- documents ---------------------------------------------------------

    def test_discovers_the_complete_books_in_upstream_id_order
      assert_equal [PRAYER, PSALM], documents.keys
    end

    def test_one_passage_per_page_with_text_cited_by_page_index
      prayer = documents.fetch(PRAYER)
      assert_equal "sl", prayer.language
      assert_equal(%w[1 2 3 4 5 6], prayer.map { |p| p.urn.delete_prefix("#{PRAYER}:") })
      assert_equal [7], prayer.metadata["blank_pages"], "a page with no body text mints nothing"
      assert_equal 7, prayer.metadata["page_count"]
      assert prayer.first.text.start_with?("ENA MOLITOV TIH KERSzhenikou"), prayer.first.text[0, 40]
      assert_equal 8, documents.fetch(PSALM).size
    end

    def test_forme_work_rides_the_passage_annotations
      page = documents.fetch(PSALM).find { |p| p.urn.end_with?(":2") }
      assert_equal "Dobru", page.annotations["catchword"]
      refute_includes page.text, "Dobru"
    end

    def test_the_book_header_mines_the_axes
      meta = documents.fetch(PRAYER).metadata
      assert_equal "TM 1555", meta["siglum"]
      assert_equal "Primož Trubar", meta["author"]
      assert_nil meta["author_role"]
      assert_equal "Tübingen", meta["place"]
      assert_equal "Tübingen, 1555", meta["imprint"]
      assert_equal({ "not_before" => 1555, "not_after" => 1555, "raw" => "Tübingen, 1555", "class" => "edition" },
                   meta["date"])
      assert_equal "https://fran.si/korpus16/Knjiga/9/molitev_krscenikov", meta["permalink"]
      assert_equal "double-keyed transcription", meta["text_nature"]
      assert_equal "ENA MOLITOV TIH KERSZHENIKOU", documents.fetch(PRAYER).title
    end

    def test_editors_and_two_year_sigla_parse_from_real_headers
      adapter = conformance_adapter
      hymnal = adapter.book_metadata(page_html(25, 1), book_id: "25", slug: "eni_psalmi")
      assert_equal ["Primož Trubar", "editor"], [hymnal["author"], hymnal["author_role"]]
      assert_equal "Primož Trubar (ur.)", hymnal["statement_of_responsibility"]
      nt = adapter.book_metadata(page_html(43, 1), book_id: "43", slug: "novi_testament")
      assert_equal({ "not_before" => 1581, "not_after" => 1582, "raw" => "Tübingen, 1581 (siglum TT 1581-82)",
                     "class" => "edition" }, nt["date"])
      bible = adapter.book_metadata(page_html(58, 1), book_id: "58", slug: "biblia")
      assert_match(/Svetopisemska družba Slovenije/, bible["transcription_credit"])
      assert_nil nt["transcription_credit"]
    end

    # The *P 1563 hymnal's header, verbatim (book 17's page 1).
    def test_the_klombner_juricic_hymnal_names_both_editors
      assert_equal ["Matija Klombner; Jurij Juričič", "editor"],
                   Adapter.people("Matija Klombner in Jurij Juričič (ur.)")
      assert_equal ["Jurij Dalmatin", nil], Adapter.people("Jurij Dalmatin")
    end

    def page_html(book, page)
      File.read(File.join(FIXTURES, "books", book.to_s, format("%05d.html", page)), encoding: "UTF-8")
    end

    # -- discovery accounting ----------------------------------------------

    def test_partial_books_and_portal_pages_skip_by_rule
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_includes skips.notes, "crawl incomplete: book 58 DB 1584 (1563 page(s) to go)"
      assert_includes skips.notes, "crawl incomplete: book 25 TPs 1567 (30 page(s) to go)"
      assert_includes skips.notes, "crawl incomplete: book 43 TT 1581-82 (1135 page(s) to go)"
      assert_includes skips.notes, "portal page map/about-Colofon.html: front matter, not corpus text"
      assert_equal 6, skips.skipped_by_rule, "three partial books + three portal pages"
      assert skips.clean?
    end

    def test_a_book_directory_the_index_does_not_list_is_unrecognized
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], dir)
        FileUtils.mkdir_p(File.join(dir, "books", "999"))
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        assert_includes skips.notes, "book directory not in the index: books/999"
      end
    end

    def test_a_ledgered_page_completes_its_book
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], dir)
        FileUtils.rm(File.join(dir, "books", "9", "00004.html"))
        assert_equal [PSALM], conformance_adapter.discover(dir).map(&:id)
        File.write(File.join(dir, Adapter::LEDGER_FILE), JSON.generate({ "pages" => { "9" => [4] } }))
        assert_equal [PRAYER, PSALM], conformance_adapter.discover(dir).map(&:id)
        doc = conformance_adapter.parse(conformance_adapter.discover(dir).first)
        assert_equal [4], doc.metadata["ledgered_pages"]
        assert_equal(%w[1 2 3 5 6], doc.map { |p| p.urn.split(":").last })
      end
    end

    # -- the paced, resumable crawl (WebMock; delay 0) ---------------------

    def stub_portal
      stub_request(:get, Adapter::INDEX_URL)
        .to_return(status: 200, body: File.read(File.join(FIXTURES, "map", "korpus16.html")))
      Adapter::PORTAL_PAGES.each do |name|
        stub_request(:get, format(Adapter::PORTAL_URL, name))
          .to_return(status: 200, body: File.read(File.join(FIXTURES, "map", "about-#{name}.html")))
      end
    end

    def page_url(book, slug, page) = format(Adapter::PAGE_URL, id: book, slug: slug, page: page)

    def stub_prayer(pages = 1..7)
      pages.each do |page|
        stub_request(:get, page_url(9, "molitev_krscenikov", page)).to_return(status: 200, body: page_html(9, page))
      end
    end

    def test_fetch_walks_a_book_and_writes_raw_pages
      stub_portal
      stub_prayer
      Dir.mktmpdir do |dir|
        report = quiet(books: ["9"]).fetch(dir)
        assert_match %r{crawl at 7/7 page\(s\); 1/1 book\(s\) complete \(\+7 page\(s\) this sync\)}, report.notes
        assert_match %r{upstream advertises 45 books / 12,945 pages; the index lists 5 book\(s\)}, report.notes
        assert_equal page_html(9, 3), File.read(File.join(dir, "books", "9", "00003.html"), encoding: "UTF-8")
        assert_equal [PRAYER], Adapter.new.discover(dir).map(&:id)
        assert File.file?(File.join(dir, "map", "about-Colofon.html")), "the license page is kept each sync"
      end
    end

    def test_fetch_resumes_at_the_file_grain_after_the_slice
      stub_portal
      stub_prayer
      Dir.mktmpdir do |dir|
        first = quiet(books: ["9"], slice: 3).fetch(dir)
        assert_match(/\(\+3 page\(s\) this sync\); slice limit reached — resume next sync/, first.notes)
        assert_empty Adapter.new.discover(dir).to_a, "three of seven pages: no document yet"
        second = quiet(books: ["9"]).fetch(dir)
        assert_match %r{crawl at 7/7 page\(s\); 1/1 book\(s\) complete \(\+4 page\(s\) this sync\)}, second.notes
        assert_requested :get, page_url(9, "molitev_krscenikov", 1), times: 1
        refute_equal first.sha, second.sha
      end
    end

    def test_fetch_ledgers_a_404_and_a_non_reading_page
      stub_portal
      stub_prayer([1, 2, 3, 5, 7])
      stub_request(:get, page_url(9, "molitev_krscenikov", 4)).to_return(status: 404)
      stub_request(:get, page_url(9, "molitev_krscenikov", 6))
        .to_return(status: 200, body: File.read(File.join(FIXTURES, "map", "about-Info.html")))
      Dir.mktmpdir do |dir|
        report = quiet(books: ["9"]).fetch(dir)
        assert_match(/2 page\(s\) ledgered/, report.notes)
        ledger = JSON.parse(File.read(File.join(dir, Adapter::LEDGER_FILE)))
        assert_equal({ "9" => [4] }, ledger["pages"], "the 404 rides the legacy refused section")
        assert_equal ["9:6"], ledger["not-reading"], "a 200 that is no reading page is its own class"
        quiet(books: ["9"]).fetch(dir)
        assert_requested :get, page_url(9, "molitev_krscenikov", 4), times: 1
        assert_requested :get, page_url(9, "molitev_krscenikov", 6), times: 1
        assert_equal [PRAYER], Adapter.new.discover(dir).map(&:id), "both ledgered pages complete the book"
      end
    end

    def test_a_timed_out_page_is_retried_then_ledgered_stuck
      stub_portal
      stub_prayer([1, 2, 4, 5, 6, 7])
      stub_request(:get, page_url(9, "molitev_krscenikov", 3)).to_raise(Net::ReadTimeout)
      Dir.mktmpdir do |dir|
        report = quiet(books: ["9"]).fetch(dir)
        assert_requested :get, page_url(9, "molitev_krscenikov", 3), times: Adapter::PAGE_CRAWL.timeout_attempts
        assert_equal ["9:3"], JSON.parse(File.read(File.join(dir, Adapter::LEDGER_FILE)))["timeout-stuck"]
        assert_match(/\(\+6 page\(s\) this sync\)/, report.notes)
      end
    end

    # A ledger as the hand-rolled crawl wrote it (refused books, refused
    # pages per book) reads through the lane's codec and writes back with
    # every entry intact, the new classes beside it.
    LEGACY_LEDGER = { "books" => %w[17 4], "pages" => { "58" => [200, 7], "9" => [4] } }.freeze

    def test_a_legacy_ledger_round_trips_through_the_codec
      codec = Adapter::LedgerCodec
      classes = codec.load(LEGACY_LEDGER)
      assert_equal Set["17", "4", "58:7", "58:200", "9:4"], classes.fetch("refused")
      dumped = codec.dump(Adapter::PAGE_CRAWL.class_names.to_h { |klass| [klass, classes.fetch(klass, Set.new)] },
                          LEGACY_LEDGER)
      assert_equal({ "books" => %w[4 17], "pages" => { "9" => [4], "58" => [7, 200] },
                     "not-reading" => [], "timeout-stuck" => [] }, dumped)
      assert_equal classes.fetch("refused"), codec.load(JSON.parse(JSON.generate(dumped))).fetch("refused")
    end

    def test_a_slice_over_a_legacy_ledger_keeps_every_entry
      stub_portal
      stub_prayer
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, Adapter::LEDGER_FILE), JSON.generate(LEGACY_LEDGER.merge("pages" => { "9" => [4] })))
        quiet(books: ["9"]).fetch(dir)
        on_disk = JSON.parse(File.read(File.join(dir, Adapter::LEDGER_FILE)))
        assert_equal [%w[4 17], { "9" => [4] }], on_disk.values_at("books", "pages")
        assert_equal "yield", on_disk.dig("last_slice", "classification")
        assert_not_requested :get, page_url(9, "molitev_krscenikov", 4)
      end
    end

    def test_the_chain_seam_names_the_one_page_lane
      lanes = quiet.paced_crawls(Dir.mktmpdir)
      assert_equal ["pages"], lanes.keys
      assert_kind_of Nabu::PacedCrawl::Engine, lanes.fetch("pages")
      assert_equal Adapter::LedgerCodec, lanes.fetch("pages").spec.codec
    end

    def test_a_refused_page_one_ledgers_the_whole_book
      stub_portal
      stub_request(:get, page_url(9, "molitev_krscenikov", 1)).to_return(status: 404)
      Dir.mktmpdir do |dir|
        report = quiet(books: ["9"]).fetch(dir)
        assert_match(/1 book\(s\) refused/, report.notes)
        ledger = JSON.parse(File.read(File.join(dir, Adapter::LEDGER_FILE)))
        assert_equal [["9"], {}], ledger.values_at("books", "pages")
        quiet(books: ["9"]).fetch(dir)
        assert_requested :get, page_url(9, "molitev_krscenikov", 1), times: 1
        FileUtils.mkdir_p(File.join(dir, "books", "9"))
        assert_includes Adapter.new.discovery_skips(dir).notes, "book 9: page 1 refused upstream (ledgered)"
      end
    end

    def test_fetch_stops_cleanly_when_rate_limited
      stub_portal
      stub_prayer([1, 2])
      stub_request(:get, page_url(9, "molitev_krscenikov", 3)).to_return(status: 429)
      Dir.mktmpdir do |dir|
        report = quiet(books: ["9"]).fetch(dir)
        assert_match(/\(\+2 page\(s\) this sync\); rate limited — resume next sync/, report.notes)
        assert_match(/CLEAN STOP at 9:3: HTTP 429/, report.notes)
        on_disk = JSON.parse(File.read(File.join(dir, Adapter::LEDGER_FILE)))
        assert_equal [[], {}], on_disk.values_at("books", "pages"), "a 429 is never ledgered"
        stub_prayer([3, 4, 5, 6, 7])
        quiet(books: ["9"]).fetch(dir)
        assert_equal [PRAYER], Adapter.new.discover(dir).map(&:id), "the next sync resumes at the halted page"
      end
    end

    def test_a_transient_failure_retries_then_aborts_the_sync_resumably
      stub_portal
      stub_prayer([1])
      stub_request(:get, page_url(9, "molitev_krscenikov", 2)).to_return(status: 503).then
                                                              .to_return(status: 200, body: page_html(9, 2))
      stub_request(:get, page_url(9, "molitev_krscenikov", 3)).to_return(status: 503)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { quiet(books: ["9"]).fetch(dir) }
        assert File.file?(File.join(dir, "books", "9", "00002.html")), "one 503 then 200: kept"
        assert_requested :get, page_url(9, "molitev_krscenikov", 3), times: Adapter::RETRIES
      end
    end

    def test_an_index_without_books_aborts
      stub_request(:get, Adapter::INDEX_URL).to_return(status: 200, body: "<html><body></body></html>")
      Dir.mktmpdir do |dir|
        error = assert_raises(Nabu::FetchError) { quiet.fetch(dir) }
        assert_match(/no books/, error.message)
      end
    end
  end
end
