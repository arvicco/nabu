# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # slavistics-pd — the PD German-Slavistics reference canon as
  # archive.org scans, page grain over the hOCR derivative pair, UNCORRECTED
  # OCR declared. Fixture: three census items laid out as canonical/ holds
  # them (<identifier>/<file stem>_hocr_*): Miklosich's Das Imperfect (1874,
  # whole), Kopitar's Glagolita Clozianus (1836, first 10 hOCR pages) and
  # vol. IV of Miklosich's Vergleichende Grammatik (the multi-file item,
  # spaces in the stem; first 13 pages).
  class SlavisticsPdTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("slavistics-pd")
    URN = "urn:nabu:slavistics-pd"
    KLASS = Nabu::Adapters::SlavisticsPd

    def conformance_adapter = KLASS.new(delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "slavistics-pd"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(key) = documents.find { |d| d.urn == "#{URN}:#{key}" } || flunk("#{key} missing")

    def test_discovers_the_census_items_on_disk_by_their_work_keys
      assert_equal %W[#{URN}:kopitar-clozianus-1836 #{URN}:miklosich-imperfect-1874
                      #{URN}:miklosich-vg4-syntax-1868],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_one_passage_per_non_blank_hocr_page_cited_by_its_ordinal
      d = doc("miklosich-imperfect-1874")
      assert_equal 30, d.passages.size, "34 hOCR pages, 4 blank leaves"
      assert_equal "#{URN}:miklosich-imperfect-1874:2", d.passages.first.urn
      assert_equal "PG 159 .M5 Copy 1", d.passages.first.text
      assert_equal({ "hocr_page" => 2 }, d.passages.first.annotations)
      title_page = d.passages.find { |p| p.urn.end_with?(":4") }
      assert_includes title_page.text, "DAS IMPERFECT\nIN DEN\nSLAYISCHEN SPRACHEN",
                      "OCR misreadings stay verbatim — canonical means canonical"
    end

    def test_documents_claim_the_language_of_their_prose
      assert_equal "deu", doc("miklosich-imperfect-1874").language
      clozianus = doc("kopitar-clozianus-1836")
      assert_equal "lat", clozianus.language
      assert(clozianus.passages.all? { |p| p.language == "lat" })
      assert_equal([1, 3, 7, 8, 10], clozianus.passages.map { |p| p.annotations["hocr_page"] })
    end

    def test_uncorrected_ocr_is_declared_on_every_document
      documents.each do |d|
        assert_equal "uncorrected-ocr", d.metadata["text_nature"]
        assert_includes d.metadata["ocr_note"], "Uncorrected machine OCR"
        assert_kind_of Float, d.metadata["ocr_wordlike"]
      end
      assert_in_delta 0.79, doc("miklosich-imperfect-1874").metadata["ocr_wordlike"], 0.005
    end

    def test_work_metadata_carries_the_census_facts
      meta = doc("miklosich-imperfect-1874").metadata
      assert_equal "Franz Miklosich", meta["author"]
      assert_equal "Das Imperfect in den slavischen Sprachen", meta["title"]
      assert_equal({ "not_before" => 1874, "not_after" => 1874, "raw" => "1874" }, meta["date"])
      assert_match(/Sitzungsberichte .* LXXVII\z/, meta["series"])
      assert_equal "monograph", meta["genre"]
      assert_equal({ "genre" => { "value" => "monograph" } }, meta["facets"])
      assert_equal "dasimperfectinde00mikl", meta["ia_identifier"]
      assert_equal "https://archive.org/details/dasimperfectinde00mikl", meta["ia_url"]
      assert_equal 34, meta["hocr_pages"]
      assert_equal 4, meta["blank_pages"]
      assert_equal "Franz Miklosich, Das Imperfect in den slavischen Sprachen (1874)",
                   doc("miklosich-imperfect-1874").title
    end

    def test_a_facsimile_reprint_keeps_the_first_edition_date_and_says_so
      meta = doc("miklosich-vg4-syntax-1868").metadata
      assert_equal 1868, meta.dig("date", "not_before")
      assert_equal 1874, meta.dig("date", "not_after")
      assert_includes meta["note"], "1926 Manulneudruck"
      assert_equal "4. Vergleichende Syntax (1926)", meta["ia_file"]
      assert_equal 13, doc("miklosich-vg4-syntax-1868").passages.size
    end

    def test_the_census_is_unique_and_every_item_is_well_formed
      items = KLASS::ITEMS
      assert_equal items.size, items.map(&:key).uniq.size
      assert_equal items.size, items.map { |i| [i.identifier, i.file] }.uniq.size
      assert_equal 23, items.size, "11 canon volumes + 12 Academy monographs (the ≤15 bound)"
      assert_operator items.count(&:series), :<=, 15
      items.each do |item|
        assert_match(/\A[a-z0-9-]+\z/, item.key)
        assert_includes %w[deu lat ces], item.language
        assert_operator item.date["not_before"], :<, 1931, "every print predates 1931 (PD)"
      end
    end

    def test_download_urls_percent_encode_upstream_file_names
      assert_equal "https://archive.org/download/miklosich-vergleichende-grammatik/" \
                   "4.%20Vergleichende%20Syntax%20%281926%29_hocr_searchtext.txt.gz",
                   KLASS.download_url("miklosich-vergleichende-grammatik",
                                      "4. Vergleichende Syntax (1926)_hocr_searchtext.txt.gz")
      assert_equal "https://archive.org/download/vondrak-frisinske-pamatky/" \
                   "Frisinsk%C3%A9%20pam%C3%A1tky_hocr_pageindex.json.gz",
                   KLASS.download_url("vondrak-frisinske-pamatky", "Frisinské památky_hocr_pageindex.json.gz")
    end

    def test_the_metadata_dates_lane_reads_the_structured_shape
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["slavistics-pd"]
    end

    def test_manifest_is_open_public_domain_and_declares_the_ocr
      manifest = KLASS.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "uncorrected machine OCR"
      assert_equal "ia-hocr-text", manifest.parser_family
    end

    def test_registry_row_is_registered_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["slavistics-pd"]
      refute_nil entry
      assert entry.wired, "wired: true — first sync verified 2026-10-11 (21 docs / 5,833 passages, 2 mirror stragglers)"
      assert_equal "manual", entry.sync_policy
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "slavistics-pd", name: "PD Slavistics",
                                          adapter_class: KLASS.name, license_class: "open")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, first.added
      passages = db[:passages].count
      assert_equal 30 + 5 + 13, passages
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, second.skipped
      assert_equal passages, db[:passages].count
      assert_equal [1], db[:passages].distinct.select_map(:revision)
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only) ------------------------------------------------

    IMPERFECT = KLASS::ITEMS.find { |i| i.key == "miklosich-imperfect-1874" }
    SYNTAX = KLASS::ITEMS.find { |i| i.key == "miklosich-vg4-syntax-1868" }

    def derivative_urls(item)
      Nabu::Adapters::IaHocrText.paths(File.join(FIXTURES, item.identifier), item.file).transform_values do |path|
        [KLASS.download_url(item.identifier, File.basename(path)), File.binread(path)]
      end
    end

    def stub_item(item, status: 200)
      derivative_urls(item).each_value do |url, body|
        stub_request(:get, url).to_return(status: status, body: status == 200 ? body : "")
      end
    end

    def test_fetch_lands_each_item_pair_and_discover_finds_it
      stub_item(IMPERFECT)
      stub_item(SYNTAX)
      Dir.mktmpdir do |workdir|
        report = KLASS.new(delay: 0, items: [IMPERFECT, SYNTAX]).fetch(workdir)
        assert_match(/\A\h{64}\z/, report.sha)
        assert_includes report.notes, "2/2 item(s) held (+2 this sync)"
        assert File.file?(File.join(workdir, SYNTAX.identifier,
                                    "4. Vergleichende Syntax (1926)_hocr_searchtext.txt.gz"))
        assert_equal %W[#{URN}:miklosich-imperfect-1874 #{URN}:miklosich-vg4-syntax-1868],
                     KLASS.new(delay: 0).discover(workdir).map(&:id).sort
      end
    end

    def test_fetch_follows_the_mirror_redirect
      url, body = derivative_urls(IMPERFECT).fetch(:searchtext)
      mirror = "https://ia800000.us.archive.org/0/items/dasimperfectinde00mikl/x.gz"
      stub_request(:get, url).to_return(status: 302, headers: { "Location" => mirror })
      stub_request(:get, mirror).to_return(status: 200, body: body)
      index_url, index_body = derivative_urls(IMPERFECT).fetch(:pageindex)
      stub_request(:get, index_url).to_return(status: 200, body: index_body)
      Dir.mktmpdir do |workdir|
        KLASS.new(delay: 0, items: [IMPERFECT]).fetch(workdir)
        assert_equal body, File.binread(File.join(workdir, IMPERFECT.identifier,
                                                  "dasimperfectinde00mikl_hocr_searchtext.txt.gz"))
      end
    end

    def test_a_held_item_is_never_requested_again
      stub_item(IMPERFECT)
      Dir.mktmpdir do |workdir|
        KLASS.new(delay: 0, items: [IMPERFECT]).fetch(workdir)
        WebMock.reset!
        report = KLASS.new(delay: 0, items: [IMPERFECT]).fetch(workdir)
        assert_includes report.notes, "1/1 item(s) held (+0 this sync)"
        assert_not_requested :get, /archive\.org/
      end
    end

    def test_a_flaky_mirror_is_retried
      url, body = derivative_urls(IMPERFECT).fetch(:searchtext)
      stub_request(:get, url).to_return({ status: 500 }, { status: 500 }, { status: 200, body: body })
      index_url, index_body = derivative_urls(IMPERFECT).fetch(:pageindex)
      stub_request(:get, index_url).to_return(status: 200, body: index_body)
      Dir.mktmpdir do |workdir|
        report = KLASS.new(delay: 0, items: [IMPERFECT]).fetch(workdir)
        assert_includes report.notes, "+1 this sync"
      end
    end

    def test_an_unreachable_item_is_reported_and_the_rest_lands_whole_or_not_at_all
      stub_item(IMPERFECT)
      searchtext_url, = derivative_urls(SYNTAX).fetch(:searchtext)
      index_url, index_body = derivative_urls(SYNTAX).fetch(:pageindex)
      stub_request(:get, searchtext_url).to_return(status: 500)
      stub_request(:get, index_url).to_return(status: 200, body: index_body)
      Dir.mktmpdir do |workdir|
        report = KLASS.new(delay: 0, items: [IMPERFECT, SYNTAX]).fetch(workdir)
        assert_includes report.notes, "1/2 item(s) held"
        assert_includes report.notes, "unreachable, retried next sync: miklosich-vg4-syntax-1868"
        refute Dir.exist?(File.join(workdir, SYNTAX.identifier)), "a half-fetched item writes nothing"
      end
    end

    def test_nothing_reachable_is_a_fetch_error
      stub_item(IMPERFECT, status: 500)
      Dir.mktmpdir do |workdir|
        assert_raises(Nabu::FetchError) { KLASS.new(delay: 0, items: [IMPERFECT]).fetch(workdir) }
      end
    end
  end
end
