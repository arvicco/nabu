# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"

module Adapters
  # ndl-kotenseki (P109-2, phase 1): the NDL 次世代デジタルライブ
  # ラリー classical-materials OCR mass, crawled over the granted bulk
  # route. Fixture: a real fulltext-json capture for PID 2532153
  # (玉篇 巻中 — a 1605 Yupian print's classical OCR), trimmed to its
  # first 6 koma (2 empty cover koma + the title koma + text koma),
  # and the census.tsv row the fetch derives from the NDL open
  # bibliographic dataset.
  class NdlKotensekiTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("ndl-kotenseki")

    def conformance_adapter = Nabu::Adapters::NdlKotenseki.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "ndl-kotenseki"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pid) = documents.find { |d| d.urn.end_with?(":#{pid}") } || flunk("#{pid} missing")

    def test_discovers_one_document_per_crawled_book
      assert_equal %w[urn:nabu:ndl-kotenseki:2532153 urn:nabu:ndl-kotenseki:2537051
                      urn:nabu:ndl-kotenseki:2541107],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    # -- The NDL Search bib join (bib/<pid>.xml sidecars) -------------------

    def test_bib_ndc_joins_metadata_and_the_ndc_facet
      meta = doc(2_532_153).metadata
      assert_equal ["813.2"], meta["ndc"]
      assert_equal({ "values" => ["813.2"] }, meta.dig("facets", "ndc"))
      assert_equal [{ "category" => "R100000002", "bib_id" => "000003284459" }], meta.dig("ndl_bib", "records"),
                   "the record provenance rides beside the join"
      assert_equal [1605, 1605, "[慶長10(1605)]"], meta["date"].values_at("not_before", "not_after", "raw"),
                   "a typed census date stays the date — the bib record never overrides it"
    end

    def test_bib_creators_ride_metadata_and_join_the_author_facet
      meta = doc(2_541_107).metadata
      assert_equal({ "name" => "歌川, 広重 1世", "life" => "1797-1858", "born" => 1797, "died" => 1858,
                     "reading" => "ウタガワ, ヒロシゲ 1セイ, 1797-1858",
                     "authority" => "http://id.ndl.go.jp/auth/entity/00272450" }, meta["creators"].last)
      assert_equal({ "values" => ["夷福山人", "広重", "歌川, 広重 1世"] }, meta.dig("facets", "author"),
                   "the authority forms join the census names, deduplicated, life-years never in the value")
      assert_nil meta["date"], "neither the census nor the record carries a year"
    end

    def test_bib_issued_year_dates_a_census_undated_book_labeled_as_the_records_claim
      meta = doc(2_537_051).metadata
      assert_equal "寛政7序", meta["pub_date"], "the census prose rides verbatim as before"
      assert_equal({ "not_before" => 1795, "not_after" => 1795,
                     "raw" => "NDL Search record (pid 2537051): 寛政7 [1795] 序" }, meta["date"])
      assert_nil meta["date"]["class"], "the print's own date — the artifact class, labeled by its raw"
    end

    def test_a_book_without_a_bib_sidecar_parses_as_before
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "books"))
        FileUtils.cp(File.join(FIXTURES, "books", "2541107.json"), File.join(dir, "books"))
        FileUtils.cp(File.join(FIXTURES, "census.tsv"), dir)
        adapter = conformance_adapter
        meta = adapter.parse(adapter.discover(dir).first).metadata
        assert_nil meta["creators"]
        assert_nil meta["ndl_bib"]
        assert_equal({ "values" => %w[夷福山人 広重] }, meta.dig("facets", "author"))
      end
    end

    def test_bib_sidecars_are_declared_materializations_not_strays
      assert_includes Nabu::Adapters::NdlKotenseki.materialized_paths, "bib"
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "bib"))
        File.write(File.join(dir, "bib", "2532153.xml"), "<ndl-bib/>")
        File.write(File.join(dir, ".ndl-bib.json"), "{}")
        assert_equal 0, conformance_adapter.discovery_skips(dir).unrecognized
      end
    end

    def test_koma_contents_become_passages_empty_koma_skipped
      d = doc(2_532_153)
      assert_equal "jpn", d.language
      assert_equal %w[3 4 5 6], d.passages.map { |p| p.annotations["koma"] },
                   "cover koma with empty OCR contents mint nothing"
      assert_equal "#{d.urn}:3", d.passages.first.urn
      assert_equal "玉篇巻中本", d.passages.first.text
    end

    def test_census_bibliography_joins_the_document
      d = doc(2_532_153)
      assert_equal "玉篇 巻中", d.title
      meta = d.metadata
      assert_equal "machine-ocr", meta["text_nature"], "the OCR-nature label rides every document"
      assert_equal "https://dl.ndl.go.jp/pid/2532153", meta["permalink"],
                   "per-item NDL provenance, as promised in the grant thread"
      assert_equal "[慶長10(1605)]", meta["pub_date"], "the prose date rides verbatim"
      assert_equal({ "values" => ["古典籍資料（貴重書等）-その他"] }, meta.dig("facets", "collection"),
                   "collection is ||-multi like subject — the values shape")
      assert_equal({ "values" => %w[倭玉篇 辞書] }, meta.dig("facets", "subject"),
                   "the ||-separated 件名 values each facet")
    end

    # シリーズタイトル → metadata + the series facet; 容量・大きさ → metadata
    # only; the 著者 string keeps its raw form beside a per-part split of
    # the trailing role token.
    def test_series_extent_and_author_roles_join_the_document
      meta = doc(2_541_107).metadata
      assert_equal "赤本昔はなし", meta["series"]
      assert_equal({ "values" => ["赤本昔はなし"] }, meta.dig("facets", "series"))
      assert_equal "1冊 ; 12.2cm", meta["extent"], "the extent rides verbatim, unfaceted"
      assert_equal "夷福山人 作||広重 画", meta["author"], "the raw string is kept"
      assert_equal [{ "name" => "夷福山人", "role" => "作" }, { "name" => "広重", "role" => "画" }],
                   meta["authors"]
      assert_equal(["夷福山人", "広重", "歌川, 広重 1世"], meta.dig("facets", "author", "values"),
                   "the census names first; the bib record's authority form joins (the bib-join tests)")
      assert_equal "1冊 ; 31cm", doc(2_532_153).metadata["extent"]
      assert_nil doc(2_532_153).metadata["authors"], "an empty 著者 claims no person"
    end

    def test_author_role_split_is_conservative
      split = Nabu::Adapters::NdlKotenseki.method(:author_part)
      assert_equal({ "name" => "藤原基経", "role" => "編" }, split.call("藤原基経 編"))
      assert_equal({ "name" => "[藤田幽谷]", "role" => "[著]" }, split.call("[藤田幽谷] [著]"),
                   "the cataloguer's supplied-role bracket rides verbatim")
      assert_equal({ "name" => "(梁) 蕭統", "role" => "撰" }, split.call("(梁) 蕭統 撰"))
      assert_equal({ "name" => "(唐) 李善 等注" }, split.call("(唐) 李善 等注"),
                   "an et-al. tail is not a single role token — the name stays whole")
      assert_equal({ "name" => "宋黄庭堅撰" }, split.call("宋黄庭堅撰"), "no whitespace, no split")
      assert_equal({ "name" => "戸田茂睡" }, split.call("戸田茂睡"))
    end

    # A census.tsv derived before a column joined CENSUS_COLUMNS re-derives
    # from the held xlsx at fetch; a current one is left alone.
    def test_a_stale_census_header_re_derives_at_fetch
      adapter = quiet_adapter
      derived = []
      adapter.define_singleton_method(:derive_census!) { |_xlsx, tsv| derived << tsv }
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "dataset_202602_k_internet.xlsx"), "")
        File.write(File.join(dir, "census.tsv"), "pid\ttitle\n")
        adapter.send(:ensure_census!, dir, nil)
        assert_equal 1, derived.size, "the pre-series header re-derives"
        File.write(File.join(dir, "census.tsv"), "#{Nabu::Adapters::NdlKotenseki::CENSUS_HEADER}\n")
        adapter.send(:ensure_census!, dir, nil)
        assert_equal 1, derived.size, "a current header is never re-derived"
      end
    end

    def test_crawl_slice_tallies_denied_pids_into_the_ledger
      adapter = conformance_adapter
      def adapter.fetch_book!(_workdir, pid) = pid == "1" ? :denied : :empty
      ledger = { "denied" => [], "empty" => [] }
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "census.tsv"), "pid\ttitle\n")
        crawled, denied = adapter.send(:crawl_slice!, dir, %w[1 2], ledger, nil)
        assert_equal [0, 2], [crawled, denied],
                     "each refusal counts ONCE (the first live slice died on a " \
                     "denied-arm arithmetic bug)"
        assert_equal ["1"], ledger["denied"]
        assert_equal ["2"], ledger["empty"]
      end
    end

    # -- The timeout-wedge fix (2026-10-11): a book that hangs on Net::ReadTimeout wedged the resumable
    # crawl (every resumed slice re-hit the same two PIDs and died). A
    # book timing out TIMEOUT_ATTEMPTS times in one slice is ledgered
    # under its own reason and the slice moves on.

    BOOK = "https://lab.ndl.go.jp/dl/api/book/fulltext-json/%s"

    def quiet_adapter(slice: 400) = Nabu::Adapters::NdlKotenseki.new(delay: 0, slice: slice, timeout_backoff: 0)

    def fresh_ledger = { "denied" => [], "empty" => [], "timeout-stuck" => [] }

    def test_a_book_timing_out_repeatedly_is_ledgered_stuck_and_the_slice_continues
      stub_request(:get, format(BOOK, "1")).to_return(status: 403, body: "This PID is not allowed")
      stuck = stub_request(:get, format(BOOK, "2")).to_raise(Net::ReadTimeout)
      stub_request(:get, format(BOOK, "3")).to_return(status: 200, body: '{"list":[{"page":1,"contents":"x"}]}')
      ledger = fresh_ledger
      Dir.mktmpdir do |dir|
        crawled, denied, stuck_pids = quiet_adapter.send(:crawl_slice!, dir, %w[1 2 3], ledger, nil)
        assert_requested stuck, times: Nabu::Adapters::NdlKotenseki::TIMEOUT_ATTEMPTS
        assert_equal 3, Nabu::Adapters::NdlKotenseki::TIMEOUT_ATTEMPTS
        assert_equal [1, 1, ["2"]], [crawled, denied, stuck_pids]
        assert File.file?(File.join(dir, "books", "3.json")), "the slice advanced past the hanging book"
        assert_equal ["1"], ledger["denied"], "a 403 stays a denial"
        assert_equal ["2"], ledger["timeout-stuck"], "the hang is ledgered under its own reason, not as a 403"
        on_disk = JSON.parse(File.read(File.join(dir, ".ndl-crawl.json")))
        assert_equal({ "denied" => ["1"], "empty" => [], "timeout-stuck" => ["2"] }, on_disk)
      end
    end

    def test_a_timeout_that_recovers_within_the_slice_is_crawled_not_ledgered
      stub_request(:get, format(BOOK, "2"))
        .to_raise(Net::ReadTimeout).then
        .to_return(status: 200, body: '{"list":[{"page":1,"contents":"x"}]}')
      ledger = fresh_ledger
      Dir.mktmpdir do |dir|
        crawled, denied, stuck_pids = quiet_adapter.send(:crawl_slice!, dir, %w[2], ledger, nil)
        assert_equal [1, 0, []], [crawled, denied, stuck_pids]
        assert_empty ledger["timeout-stuck"]
      end
    end

    def test_a_non_timeout_transport_failure_stays_fatal
      stub_request(:get, format(BOOK, "2")).to_return(status: 500)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { quiet_adapter.send(:crawl_slice!, dir, %w[2], fresh_ledger, nil) }
      end
    end

    def test_a_stuck_ledgered_book_is_skipped_on_resume
      adapter = quiet_adapter
      asked = []
      adapter.define_singleton_method(:fetch_book!) do |_workdir, pid|
        asked << pid
        :empty
      end
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".ndl-crawl.json"),
                   JSON.generate({ "denied" => ["1"], "empty" => [], "timeout-stuck" => ["2"] }))
        ledger = adapter.send(:read_ledger, dir)
        adapter.send(:crawl_slice!, dir, %w[1 2 3], ledger, nil)
        assert_equal ["3"], asked, "neither the 403 nor the stuck book is re-hit"
        assert_equal ["2"], ledger["timeout-stuck"]
        refute_includes ledger["denied"], "2"
      end
    end

    def test_a_legacy_ledger_without_the_stuck_class_reads_cleanly
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".ndl-crawl.json"), JSON.generate({ "denied" => ["1"], "empty" => ["4"] }))
        assert_equal({ "denied" => ["1"], "empty" => ["4"], "timeout-stuck" => [] },
                     quiet_adapter.send(:read_ledger, dir))
      end
    end

    def test_crawl_sha_is_unchanged_by_an_empty_stuck_class
      adapter = quiet_adapter
      Dir.mktmpdir do |dir|
        legacy = Digest::SHA256.hexdigest(JSON.generate(["", ["9"], ["1"], []]))
        assert_equal legacy, adapter.send(:crawl_sha, dir, ["9"], { "denied" => ["1"], "empty" => [] }),
                     "a pre-I-9 crawl state keeps its identity (no re-parse churn)"
        refute_equal legacy, adapter.send(:crawl_sha, dir, ["9"],
                                          { "denied" => ["1"], "empty" => [], "timeout-stuck" => ["2"] })
      end
    end

    def test_fetch_notes_name_the_stuck_books
      stub_request(:get, format(BOOK, "2546843")).to_raise(Net::ReadTimeout)
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "dataset_202602_k_internet.xlsx"), "")
        File.write(File.join(dir, "census.tsv"),
                   "#{Nabu::Adapters::NdlKotenseki::CENSUS_HEADER}\n2546843\tx\n")
        report = quiet_adapter.fetch(dir)
        assert_match(/1 stuck on timeout \(2546843\)/, report.notes)
      end
    end

    # -- The paced bib crawl: held PIDs without a sidecar, oldest first, in
    # SRU batches; a PID the answer does not link is ledgered "missing".

    SRU = %r{\Ahttps://ndlsearch\.ndl\.go\.jp/api/sru\?}
    SRU_BODY = File.read(File.join(FIXTURES, "sru", "searchRetrieve-3.xml"))
    BIB_PIDS = %w[2532153 2537051 2541107].freeze

    def bib_adapter(batch: 50, slice: 100)
      Nabu::Adapters::NdlKotenseki.new(delay: 0, timeout_backoff: 0, bib_batch: batch, bib_slice: slice)
    end

    def held_workdir(dir, pids)
      FileUtils.mkdir_p(File.join(dir, "books"))
      pids.each { |pid| File.write(File.join(dir, "books", "#{pid}.json"), '{"list":[]}') }
      dir
    end

    def queried_pids(request)
      URI.decode_www_form_component(request.uri.query[/query=([^&]*)/, 1])
         .scan(%r{pid/(\d+)}).flatten
    end

    def test_bib_crawl_writes_one_sidecar_per_linked_pid_and_ledgers_the_rest
      stub = stub_request(:get, SRU).to_return(status: 200, body: SRU_BODY)
      Dir.mktmpdir do |dir|
        held_workdir(dir, [*BIB_PIDS, "9999999"])
        counts = bib_adapter.send(:crawl_bib_slice!, dir, progress: nil)
        assert_requested stub, times: 1
        assert_equal({ fetched: 3, missing: 1, denied: 0, stuck: 0, batches: 1 }, counts)
        BIB_PIDS.each { |pid| assert File.file?(File.join(dir, "bib", "#{pid}.xml")), pid }
        assert_equal File.read(File.join(FIXTURES, "bib", "2532153.xml")),
                     File.read(File.join(dir, "bib", "2532153.xml")), "the fixture sidecar IS the crawl's shape"
        ledger = JSON.parse(File.read(File.join(dir, ".ndl-bib.json")))
        assert_equal({ "missing" => ["9999999"], "denied" => [], "timeout-stuck" => [] }, ledger)

        # incremental: held sidecars and ledgered PIDs never re-fetch
        assert_equal 0, bib_adapter.send(:crawl_bib_slice!, dir, progress: nil)[:batches]
        assert_requested stub, times: 1
      end
    end

    def test_bib_crawl_batches_oldest_pid_first_and_stops_at_the_slice
      asked = []
      stub_request(:get, SRU).to_return do |request|
        asked << queried_pids(request)
        { status: 200, body: SRU_BODY }
      end
      Dir.mktmpdir do |dir|
        held_workdir(dir, %w[2541107 2537051 2532153 10])
        counts = bib_adapter(batch: 2, slice: 1).send(:crawl_bib_slice!, dir, progress: nil)
        assert_equal [%w[10 2532153]], asked, "numeric order, one batch of two, then the slice ends"
        assert_equal 1, counts[:batches]
        refute File.file?(File.join(dir, "bib", "2537051.xml")), "the next slice's work waits"
      end
    end

    def test_a_partial_answer_pages_through_next_record_position
      records = SRU_BODY[%r{<records>.*</records>}m]
      first, *rest = records.scan(%r{<record>.*?</record>}m)
      page1 = SRU_BODY.sub(records, "<records>#{first}</records><nextRecordPosition>2</nextRecordPosition>")
      page2 = SRU_BODY.sub(records, "<records>#{rest.join}</records>")
      stub_request(:get, SRU).with(query: hash_including("startRecord" => "1")).to_return(status: 200, body: page1)
      stub_request(:get, SRU).with(query: hash_including("startRecord" => "2")).to_return(status: 200, body: page2)
      Dir.mktmpdir do |dir|
        held_workdir(dir, BIB_PIDS)
        assert_equal 3, bib_adapter.send(:crawl_bib_slice!, dir, progress: nil)[:fetched]
      end
    end

    def test_a_refused_batch_is_ledgered_denied_and_a_server_error_stays_fatal
      stub_request(:get, SRU).to_return(status: 403, body: "Forbidden")
      Dir.mktmpdir do |dir|
        held_workdir(dir, BIB_PIDS)
        assert_equal 3, bib_adapter.send(:crawl_bib_slice!, dir, progress: nil)[:denied]
        assert_equal BIB_PIDS, JSON.parse(File.read(File.join(dir, ".ndl-bib.json")))["denied"]
      end
      stub_request(:get, SRU).to_return(status: 500)
      Dir.mktmpdir do |dir|
        held_workdir(dir, BIB_PIDS)
        assert_raises(Nabu::FetchError) { bib_adapter.send(:crawl_bib_slice!, dir, progress: nil) }
        assert File.file?(File.join(dir, ".ndl-bib.json")), "the ledger is written even when the slice dies"
      end
    end

    def test_a_batch_timing_out_repeatedly_is_ledgered_stuck_and_the_slice_continues
      stub_request(:get, SRU).to_raise(Net::ReadTimeout).times(Nabu::Adapters::NdlKotenseki::TIMEOUT_ATTEMPTS)
                             .then.to_return(status: 200, body: SRU_BODY)
      Dir.mktmpdir do |dir|
        held_workdir(dir, %w[10 2532153])
        counts = bib_adapter(batch: 1).send(:crawl_bib_slice!, dir, progress: nil)
        assert_equal({ fetched: 1, missing: 0, denied: 0, stuck: 1, batches: 2 }, counts)
        assert_equal ["10"], JSON.parse(File.read(File.join(dir, ".ndl-bib.json")))["timeout-stuck"]
      end
    end

    def test_fetch_runs_the_bib_slice_after_the_book_slice_and_reports_it
      stub_request(:get, SRU).to_return(status: 200, body: SRU_BODY)
      Dir.mktmpdir do |dir|
        held_workdir(dir, BIB_PIDS)
        File.write(File.join(dir, "dataset_202602_k_internet.xlsx"), "")
        File.write(File.join(dir, "census.tsv"), "#{Nabu::Adapters::NdlKotenseki::CENSUS_HEADER}\n")
        report = bib_adapter.fetch(dir)
        assert_includes report.notes,
                        "bib records at 3/3 held book(s) (+3 this sync, 0 missing, 0 refused, 0 stuck; 1 batch(es))"
      end
    end

    def test_crawl_sha_moves_with_bib_state_only_when_there_is_some
      adapter = quiet_adapter
      Dir.mktmpdir do |dir|
        ledger = { "denied" => ["1"], "empty" => [] }
        bare = adapter.send(:crawl_sha, dir, ["9"], ledger)
        FileUtils.mkdir_p(File.join(dir, "bib"))
        assert_equal bare, adapter.send(:crawl_sha, dir, ["9"], ledger), "an empty bib dir is no state"
        File.write(File.join(dir, "bib", "9.xml"), "<ndl-bib/>")
        refute_equal bare, adapter.send(:crawl_sha, dir, ["9"], ledger)
      end
    end

    # The prose 出版日 nengō (owner-ruled 2026-10-20): where neither the
    # census W3CDTF nor the bib record types a year, the census prose era
    # date converts through the shared table (config/eras.yml) — real
    # census values. Typed years always win; Chinese print-era homonyms
    # (Ming 正徳 imprints share the collection) ride unparsed.
    def test_a_prose_nengo_dates_a_book_neither_typed_source_dates
      era = Nabu::Adapters::NdlKotenseki.method(:era_date_envelope)
      assert_equal({ "not_before" => 1792, "not_after" => 1792, "raw" => "寛政4刊",
                     "eras" => ["寛政4"], "basis" => "census 出版日 nengō (config/eras.yml)" },
                   era.call({ "pub_date" => "寛政4刊", "w3cdtf" => "" }))
      assert_equal [1847, 1853], era.call({ "pub_date" => "弘化4-嘉永6", "w3cdtf" => "1000" })
                                    .values_at("not_before", "not_after")
      assert_nil era.call({ "pub_date" => "正徳3", "w3cdtf" => "" }), "Ming or Japanese 正徳 — not guessed"
      assert_nil era.call({ "pub_date" => "[慶長元和年間]", "w3cdtf" => "" }), "no year number"
      typed = doc(2_537_051).metadata["date"]
      assert_match(/\ANDL Search record/, typed["raw"], "the bib record's typed year outranks the prose 寛政7序")
    end

    def test_w3cdtf_year_mints_the_date_envelope
      date = doc(2_532_153).metadata["date"]
      assert_equal [1605, 1605, "[慶長10(1605)]"],
                   date.values_at("not_before", "not_after", "raw")
    end
  end
end
