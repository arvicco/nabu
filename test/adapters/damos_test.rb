# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "support/paced_crawl_conformance"
require "nabu/paced_crawl_chain"
require "stringio"
require "tmpdir"

module Adapters
  # damos: DĀMOS, the Database of Mycenaean at Oslo — the complete
  # Linear B corpus. Fixtures (retrieved 2026-10-18): four real
  # ajaxitem JSON records — KN B 822 (under-dots + the VIR logogram),
  # PY Tn 316 (recto/verso, unlabeled margin lines), KN Vc <295> (a
  # LOST tablet: lost -1, Preserved "No") and TH Z 839 (a stirrup-jar
  # inscription, the "Vases - Thebes" collection) — plus a trimmed
  # ajaxgetfilter listing (six ids, collection counts restated).
  class DamosTest < Minitest::Test
    include AdapterConformance
    include PacedCrawlConformance

    FIXTURES = Nabu::TestSupport.fixtures("damos")
    LISTING = "https://damos.hf.uio.no/ajaxgetfilter"
    ITEM = "https://damos.hf.uio.no/ajaxitem/%s/"

    def conformance_adapter = Nabu::Adapters::Damos.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "damos"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(id) = documents.find { |d| d.urn == "urn:nabu:damos:#{id}" } || flunk("#{id} missing")

    def quiet_adapter(slice: 1_500) = Nabu::Adapters::Damos.new(delay: 0, slice: slice, timeout_backoff: 0)

    def fresh_ledger = { "denied" => [], "empty" => [], "timeout-stuck" => [], "server-error" => [] }

    def item_body(id) = File.read(File.join(FIXTURES, "items", "#{id}.json"))

    # -- documents ---------------------------------------------------------

    def test_discovers_one_document_per_crawled_item
      assert_equal %w[urn:nabu:damos:277 urn:nabu:damos:4985 urn:nabu:damos:5755 urn:nabu:damos:755],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_heading_is_the_title_and_language_is_mycenaean
      d = doc(755)
      assert_equal "KN B 822 (-)", d.title
      assert_equal "gmy", d.language
    end

    def test_line_labels_are_the_passage_grain
      d = doc(755)
      assert_equal(%w[1a 1b 2], d.passages.map { |p| p.urn.delete_prefix("#{d.urn}:") })
      assert_equal ".1a", d.passages.first.annotations["line"]
      assert_match(/\A\]\s+po-ḍạ-qe-re-ṣị-je-wo\z/, d.passages.first.text,
                   "the po-da-qe-re-si-je-wo line, under-dots composed by NFC, layout spacing verbatim")
      assert_includes d.passages[1].text, "do-e-ro  ,  VIR   1", "logograms ride verbatim"
      assert_equal "vac.", d.passages[2].text.split.last
    end

    def test_under_dots_are_nfc_composed_at_the_boundary
      text = doc(755).passages.first.text
      assert text.unicode_normalized?(:nfc)
      assert_includes text, "ḍ", "d + U+0323 composes to ḍ (gmy is not NFC-exempt)"
      refute_includes text, "ḍ"
    end

    def test_verso_lines_take_the_side_prefix_and_unlabeled_lines_are_kept
      d = doc(4985)
      ids = d.passages.map { |p| p.urn.delete_prefix("#{d.urn}:") }
      assert_equal %w[1 2 3 4 5 6 7 8 9 10 u1 u2], ids.first(12), "recto, then the two unlabeled margin lines"
      assert_equal "v.1", ids[12], "the verso restarts its .1 under the side marker"
      assert_includes ids, "v.3a"
      assert_equal "v.u3", ids.last, "the closing reliqua-pars line sits on the verso"
      assert_equal ids.uniq, ids
      assert_equal "reliqua pars sine regulis", d.passages[10].text
      assert_equal "di-we si-p̣ọ-ṛọ ti-mi-ṭọ".unicode_normalize(:nfc), d.passages[11].text
      assert_equal "v.", d.passages[12].annotations["side"]
      assert_nil d.passages[0].annotations["side"]
      assert_equal "true", d.passages[10].annotations["unlabeled"]
    end

    def test_an_unlabeled_one_line_content_is_one_passage
      d = doc(5755)
      assert_equal ["#{d.urn}:u1"], d.passages.map(&:urn)
      assert_equal "ka-u-no o-du-ru-wi-jo , wa-na-ka-te-ro ,", d.passages.first.text
    end

    def test_side_markers_are_parsed_from_the_censused_shapes
      adapter = conformance_adapter
      lines = adapter.send(:content_lines, ".1  a-b\nlat. inf.\n  ]c-d[\nv.↓\n  e\nα\n  f")
      assert_equal([[nil, "1", "a-b"], ["lat. inf.", "u1", "]c-d["], ["v.↓", "u2", "e"], ["α", "u3", "f"]],
                   lines.map { |l| [l[:side], l[:label], l[:text]] })
      assert_equal(%w[1 lat-inf.u1 v.u2 α.u3], lines.map { |l| l[:id] })
    end

    def test_a_repeated_label_is_disambiguated_not_dropped
      lines = conformance_adapter.send(:content_lines, ".1  a\n.1  b")
      assert_equal(%w[1 1~2], lines.map { |l| l[:id] })
    end

    # -- axes --------------------------------------------------------------

    def test_site_and_findspot_mine_the_place_hash
      meta = doc(4985).metadata
      assert_equal({ "ancient" => "Pylos", "find_area" => "PY, Room 8", "find_spot" => "8.2219" },
                   meta["place"])
      assert_equal "Pylos", meta["site"]
    end

    def test_a_vase_collection_places_at_its_site_and_keeps_its_provenance
      meta = doc(5755).metadata
      assert_equal "Vases - Thebes", meta["site"], "the collection label rides verbatim"
      assert_equal "Thebes", meta.dig("place", "ancient"), "the findspot site, the Vases- grouping stripped"
      assert_equal "West Crete α", meta["provenance"], "the jar's clay provenance is NOT the findspot"
      assert_equal "stirrup jar", meta["object"]
      assert_equal "1921", meta["find_year"]
    end

    def test_chronology_rides_as_the_period_label
      assert_equal "LH IIIB2/LH IIIC", doc(4985).metadata["period"]
      assert_equal "LH IIIA2-LH IIIB", doc(5755).metadata["context_chronology"],
                   "upstream's U+00A0 inside the label folds to a plain space"
      refute doc(755).metadata.key?("period"), "upstream's '-' sentinel mints no period"
    end

    def test_series_hand_and_collection_facet
      facets = doc(4985).metadata["facets"]
      assert_equal({ "values" => ["Tn"] }, facets["series"], "series + subseries, the Linear B prefix")
      assert_equal({ "values" => ["44"] }, facets["hand"])
      assert_equal({ "values" => ["Pylos"] }, facets["collection"])
      assert_equal({ "values" => ["tablet"] }, facets["object"])
      refute doc(755).metadata["facets"].key?("hand"), "the '-' hand sentinel mints no facet"
      assert_equal({ "values" => ["B"] }, doc(755).metadata.dig("facets", "series"),
                   "a '-' subseries leaves the bare series")
    end

    def test_lost_tablets_are_flagged
      assert_equal true, doc(277).metadata["lost"]
      refute doc(755).metadata.key?("lost")
    end

    def test_provenance_ids_ride
      meta = doc(755).metadata
      assert_equal "951327", meta["tm"]
      assert_equal "https://damos.hf.uio.no/755", meta["permalink"]
      assert_includes meta["bibliography"], "Companion-1 138/252/253"
    end

    def test_registered_with_metadata_dates
      assert_equal :period_label, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["damos"]
    end

    # -- the listing -------------------------------------------------------

    def test_listing_ids_are_unique_ascending_and_alias_rows_collapse
      ids = conformance_adapter.send(:listing_ids, File.read(File.join(FIXTURES, "map", "ajaxgetfilter.json")))
      assert_equal %w[277 755 4972 4985 5443 5755], ids
    end

    def test_a_truncated_listing_aborts
      body = JSON.generate({ "collections" => [{ "id" => 1, "value" => "Knossos", "count" => 3 }],
                             "tables" => [{ "id" => 1, "tsort" => 1 }, { "id" => 1, "tsort" => 3 },
                                          { "id" => 2, "tsort" => 1 }] })
      error = assert_raises(Nabu::FetchError) { conformance_adapter.send(:listing_ids, body) }
      assert_match(/TRUNCATED.*3.*2/m, error.message)
    end

    def test_a_truncated_listing_never_replaces_the_kept_map
      stub_request(:post, LISTING).to_return(
        status: 200, body: JSON.generate({ "collections" => [{ "count" => 2 }], "tables" => [{ "id" => 1 }] })
      )
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "map"))
        File.write(File.join(dir, "map", "ajaxgetfilter.json"), "KEPT")
        assert_raises(Nabu::FetchError) { quiet_adapter.fetch(dir) }
        assert_equal "KEPT", File.read(File.join(dir, "map", "ajaxgetfilter.json"))
      end
    end

    def test_a_listing_without_ids_aborts
      body = JSON.generate({ "collections" => [], "tables" => [] })
      assert_raises(Nabu::FetchError) { conformance_adapter.send(:listing_ids, body) }
    end

    # -- the crawl ---------------------------------------------------------

    D = Nabu::Adapters::Damos
    EMPTY_ITEM = '{"item":{"content":"  "}}'

    # A held listing whose unique ids are exactly +ids+ (the truncation
    # defense satisfied: one collection counting them all).
    def write_listing(dir, ids)
      FileUtils.mkdir_p(File.join(dir, "map"))
      File.write(File.join(dir, "map", "ajaxgetfilter.json"),
                 JSON.generate({ "collections" => [{ "count" => ids.size }],
                                 "tables" => ids.map { |id| { "id" => Integer(id, 10) } } }))
    end

    def crawl_over(dir, ids, slice: 1_500)
      write_listing(dir, ids)
      quiet_adapter(slice: slice).item_crawl(dir)
    end

    def ledger_on_disk(dir) = JSON.parse(File.read(File.join(dir, ".damos-crawl.json")))

    # The paced-crawl conformance drives the item lane through its real
    # wiring: the held listing is the universe, items/<id>.json the held
    # rule, the script answers over the stubbed ajaxitem endpoint. damos
    # answers a missing id with HTTP 500 (a terminal class, server-error),
    # so the script's :fatal — a non-terminal failure — is an HTTP 400.
    def paced_crawl_engine(dir:, ids:, slice:, script:)
      stub_request(:get, %r{\Ahttps://damos\.hf\.uio\.no/ajaxitem/\d+/\z}).to_return do |request|
        case script.call(request.uri.path[%r{/ajaxitem/(\d+)/}, 1])
        when :ok then { status: 200, body: item_body("755") }
        when :denied then { status: 403, body: PacedCrawlConformance::PC_REFUSAL_BODY }
        when :empty then { status: 200, body: EMPTY_ITEM }
        when :timeout then raise Net::ReadTimeout
        when :fatal then { status: 400, body: "bad request" }
        end
      end
      crawl_over(dir, ids, slice: slice)
    end

    def paced_crawl_hold!(dir, id)
      FileUtils.mkdir_p(File.join(dir, "items"))
      File.write(File.join(dir, "items", "#{id}.json"), item_body("755"))
    end

    def test_the_lane_keeps_the_committed_etiquette
      lane = D::ITEM_CRAWL
      assert_equal ["items", ".damos-crawl.json", 1.0, 1_500, 3, 5.0],
                   [lane.name, lane.ledger_file, lane.delay, lane.slice, lane.timeout_attempts, lane.timeout_backoff]
      assert_equal %w[denied empty timeout-stuck server-error], lane.class_names,
                   "the four classes, in the ledger's own order"
      assert_equal %w[timeout-stuck server-error], lane.classes_for(:timeout),
                   "a persistent 5xx is a timeout-grade failure: retried with backoff, then ledgered"
      assert_equal [[:timeout], 3], [lane.outage_statuses, lane.outage_run], "the outage breaker is armed"
      assert_equal D::LEDGER_CLASSES, lane.class_names
    end

    def test_paced_crawls_is_the_chain_seam
      Dir.mktmpdir do |dir|
        lanes = quiet_adapter.paced_crawls(dir)
        assert_equal ["items"], lanes.keys
        assert_kind_of Nabu::PacedCrawl::Engine, lanes["items"]
        assert_equal "items", lanes["items"].spec.name
      end
    end

    def test_no_held_listing_is_an_empty_cone
      Dir.mktmpdir do |dir|
        report = quiet_adapter.item_crawl(dir).slice!
        assert_equal [:cone_exhausted, 0], [report.classification, report.census]
      end
    end

    def test_fetch_posts_the_listing_and_crawls_one_slice_resumably
      listing = stub_request(:post, LISTING)
                .to_return(status: 200, body: File.read(File.join(FIXTURES, "map", "ajaxgetfilter.json")))
      %w[277 755 4972].each do |id|
        stub_request(:get, format(ITEM, id)).to_return(status: 200, body: item_body(id == "4972" ? "4985" : id))
      end
      Dir.mktmpdir do |dir|
        report = quiet_adapter(slice: 3).fetch(dir)
        assert_requested listing
        assert File.file?(File.join(dir, "map", "ajaxgetfilter.json")), "the listing is kept under map/"
        assert_equal %w[277 4972 755], Dir.children(File.join(dir, "items")).map { |f| File.basename(f, ".json") }.sort
        assert_includes report.notes.split("; "),
                        "items: census 6 = held 3 (+3) + ledgered 0 (+0) [denied 0, empty 0, timeout-stuck 0, " \
                        "server-error 0] + remaining 3 — reconciles"

        %w[4985 5443 5755].each do |id|
          stub_request(:get, format(ITEM, id)).to_return(status: 200, body: item_body(id == "5443" ? "755" : id))
        end
        resumed = quiet_adapter(slice: 3).fetch(dir)
        assert_match(/items: census 6 = held 6 \(\+3\)/, resumed.notes)
        assert_requested :get, format(ITEM, "277"), times: 1 # on-disk is done: never re-fetched
      end
    end

    def test_denied_and_empty_items_are_ledgered_and_never_retried
      stub_request(:get, format(ITEM, "1")).to_return(status: 404, body: "gone")
      stub_request(:get, format(ITEM, "2")).to_return(status: 200, body: EMPTY_ITEM)
      stub_request(:get, format(ITEM, "3")).to_return(status: 200, body: "<html>not json</html>")
      Dir.mktmpdir do |dir|
        report = crawl_over(dir, %w[1 2 3]).slice!
        assert_equal [0, { "denied" => 2, "empty" => 1, "timeout-stuck" => 0, "server-error" => 0 }, []],
                     [report.ok, report.refused, report.stuck]
        assert_equal({ id: "1", status: :denied, http_status: 404, body_head: "gone" }, report.samples.first,
                     "the refusal's own answer rides as evidence")
        on_disk = ledger_on_disk(dir)
        assert_equal %w[1 3], on_disk["denied"]
        assert_equal ["2"], on_disk["empty"], "an item with no transliteration is ledgered empty"
      end
    end

    def test_a_timing_out_item_is_ledgered_stuck_and_the_slice_continues
      stuck = stub_request(:get, format(ITEM, "2")).to_raise(Net::ReadTimeout)
      stub_request(:get, format(ITEM, "3")).to_return(status: 200, body: item_body("755"))
      Dir.mktmpdir do |dir|
        report = crawl_over(dir, %w[2 3]).slice!
        assert_requested stuck, times: D::TIMEOUT_ATTEMPTS
        assert_equal [1, ["2"]], [report.ok, report.stuck]
        assert_equal ["2"], ledger_on_disk(dir)["timeout-stuck"]
        assert File.file?(File.join(dir, "items", "3.json"))
      end
    end

    # A missing id answers HTTP 500 (probed 2026-10-18: /ajaxitem/9999999/
    # → 500 with an HTML error page), so a lone persistent 500 is
    # ledgered under its own class rather than wedging every resume.
    def test_a_lone_server_error_is_retried_then_ledgered
      failing = stub_request(:get, format(ITEM, "2")).to_return(status: 500, body: "<html>Server Error</html>")
      stub_request(:get, format(ITEM, "3")).to_return(status: 200, body: item_body("755"))
      Dir.mktmpdir do |dir|
        report = crawl_over(dir, %w[2 3]).slice!
        assert_requested failing, times: D::TIMEOUT_ATTEMPTS
        assert_equal [1, ["2"]], [report.ok, report.stuck]
        assert_equal ["2"], ledger_on_disk(dir)["server-error"]
        assert_empty ledger_on_disk(dir)["timeout-stuck"]
        assert_equal [:timeout, 500], report.samples.first.values_at(:status, :http_status)
      end
    end

    def test_another_client_error_stays_fatal
      stub_request(:get, format(ITEM, "2")).to_return(status: 400)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { crawl_over(dir, %w[2]).slice! }
      end
    end

    # The outage defense: a run of consecutive failures is upstream down,
    # not bad ids — the crawl aborts WITHOUT ledgering the run, and the
    # next sync resumes at the same place. The sync still aborts loudly.
    def test_consecutive_failures_abort_the_sync_without_ledgering_the_run
      stub_request(:post, LISTING)
        .to_return(status: 200, body: File.read(File.join(FIXTURES, "map", "ajaxgetfilter.json")))
      %w[277 755 4972 4985].each { |id| stub_request(:get, format(ITEM, id)).to_return(status: 503) }
      Dir.mktmpdir do |dir|
        error = assert_raises(Nabu::FetchError) { quiet_adapter.fetch(dir) }
        assert_match(/damos crawl aborted — upstream outage: 3 consecutive item\(s\) failed \(277, 755, 4972\)/,
                     error.message)
        assert_empty ledger_on_disk(dir)["server-error"], "the outage run is never ledgered"
        assert_equal "outage_abort", ledger_on_disk(dir).dig("last_slice", "classification")
        assert_not_requested :get, format(ITEM, "4985")
      end
    end

    # THE ENGINE LAW (a deliberate delta from the hand-rolled crawl, which
    # committed a short trailing run at slice end): a failure still staged
    # when the slice ends stays UNLEDGERED and is re-asked next slice; it
    # commits once a later id answers.
    def test_a_trailing_failure_at_slice_end_stays_unledgered_and_is_re_asked
      stub_request(:get, format(ITEM, "1")).to_return(status: 200, body: item_body("755"))
      failing = stub_request(:get, format(ITEM, "2")).to_return(status: 500)
      stub_request(:get, format(ITEM, "3")).to_return(status: 200, body: item_body("755"))
      Dir.mktmpdir do |dir|
        report = crawl_over(dir, %w[1 2 3], slice: 2).slice!
        assert_empty ledger_on_disk(dir)["server-error"], "no later id confirmed upstream alive"
        assert_equal({ aborted: false, count: 1, ids: ["2"] }, report.outage.slice(:aborted, :count, :ids))
        assert(report.lines.any? { |line| line.include?("OUTAGE STAGE") }, report.lines.inspect)

        crawl_over(dir, %w[1 2 3], slice: 2).slice!
        assert_requested failing, times: 2 * D::TIMEOUT_ATTEMPTS
        assert_equal ["2"], ledger_on_disk(dir)["server-error"], "item 3 answering commits it"
      end
    end

    # …and its consequence at the very END of the cone: a genuinely bad
    # last id is re-asked every slice, never reaching cone-exhausted — a
    # chained run stops loudly on the declared zero-yield budget instead.
    def test_a_bad_last_id_stops_a_chain_on_the_zero_yield_budget
      stub_request(:get, format(ITEM, "1")).to_return(status: 200, body: item_body("755"))
      stub_request(:get, format(ITEM, "2")).to_return(status: 500)
      Dir.mktmpdir do |dir|
        paced_crawl_hold!(dir, "1")
        engine = crawl_over(dir, %w[1 2])
        summary = Nabu::PacedCrawl::Chain.new(engine: engine, slices: 5, log: StringIO.new).run!
        assert_predicate summary, :stalled?
        assert_match(/3 consecutive zero-yield slice\(s\)/, summary.stop_reason)
        assert_equal 3, summary.reports.size
        refute(summary.reports.any? { |r| r.classification == :cone_exhausted })
        assert_empty ledger_on_disk(dir)["server-error"]
      end
    end

    def test_a_ledgered_item_is_skipped_on_resume
      asked = []
      stub_request(:get, %r{/ajaxitem/\d+/\z}).to_return do |request|
        asked << request.uri.path[/\d+/]
        { status: 200, body: EMPTY_ITEM }
      end
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".damos-crawl.json"),
                   JSON.generate({ "denied" => ["1"], "timeout-stuck" => ["2"], "server-error" => ["3"] }))
        crawl = crawl_over(dir, %w[1 2 3 4])
        assert_equal [], crawl.ledger["empty"], "a missing class defaults empty"
        crawl.slice!
        assert_equal ["4"], asked
      end
    end

    # The on-disk ledger shape: the four classes, in this order, each a
    # sorted array, pretty-printed; the engine's last_slice rides beside.
    def test_the_ledger_on_disk_is_four_sorted_flat_arrays
      stub_request(:post, LISTING)
        .to_return(status: 200, body: File.read(File.join(FIXTURES, "map", "ajaxgetfilter.json")))
      stub_request(:get, format(ITEM, "277")).to_return(status: 200, body: '{"item":{"content":""}}')
      stub_request(:get, format(ITEM, "755")).to_return(status: 404, body: "gone")
      stub_request(:get, format(ITEM, "4972")).to_return(status: 200, body: "<html>no</html>")
      stub_request(:get, format(ITEM, "4985")).to_return(status: 200, body: item_body("4985"))
      Dir.mktmpdir do |dir|
        quiet_adapter(slice: 4).fetch(dir)
        on_disk = ledger_on_disk(dir)
        assert_equal %w[denied empty timeout-stuck server-error last_slice], on_disk.keys
        expected = JSON.pretty_generate({ "denied" => %w[4972 755], "empty" => ["277"],
                                          "timeout-stuck" => [], "server-error" => [] })
        assert_equal expected, JSON.pretty_generate(on_disk.except("last_slice"))
      end
    end

    # A ledger written by the pre-engine crawl (the live one's shape: four
    # pretty-printed class arrays, no last_slice) reads cleanly, and a
    # slice that learns nothing writes the class section back byte for byte.
    def test_a_pre_engine_ledger_reads_and_writes_back_byte_compatibly
      legacy = JSON.pretty_generate({ "denied" => [], "empty" => %w[5089 5090], "timeout-stuck" => [],
                                      "server-error" => [] })
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".damos-crawl.json"), legacy)
        %w[277 755].each { |id| paced_crawl_hold!(dir, id) }
        crawl = crawl_over(dir, %w[277 755 5089 5090])
        assert_equal({ "denied" => [], "empty" => %w[5089 5090], "timeout-stuck" => [], "server-error" => [] },
                     crawl.ledger)
        assert_predicate crawl.diagnose, :reconciles?
        report = crawl.slice!
        assert_equal [:cone_exhausted, 0], [report.classification, report.requests]
        written = File.read(File.join(dir, ".damos-crawl.json"))
        assert_equal legacy, JSON.pretty_generate(JSON.parse(written).except("last_slice"))
        assert written.start_with?(legacy.delete_suffix("\n}")), "the class section leads, unchanged"
      end
    end

    def test_a_held_item_reprobed_is_never_overwritten
      stub_request(:get, format(ITEM, "755")).to_return(status: 200, body: item_body("4985"))
      Dir.mktmpdir do |dir|
        paced_crawl_hold!(dir, "755")
        outcome = quiet_adapter.send(:fetch_item!, dir, "755")
        assert_equal [:ok, 200], [outcome.status, outcome.http_status]
        assert_equal item_body("755"), File.read(File.join(dir, "items", "755.json")), "the probe answers liveness"
      end
    end

    def test_the_lane_declares_its_schedule
      schedule = D::ITEM_CRAWL.schedule
      assert_equal [:per_phase, 3, 3],
                   [schedule.cadence, schedule.slices_per_phase, schedule.stop_after_zero_slices]
    end

    def test_crawl_sha_moves_with_the_held_set_and_the_ledger
      adapter = quiet_adapter
      Dir.mktmpdir do |dir|
        base = adapter.send(:crawl_sha, dir, ["9"], fresh_ledger)
        assert_equal base, adapter.send(:crawl_sha, dir, ["9"], fresh_ledger)
        refute_equal base, adapter.send(:crawl_sha, dir, %w[9 10], fresh_ledger)
        refute_equal base, adapter.send(:crawl_sha, dir, ["9"], fresh_ledger.merge("denied" => ["1"]))
      end
    end

    def test_stray_files_are_reported
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "items"))
        FileUtils.mkdir_p(File.join(dir, "map"))
        File.write(File.join(dir, "items", "1.json"), "{}")
        File.write(File.join(dir, "map", "ajaxgetfilter.json"), "{}")
        File.write(File.join(dir, ".damos-crawl.json"), "{}")
        File.write(File.join(dir, "stray.txt"), "x")
        assert_equal ["non-corpus file: stray.txt"], conformance_adapter.discovery_skips(dir).notes
      end
    end

    def test_registry_row
      entry = YAML.safe_load_file(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml"))["damos"]
      assert_equal "Nabu::Adapters::Damos", entry["adapter"]
      assert_equal true, entry["wired"] # wired at the completed crawl (5,890 docs, 2026-10-18)
      assert_equal "manual", entry["sync_policy"]
      assert_equal %w[epigraphy classical], entry["axes"]
      assert_equal "nc", Nabu::Adapters::Damos.manifest.license_class
      assert_includes Nabu::Adapters::Damos.manifest.license, "Content: CC BY-NC-SA 4.0"
    end
  end
end
