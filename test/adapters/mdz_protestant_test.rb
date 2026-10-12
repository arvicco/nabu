# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "fileutils"
require "tmpdir"

module Adapters
  # mdz-protestant (02-sources row 243): the MDZ page-OCR layer of
  # the 16th-century Slovene/Croatian Protestant prints. Fixtures: three
  # real objects, their IIIF manifests trimmed to the canvases whose hOCR
  # is checked in — Trubar's 1562 Articuli (PDM; the cover + two text
  # pages), Dalmatin's 1575 Sirah (NoC-NC; two pages) and the 1564
  # Croatian Spovid (NoC-NC; one page).
  class MdzProtestantTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("mdz-protestant")
    TRUBAR = "urn:nabu:mdz-protestant:bsb00078189"
    SIRAH = "urn:nabu:mdz-protestant:bsb11302253"
    SPOVID = "urn:nabu:mdz-protestant:bsb10206655"
    Adapter = Nabu::Adapters::MdzProtestant

    def conformance_adapter = Adapter.new(delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "mdz-protestant"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).to_h { |ref| [ref.id, conformance_adapter.parse(ref)] }
    end

    def test_discovers_complete_seed_objects_in_seed_order
      assert_equal [TRUBAR, SIRAH, SPOVID], documents.keys,
                   "seeds without a manifest on disk discover nothing"
    end

    def test_one_passage_per_canvas_with_text_cited_by_canvas_number
      doc = documents.fetch(TRUBAR)
      assert_equal "sl", doc.language
      assert_equal(%w[1 79 80], doc.map { |p| p.urn.delete_prefix("#{TRUBAR}:") })
      page = doc.find { |p| p.urn.end_with?(":79") }
      assert_equal 79, page.annotations["canvas"]
      assert_equal "(0079)", page.annotations["page_label"]
      assert page.text.start_with?("TE STARB PRAVE VERE.\n33\n"), page.text[0, 80]
      assert_includes page.text, "Odpuſzhane tih Gre shya", "long s and OCR splits ride verbatim"
    end

    def test_the_scan_target_label_leaves_the_text
      page = documents.fetch(TRUBAR).find { |p| p.urn.end_with?(":79") }
      assert_equal "00078189", page.annotations["scan_label"]
      refute_includes page.text.lines.first, "00078189"
      cover = documents.fetch(TRUBAR).first
      assert_equal "000", cover.annotations["scan_label"]
      assert_includes cover.text, "PRIMUS TRV"
    end

    def test_google_copies_carry_no_scan_label_and_keep_the_folio_number
      page = documents.fetch(SIRAH).first
      assert_nil page.annotations["scan_label"]
      assert_equal "74 (0076)", page.annotations["page_label"]
      assert page.text.start_with?("74\nIESVS\n"), page.text[0, 40]
    end

    def test_license_comes_from_each_manifest
      assert_nil documents.fetch(TRUBAR).license_override, "PDM is the source's open class"
      assert_equal "nc", documents.fetch(SIRAH).license_override, "NoC-NC rides as per-document nc"
      assert_equal "nc", documents.fetch(SPOVID).license_override
      assert_equal "https://rightsstatements.org/vocab/NoC-NC/1.0/", documents.fetch(SIRAH).metadata["license"]
    end

    def test_manifest_metadata_mines_the_axes
      meta = documents.fetch(TRUBAR).metadata
      assert_equal "machine-ocr", meta["text_nature"]
      assert_equal({ "not_before" => 1562, "not_after" => 1562, "raw" => "1562" }, meta["date"])
      assert_equal "V Tibingi", meta["place"], "the imprint's own spelling"
      assert_equal "Trubar, Primož, 1508-1586", meta["author"]
      assert_equal [{ "name" => "Trubar, Primož, 1508-1586", "gnd" => "118761005" }], meta["creators"]
      assert_equal "urn:nbn:de:bvb:12-bsb00078189-9", meta["urn_nbn"]
      assert_equal "https://mdz-nbn-resolving.de/details:bsb00078189", meta["permalink"]
      assert_equal "ESlg/4 H.ref. 831 m", meta["shelfmark"]
      assert documents.fetch(TRUBAR).title.start_with?("Articuli oli Deili")
    end

    def test_imprint_place_drops_the_printer_and_brackets
      assert_equal "Lublani", documents.fetch(SIRAH).metadata["place"]
      meta = documents.fetch(SPOVID).metadata
      assert_equal "Tubingae", meta["place"]
      assert_equal "Tubingae : [Morhart]", meta["imprint"]
      assert_equal "hrv", documents.fetch(SPOVID).language
      assert_equal(["Anton Dalmatin, -1579", "Consul, Stephan, 1531-1580"],
                   meta["contributors"].map { |c| c["name"] })
    end

    def test_orthography_is_declared_per_seed_never_guessed
      assert_nil documents.fetch(TRUBAR).metadata["orthography"], "Trubar 1562 predates bohoričica"
      seed = Adapter::SEEDS.find { |s| s.id == "bsb00078823" }
      assert_equal "bohoričica", seed.orthography, "Bohorič 1584 codifies it"
    end

    def test_an_incomplete_crawl_mints_no_document
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "bsb00078189"), dir)
        FileUtils.rm(File.join(dir, "bsb00078189", "hocr", "00080.hocr"))
        adapter = conformance_adapter
        assert_empty adapter.discover(dir).to_a
        skips = adapter.discovery_skips(dir)
        assert_equal ["crawl incomplete: bsb00078189 (1 page(s) to go)"], skips.notes
        assert skips.clean?, "a crawl in progress is skipped by rule, not unrecognized"
      end
    end

    def test_a_ledgered_404_page_completes_the_object
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "bsb00078189"), dir)
        FileUtils.rm(File.join(dir, "bsb00078189", "hocr", "00080.hocr"))
        File.write(File.join(dir, ".mdz-crawl.json"), JSON.generate({ "missing" => { "bsb00078189" => [80] } }))
        assert_equal [TRUBAR], conformance_adapter.discover(dir).map(&:id)
      end
    end

    # -- the paced, resumable crawl (WebMock; delay 0) ---------------------

    def seed_only(id) = [Adapter::SEEDS.find { |s| s.id == id }]

    def stub_manifest(id)
      body = File.read(File.join(FIXTURES, id, "manifest.json"))
      stub_request(:get, format(Adapter::MANIFEST_URL, id)).to_return(status: 200, body: body)
    end

    def stub_page(id, page, status: 200, remaining: "4000")
      body = status == 200 ? File.read(File.join(FIXTURES, id, "hocr", format("%05d.hocr", page))) : ""
      stub_request(:get, format(Adapter::OCR_URL, id, page))
        .to_return(status: status, body: body, headers: { "x-ratelimit-remaining" => remaining })
    end

    def test_fetch_crawls_missing_pages_and_resumes_after_the_slice
      stub_manifest("bsb00078189")
      [1, 79, 80].each { |page| stub_page("bsb00078189", page) }
      Dir.mktmpdir do |dir|
        adapter = Adapter.new(delay: 0, slice: 2, seeds: seed_only("bsb00078189"))
        report = adapter.fetch(dir)
        assert_match(%r{crawl at 2/3 page\(s\) \(\+2 this sync\); slice limit reached}, report.notes)
        assert_empty adapter.discover(dir).to_a, "two of three pages: no document yet"

        second = Adapter.new(delay: 0, slice: 2, seeds: seed_only("bsb00078189")).fetch(dir)
        assert_match(%r{crawl at 3/3 page\(s\) \(\+1 this sync\)\z}, second.notes)
        assert_requested :get, format(Adapter::OCR_URL, "bsb00078189", 1), times: 1
        assert_equal [TRUBAR], adapter.discover(dir).map(&:id)
        refute_equal report.sha, second.sha
      end
    end

    def test_fetch_stops_cleanly_on_429_and_at_the_quota_floor
      stub_manifest("bsb00078189")
      stub_page("bsb00078189", 1, remaining: "10")
      Dir.mktmpdir do |dir|
        report = Adapter.new(delay: 0, seeds: seed_only("bsb00078189")).fetch(dir)
        assert_match(/\+1 this sync\); rate limit reached/, report.notes,
                     "the remaining quota at the floor ends the slice after the page is kept")
        stub_page("bsb00078189", 79, status: 429)
        again = Adapter.new(delay: 0, seeds: seed_only("bsb00078189")).fetch(dir)
        assert_match(/\+0 this sync\); rate limit reached/, again.notes, "429 never raises")
      end
    end

    def test_fetch_ledgers_a_404_page
      stub_manifest("bsb00078189")
      stub_page("bsb00078189", 1)
      stub_page("bsb00078189", 79, status: 404)
      stub_page("bsb00078189", 80)
      Dir.mktmpdir do |dir|
        Adapter.new(delay: 0, seeds: seed_only("bsb00078189")).fetch(dir)
        ledger = JSON.parse(File.read(File.join(dir, ".mdz-crawl.json")))
        assert_equal({ "bsb00078189" => [79] }, ledger["missing"])
        assert_equal(%w[1 80], Adapter.new(delay: 0).then { |a| a.parse(a.discover(dir).first) }
                                                    .map { |p| p.urn.split(":").last })
      end
    end

    def test_a_failing_manifest_aborts_the_sync
      stub_request(:get, format(Adapter::MANIFEST_URL, "bsb00078189")).to_return(status: 503)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { Adapter.new(delay: 0, seeds: seed_only("bsb00078189")).fetch(dir) }
      end
    end
  end
end
