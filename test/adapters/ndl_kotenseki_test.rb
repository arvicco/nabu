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
      assert_equal %w[urn:nabu:ndl-kotenseki:2532153],
                   conformance_adapter.discover(FIXTURES).map(&:id)
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

    # -- №I-9: a book that hangs on Net::ReadTimeout wedged the resumable
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
        File.write(File.join(dir, "census.tsv"), "pid\ttitle\n2546843\tx\n")
        report = quiet_adapter.fetch(dir)
        assert_match(/1 stuck on timeout \(2546843\)/, report.notes)
      end
    end

    def test_w3cdtf_year_mints_the_date_envelope
      date = doc(2_532_153).metadata["date"]
      assert_equal [1605, 1605, "[慶長10(1605)]"],
                   date.values_at("not_before", "not_after", "raw")
    end
  end
end
