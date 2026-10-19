# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Adapters
  # Nabu::Adapters::ItkcCatalog — the ITKC 한국고전종합DB 서지
  # (bibliographic) catalog as a feature module: discover mints nothing,
  # fetch pages the keyless OpenAPI's MO_SJ / GO_SJ / KP_SJ sections into
  # <section>/<start>.xml, all-or-nothing, paced, breaker-guarded. The
  # record reader and band rules are tested with the builders
  # (test/store/timeline_builder/itkc_catalog_records_test.rb). No
  # network: WebMock stubs.
  class ItkcCatalogTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("itkc-catalog")
    CATALOG = Nabu::Store::TimelineBuilder::ItkcCatalogRecords
    ADAPTER = Nabu::Adapters::ItkcCatalog
    API = "https://db.itkc.or.kr/openapi/search"

    # --- registry / module shape ------------------------------------------------

    def test_registry_carries_the_module_row_manual_and_unwired
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["itkc-catalog"]
      refute_nil entry, "itkc-catalog must be registered in config/sources.yml"
      assert entry.feature_module?
      assert_equal "manual", entry.sync_policy
    end

    def test_manifest_records_the_terms_and_a_conservative_class
      manifest = ADAPTER.manifest
      assert_equal "itkc-catalog", manifest.id
      assert_equal "nc", manifest.license_class
      assert_includes manifest.license, "소중한 국가정보화자원을 외부에서 이용하여"
      assert_includes manifest.license, "이용허락범위 제한 없음"
    end

    def test_discover_yields_no_documents_and_parse_is_unreachable
      adapter = ADAPTER.new
      assert_empty adapter.discover(FIXTURES).to_a
      ref = Nabu::DocumentRef.new(source_id: "itkc-catalog", id: "urn:nabu:itkc-catalog:x", path: FIXTURES,
                                  metadata: {})
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end

    # --- fetch ------------------------------------------------------------------

    # A response in the live API's exact shape (the fixtures' header and doc
    # layout), carrying synthetic ids — the paging contract under test.
    def page_body(section, start, total, ids)
      docs = ids.map do |id|
        "<doc>\n\t<field name='서지ID'>#{id}</field>\n\t<field name='저자'>가|假</field>\n" \
          "\t<field name='저자생년'>1600</field>\n\t<field name='저자몰년'>1650</field>\n" \
          "\t<field name='서명'>t</field>\n\t<field name='간행년'>1700</field>\n</doc>\n"
      end
      "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<response>\n<header>\n" \
        "\t<field name='secId'>#{section}</field>\n\t<field name='keyword'></field>\n" \
        "\t<field name='start'>#{start}</field>\n\t<field name='rows'>2</field>\n" \
        "\t<field name='totalCount'>#{total}</field>\n</header>\n<result>\n#{docs.join}</result>\n</response>\n"
    end

    # Fetch tests page at 2 rows so the paging is exercised on small bodies
    # (the live page size is ADAPTER::PAGE_ROWS, the server's own cap).
    def adapter = ADAPTER.new(delay: 0, page_rows: 2)

    def page_url_rows(section, start) = "#{API}?secId=#{section}&start=#{start}&rows=2"

    def stub_paged(section, total, ids_by_start)
      ids_by_start.each do |start, ids|
        stub_request(:get, page_url_rows(section, start))
          .to_return(status: 200, body: page_body(section, start, total, ids))
      end
    end

    def stub_full_catalog(mo_ids: %w[ITKC_MO_0001A ITKC_MO_0002A ITKC_MO_0003A])
      stub_paged("MO_SJ", mo_ids.size, mo_ids.each_slice(2).with_index.to_h { |ids, i| [i * 2, ids] })
      stub_paged("GO_SJ", 1, { 0 => %w[ITKC_GO_0001A] })
      stub_paged("KP_SJ", 1, { 0 => %w[ITKC_KP_A001A] })
    end

    def test_fetch_pages_every_section_into_start_named_files
      stub_full_catalog
      Dir.mktmpdir do |workdir|
        report = adapter.fetch(workdir)
        assert_equal %w[GO_SJ/0000.xml KP_SJ/0000.xml MO_SJ/0000.xml MO_SJ/0002.xml],
                     Dir.glob("**/*.xml", base: workdir).sort
        assert_equal 5, CATALOG.records(workdir).size
        assert_match(/\A\h{64}\z/, report.sha)
        assert_includes report.notes, "MO_SJ 3"
      end
    end

    def test_refetch_of_an_unchanged_catalog_keeps_the_sha
      stub_full_catalog
      Dir.mktmpdir do |workdir|
        first = adapter.fetch(workdir)
        second = adapter.fetch(workdir)
        assert_equal first.sha, second.sha
      end
    end

    def test_a_short_page_refuses_and_leaves_the_held_catalog_untouched
      stub_full_catalog
      Dir.mktmpdir do |workdir|
        adapter.fetch(workdir)
        held = File.read(File.join(workdir, "MO_SJ", "0000.xml"))
        WebMock.reset!
        stub_paged("MO_SJ", 3, { 0 => %w[ITKC_MO_0001A], 2 => %w[ITKC_MO_0003A] })
        stub_paged("GO_SJ", 1, { 0 => %w[ITKC_GO_0001A] })
        stub_paged("KP_SJ", 1, { 0 => %w[ITKC_KP_A001A] })
        error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
        assert_match(/MO_SJ.*start 0.*1 of 2/, error.message)
        assert_equal held, File.read(File.join(workdir, "MO_SJ", "0000.xml"))
      end
    end

    def test_a_non_xml_answer_refuses
      stub_request(:get, page_url_rows("MO_SJ", 0)).to_return(status: 200, body: "<html>maintenance</html>")
      Dir.mktmpdir do |workdir|
        assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
        assert_empty Dir.glob("**/*.xml", base: workdir)
      end
    end

    def test_an_http_error_refuses
      stub_request(:get, page_url_rows("MO_SJ", 0)).to_return(status: 503)
      Dir.mktmpdir do |workdir|
        assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      end
    end

    def test_a_shrunken_catalog_trips_the_breaker_unless_forced
      stub_full_catalog(mo_ids: %w[ITKC_MO_0001A ITKC_MO_0002A ITKC_MO_0003A ITKC_MO_0004A ITKC_MO_0005A])
      Dir.mktmpdir do |workdir|
        adapter.fetch(workdir)
        WebMock.reset!
        stub_full_catalog(mo_ids: %w[ITKC_MO_0001A ITKC_MO_0002A])
        assert_raises(Nabu::SyncAborted) { adapter.fetch(workdir) }
        assert File.file?(File.join(workdir, "MO_SJ", "0004.xml")), "a tripped breaker touches nothing"
        adapter.fetch(workdir, force: true)
        refute File.file?(File.join(workdir, "MO_SJ", "0004.xml")), "the stale page leaves the live tree"
        assert File.file?(File.join(workdir, ".attic", "MO_SJ", "0004.xml")), "…into the attic, never deleted"
        assert_equal 4, CATALOG.records(workdir).size
      end
    end

    def test_requests_are_paced
      stub_full_catalog
      naps = []
      paced = ADAPTER.new(delay: 1.5, page_rows: 2, sleeper: ->(seconds) { naps << seconds })
      Dir.mktmpdir { |workdir| paced.fetch(workdir) }
      assert_equal [1.5] * 3, naps, "4 requests, a pause before every one but the first"
    end
  end
end
