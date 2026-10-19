# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Store
  # Store::TimelineBuilder::ItkcCatalogRecords — the itkc-catalog module's
  # held OpenAPI 서지 pages read into one record per ITKC work (title,
  # author forms, birth/death/print years with the 0/9999/미상 unknowns as
  # nil) and the author-era band the ItkcAuthorDates lane mints.
  # Trimmed-real fixtures (test/fixtures/itkc-catalog/README.md).
  class ItkcCatalogRecordsTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("itkc-catalog")
    CATALOG = Nabu::Store::TimelineBuilder::ItkcCatalogRecords

    def records
      @records ||= CATALOG.records(FIXTURES)
    end

    def record(id) = records.fetch(id)

    # --- the page read ----------------------------------------------------------

    def test_every_section_page_is_read_keyed_by_the_bibliographic_id
      assert_equal %w[ITKC_GO_1432A ITKC_KP_C004A ITKC_MO_0001A ITKC_MO_0003A ITKC_MO_0004A
                      ITKC_MO_0009A ITKC_MO_0672A ITKC_MO_1247A ITKC_MO_1250A ITKC_MO_1255A],
                   records.keys.sort
    end

    def test_a_record_carries_title_author_forms_and_years
      simseok = record("ITKC_MO_1250A")
      assert_equal "심석재집(心石齋集)", simseok.title
      assert_equal "송병순", simseok.author_hangul
      assert_equal "宋秉珣", simseok.author_hanja
      assert_equal [1839, 1912, 1912], [simseok.birth, simseok.death, simseok.print_year]
    end

    def test_the_unknown_sentinels_read_as_nil
      choe = record("ITKC_MO_0001A")
      assert_equal 857, choe.birth
      assert_nil choe.death, "저자몰년 9999 is the catalog's unknown filler"
      hong = record("ITKC_MO_0009A")
      assert_nil hong.birth, "저자생년 0 is the catalog's unknown filler (there is no year 0)"
      assert_equal 1304, hong.death
      assert_nil record("ITKC_MO_0004A").print_year, "간행년 미상 is prose, not a year"
      unknown = record("ITKC_KP_C004A")
      assert_equal "미상", unknown.author_hangul
      assert_nil unknown.author_hanja
    end

    def test_parse_page_reports_the_header_census
      page = CATALOG.parse_page(File.read(File.join(FIXTURES, "MO_SJ", "1000.xml")))
      assert_equal "MO_SJ", page.section
      assert_equal 1000, page.start
      assert_equal 1259, page.total
      assert_equal 3, page.records.size
    end

    def test_attic_pages_are_never_read
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "GO_SJ"), dir)
        FileUtils.mkdir_p(File.join(dir, ".attic", "MO_SJ"))
        FileUtils.cp(File.join(FIXTURES, "MO_SJ", "0000.xml"), File.join(dir, ".attic", "MO_SJ"))
        assert_equal %w[ITKC_GO_1432A], CATALOG.records(dir).keys
      end
    end

    def test_an_absent_directory_reads_empty
      assert_equal({}, CATALOG.records(File.join(FIXTURES, "nope")))
    end

    # --- the author-era band ----------------------------------------------------

    def test_birth_and_death_band_the_author_life
      band = CATALOG.band(record("ITKC_MO_0004A"))
      assert_equal [1168, 1241], [band.not_before, band.not_after]
      assert_equal "저자 이규보 李奎報 1168–1241 (ITKC_MO_0004A 서지)", band.raw
    end

    def test_a_known_death_alone_bounds_above_and_leaves_the_lower_side_open
      band = CATALOG.band(record("ITKC_MO_0009A"))
      assert_equal [nil, 1304], [band.not_before, band.not_after]
      assert_equal "저자 홍간 洪侃 ?–1304 (ITKC_MO_0009A 서지)", band.raw
    end

    def test_an_unknown_death_falls_back_to_the_original_print_year_as_terminus
      band = CATALOG.band(record("ITKC_MO_0001A"))
      assert_equal [857, 1834], [band.not_before, band.not_after]
      assert_equal "저자 최치원 崔致遠 857–? · 원문간행년 1834 (ITKC_MO_0001A 서지)", band.raw
      neither = CATALOG.band(record("ITKC_MO_0003A"))
      assert_equal [nil, 1713], [neither.not_before, neither.not_after],
                   "no life years at all: the print year alone is still an honest terminus ante quem"
    end

    def test_nothing_bounding_the_work_above_mints_no_band
      assert_nil CATALOG.band(record("ITKC_MO_0672A")), "birth 1490, death and print year unknown"
      assert_nil CATALOG.band(record("ITKC_KP_C004A")), "author, years and print all unknown"
    end

    def test_a_print_year_before_the_birth_is_no_terminus
      odd = CATALOG::Record.new(id: "ITKC_MO_9999A", section: "MO_SJ", title: "t", author_hangul: "가",
                                author_hanja: nil, birth: 1700, death: nil, print_year: 1650)
      assert_nil CATALOG.band(odd)
    end
  end
end
