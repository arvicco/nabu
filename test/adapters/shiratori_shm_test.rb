# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "support/adapter_conformance"

module Adapters
  # shiratori-shm — Shiratori's romanized Secret History (Tōyō Bunko 1943)
  # as the NDL OCR full text of pid 1184344, one document, koma grain.
  # Fixture: the real fulltext-json answer trimmed to nine koma that pin
  # every per-koma rule — the Kodak calibration frame (1) and a letterless
  # koma (2) skipped by rule, the title leaf (3, jpn), the Japanese preface
  # (4, jpn), Ye Dehui's classical-Chinese preface (11, lzh), the first two
  # interlinear openings (17–18, xng), a 總譯 summary-translation opening
  # inside the body (153, zho) and the English title leaf (636, eng).
  class ShiratoriShmTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("shiratori-shm")
    KLASS = Nabu::Adapters::ShiratoriShm
    URN = "urn:nabu:shiratori-shm:1184344"

    def conformance_adapter = KLASS.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "shiratori-shm"

    def document
      @document ||= conformance_adapter.parse(conformance_adapter.discover(FIXTURES).first)
    end

    def passage(page) = document.passages.find { |p| p.urn == "#{URN}:#{page}" }

    def test_one_document_one_passage_per_text_koma
      assert_equal [URN], conformance_adapter.discover(FIXTURES).map(&:id)
      assert_equal(%w[3 4 11 17 18 153 636], document.passages.map { |p| p.annotations["koma"] })
      assert_equal (1..7).to_a, document.passages.map(&:sequence)
    end

    def test_the_calibration_frame_and_letterless_koma_skip_by_rule
      assert_nil passage(1), "the Kodak target is never text"
      assert_nil passage(2), "a bare page number is never a passage"
      assert_equal({ "calibration" => 1, "letterless" => 1 }, document.metadata["koma_skipped"])
      assert_equal 9, document.metadata["koma_count"]
    end

    def test_each_koma_claims_the_language_its_script_mix_shows
      expected = { 3 => "jpn", 4 => "jpn", 11 => "lzh", 17 => "xng", 18 => "xng", 153 => "zho", 636 => "eng" }
      assert_equal(expected, document.passages.to_h { |p| [p.annotations["koma"].to_i, p.language] })
      assert_equal "xng", document.language
    end

    def test_the_interlinear_body_carries_hanzi_beside_the_romanization
      body = passage(17).text
      assert_includes body, "忙豁命紐察中Monyol-un", "the OCR's own 命 for 侖, uncorrected"
      assert_includes body, "tengeri-ece"
      assert_includes passage(636).text, "SHIRATORI KURAKICHI"
    end

    def test_koma_language_rules_in_isolation
      assert_equal "lzh", KLASS.koma_language("元朝祕史" * 20, body: false)
      assert_equal "zho", KLASS.koma_language("元朝祕史" * 20, body: true)
      assert_equal "jpn", KLASS.koma_language("音譯蒙文元朝祕史", body: false), "the title leaf"
      assert_equal "jpn", KLASS.koma_language("#{'あ' * 12}#{'元' * 40}", body: true)
      assert_equal "xng", KLASS.koma_language("#{'qurimlamui ' * 3}#{'忽林剌梅' * 6}", body: false)
      assert_equal "eng", KLASS.koma_language("Editor's Foreword. The original of the 元朝祕史", body: true)
    end

    def test_metadata_carries_the_edition_and_the_ocr_nature
      meta = document.metadata
      assert_equal({ "not_before" => 1943, "not_after" => 1943, "class" => "edition",
                     "raw" => "昭和18 (1943), the NDL record; the English title leaf reads 1942" }, meta["date"])
      assert_equal "machine-ocr", meta["text_nature"]
      assert_equal "https://dl.ndl.go.jp/pid/1184344", meta["permalink"]
      assert_includes meta["base_edition"], "葉德輝"
      assert_includes meta["work_note"], "altaica-shm"
      assert_equal({ "author" => { "values" => ["白鳥庫吉"] } }, meta["facets"])
    end

    def test_the_metadata_dates_lane_reads_the_structured_shape
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["shiratori-shm"]
    end

    def test_manifest_is_open_public_domain
      manifest = KLASS.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "died 1942"
      assert_equal "ndl-fulltext-json", manifest.parser_family
    end

    def test_registry_row_is_registered_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["shiratori-shm"]
      refute_nil entry
      refute entry.wired, "wired: false until the first real sync is verified"
      assert_equal "manual", entry.sync_policy
      assert_equal ["mongolic"], entry.axes
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "shiratori-shm", name: "Shiratori SHM", adapter_class: KLASS.name,
                                          license_class: "open")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 1, first.added
      assert_equal 7, db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 1, second.skipped
      assert_equal 7, db[:passages].count
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only) ------------------------------------------------

    BOOK = File.join(FIXTURES, "books", "1184344.json")
    BOOK_URL = "https://lab.ndl.go.jp/dl/api/book/fulltext-json/1184344"

    def test_fetch_lands_the_book_once_and_holds_it
      stub = stub_request(:get, BOOK_URL).to_return(status: 200, body: File.binread(BOOK))
      Dir.mktmpdir do |workdir|
        report = KLASS.new.fetch(workdir)
        assert_equal Digest::SHA256.file(BOOK).hexdigest, report.sha
        assert File.file?(File.join(workdir, "books", "1184344.json"))
        KLASS.new.fetch(workdir)
        assert_requested stub, times: 1
      end
    end

    def test_fetch_refuses_an_answer_without_a_koma_list
      stub_request(:get, BOOK_URL).to_return(status: 200, body: "This PID is not allowed")
      Dir.mktmpdir do |workdir|
        assert_raises(Nabu::FetchError) { KLASS.new.fetch(workdir) }
        refute File.exist?(File.join(workdir, "books", "1184344.json"))
      end
    end
  end
end
