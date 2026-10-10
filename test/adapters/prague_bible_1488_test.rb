# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # prague-bible-1488 — the HTR Winter School 2024 Medieval Czech ground
  # truth over the Prague Bible (1488; ÖNB Ink 13.C.5), Zenodo record
  # 14524858 (P116-1). 31 PAGE-XML pages, all Transkribus status GT, in
  # one zip (images + page/ + txt/). Grain: document = one page (the
  # Transkribus page number), passage = one TextLine — citation
  # r<region>.l<line> from the page's reading order. Fixture: three real
  # pages verbatim from the zip (Genesis 0023, Joshua 0217, Judith 0501).
  class PragueBible1488Test < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("prague-bible-1488")
    URN = "urn:nabu:prague-bible-1488"

    def conformance_adapter = Nabu::Adapters::PragueBible1488.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "prague-bible-1488"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(page) = documents.find { |d| d.urn == "#{URN}:#{page}" } || flunk("#{page} missing")

    def test_discovers_one_document_per_page_keyed_by_the_transkribus_page_number
      assert_equal ["#{URN}:p0023", "#{URN}:p0217", "#{URN}:p0501"],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_lines_become_passages_cited_by_region_and_line_reading_order
      d = doc("p0023")
      assert_equal "cs", d.language
      first = d.passages.first
      assert_equal "#{URN}:p0023:r1.l1", first.urn
      assert_equal "Prwnie knihy", first.text
      assert_equal "cs", first.language
      second_column = d.passages.find { |p| p.urn == "#{URN}:p0023:r2.l1" }
      assert_equal "ſtie buoh že w kteryž koli den gieſti bu¬", second_column.text,
                   "the long s and the ¬ line-break hyphen stay verbatim (semi-diplomatic GT)"
      assert_equal 94, d.passages.size
    end

    def test_a_one_line_running_title_region_is_its_own_region
      d = doc("p0501")
      assert_equal "Knihy", d.passages.first.text
      assert_equal "#{URN}:p0501:r1.l1", d.passages.first.urn
      assert_equal "#{URN}:p0501:r2.l1", d.passages[1].urn
    end

    def test_abbreviations_ride_with_their_expansions
      d = doc("p0217")
      passage = d.passages.find { |p| p.annotations["line_id"] == "region_1734259517264_16_tl_23" }
      abbrev = passage.annotations["abbreviations"].first
      assert_equal "Izrahelſkemu", abbrev["expansion"]
      assert_equal 5, abbrev["offset"]
      assert_equal passage.text[5, 11], abbrev["form"]
      assert_equal [{ "offset" => 15, "length" => 1, "form" => passage.text[15] }],
                   passage.annotations["superscript"]
    end

    def test_unclear_spans_ride_as_annotations
      unclear = doc("p0217").passages.filter_map { |p| p.annotations["unclear"] }.flatten
      refute_empty unclear
      assert(unclear.all? { |span| span.key?("offset") && span.key?("form") })
    end

    def test_page_metadata_carries_the_segment_the_record_assigns_it
      meta = doc("p0023").metadata
      assert_equal 23, meta["page_nr"]
      assert_equal "GT", meta["status"]
      assert_equal "0023_DTL_547662-0024.jpeg", meta["image"]
      assert_equal "Genesis", meta["book"]
      assert_equal "Gn 2:15–8:17", meta["passage_range"]
      assert_equal "7v–9v", meta["folio_range"]
      assert_equal "Martin Plechatý", meta["transcriber"]
      assert_equal "Judith", doc("p0501").metadata["book"]
      assert_equal "Joshua", doc("p0217").metadata["book"]
    end

    def test_every_page_is_dated_and_placed_by_the_edition
      documents.each do |d|
        assert_equal({ "not_before" => 1488, "not_after" => 1488, "raw" => "1488" }, d.metadata["date"])
        assert_equal "Prague", d.metadata["place"]
      end
    end

    def test_the_edition_date_rides_the_structured_metadata_dates_lane
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["prague-bible-1488"]
    end

    def test_title_names_the_book_and_page
      assert_equal "Prague Bible 1488 — Genesis, page 23", doc("p0023").title
    end

    def test_manifest_records_both_license_statements_honestly
      manifest = Nabu::Adapters::PragueBible1488.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC BY 4.0"
      assert_includes manifest.license, "CC-BY-SA-4.0"
      assert_includes manifest.upstream_url, "10.5281/zenodo.14524858"
    end

    def test_registry_row_is_ready_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["prague-bible-1488"]
      refute_nil entry
      refute entry.wired, "wired flips only after the orchestrator's first sync"
      assert_equal "manual", entry.sync_policy
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "prague-bible-1488", name: "Prague Bible 1488",
                                          adapter_class: "Nabu::Adapters::PragueBible1488",
                                          license_class: "attribution")
      adapter = conformance_adapter
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
      assert_equal 3, first.added
      passages = db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
      assert_equal 3, second.skipped
      assert_equal passages, db[:passages].count
      assert_equal [1], db[:passages].distinct.select_map(:revision)
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only) ------------------------------------------------
    # The real zip carries ONE top-level directory (Bible_prazska_1488/),
    # stripped by ZipFetch so page/ lands at canonical/prague-bible-1488/page.

    def zip_body
      @zip_body ||= Dir.mktmpdir do |tmp|
        stage = File.join(tmp, "stage", "Bible_prazska_1488", "page")
        FileUtils.mkdir_p(stage)
        FileUtils.cp(File.join(FIXTURES, "page", "0023_DTL_547662-0024.xml"), stage)
        zip = File.join(tmp, "bible.zip")
        Dir.chdir(File.join(tmp, "stage")) { Nabu::Shell.run("zip", "-qr", zip, "Bible_prazska_1488") }
        File.binread(zip)
      end
    end

    def test_fetch_unpacks_the_page_tree_and_discover_finds_it
      stub_request(:get, Nabu::Adapters::PragueBible1488::ZIP_URL)
        .to_return(status: 200, body: zip_body, headers: { "Last-Modified" => "Thu, 19 Dec 2024 11:16:44 GMT" })
      Dir.mktmpdir do |workdir|
        report = Nabu::Adapters::PragueBible1488.new.fetch(workdir)
        assert_match(/\A\h{64}\z/, report.sha)
        assert File.file?(File.join(workdir, "page", "0023_DTL_547662-0024.xml"))
        assert_equal ["#{URN}:p0023"], Nabu::Adapters::PragueBible1488.new.discover(workdir).map(&:id)
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      stub_request(:get, Nabu::Adapters::PragueBible1488::ZIP_URL).to_return(status: 500)
      Dir.mktmpdir do |workdir|
        assert_raises(Nabu::FetchError) { Nabu::Adapters::PragueBible1488.new.fetch(workdir) }
      end
    end
  end
end
