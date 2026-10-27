# frozen_string_literal: true

require "test_helper"
require "csv"
require "fileutils"
require "tmpdir"

module Store
  # Nabu::Store::TimelineBuilder::EdhDates (P17-2): EDH CSV dating/findspot over
  # the checked-in edh fixture CSV (test/fixtures/edh/text/), plus tmp-CSV
  # edge cases (signed BCE years, open-ended bounds, the year-0 tripwire) the
  # three fixture records — all CE closed ranges — cannot carry.
  class EdhDatesTest < Minitest::Test
    include StoreTestDB

    # canonical_dir/<edh>/text/edh_data_text.csv — the fixtures root IS the
    # canonical layout for the extractor's purposes.
    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "edh", name: "EDH", adapter_class: "T", license_class: "attribution"
      )
    end

    def make_document(urn)
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: urn, language: "lat",
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def timeline_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id)).first
    end

    def build!(canonical_dir: FIXTURES_ROOT)
      Nabu::Store::TimelineBuilder::EdhDates.build(catalog: @db, canonical_dir: canonical_dir)
    end

    # -- the fixture records (real rows) ---------------------------------------

    def test_ce_range_with_ancient_findspot_and_pleiades_ref
      make_document("urn:nabu:edh:hd000001")
      counts = build!
      row = timeline_for("urn:nabu:edh:hd000001")
      assert_equal 71, row.fetch(:not_before)
      assert_equal 130, row.fetch(:not_after)
      assert_equal "range", row.fetch(:precision)
      assert_equal "71–130", row.fetch(:date_raw)
      assert_equal "Cumae, bei", row.fetch(:place_name), "ancient findspot wins"
      assert_equal "https://pleiades.stoa.org/places/432808", row.fetch(:place_ref)
      assert_equal "edh", row.fetch(:axis_source)
      assert_equal 1, counts[:documents]
    end

    # P104-1: the koordinaten1 findspot pair — the WGS84 lane the
    # rundata precedent opened (migration 027) finally reads EDH's own
    # column (79,488 of 82,450 rows filled at the 2026-09-26 census).
    def test_findspot_coordinates_ride_the_axes
      make_document("urn:nabu:edh:hd000001")
      build!
      row = timeline_for("urn:nabu:edh:hd000001")
      assert_in_delta 40.8471577, row.fetch(:place_lat)
      assert_in_delta 14.0550756, row.fetch(:place_lon)
    end

    def test_malformed_or_lone_coordinates_mint_nothing
      with_csv_row("hd_nr" => "HD900007", "fo_antik" => "Roma",
                   "koordinaten1" => "41.895466") do |dir|
        make_document("urn:nabu:edh:hd900007")
        build!(canonical_dir: dir)
        row = timeline_for("urn:nabu:edh:hd900007")
        assert_nil row.fetch(:place_lat), "a lone coordinate is not a point — never guessed"
        assert_nil row.fetch(:place_lon)
      end
    end

    def test_coordinates_alone_place_a_document
      with_csv_row("hd_nr" => "HD900008", "koordinaten1" => "30.578611,34.817778") do |dir|
        make_document("urn:nabu:edh:hd900008")
        counts = build!(canonical_dir: dir)
        row = timeline_for("urn:nabu:edh:hd900008")
        assert_in_delta 30.578611, row.fetch(:place_lat)
        assert_nil row.fetch(:place_name)
        assert_equal 1, counts[:documents]
      end
    end

    def test_modern_findspot_and_geonames_fall_back_when_no_ancient_place
      make_document("urn:nabu:edh:hd080825")
      build!
      row = timeline_for("urn:nabu:edh:hd080825")
      assert_equal 151, row.fetch(:not_before)
      assert_equal 250, row.fetch(:not_after)
      assert_equal "Morken - Harff", row.fetch(:place_name)
      assert_equal "https://www.geonames.org/2869232", row.fetch(:place_ref)
    end

    def test_rows_without_a_catalog_document_are_not_counted
      counts = build! # no documents seeded at all
      assert_equal({ documents: 0, undated: 0, invalid: 0 }, counts)
      assert_equal 0, @db[:document_axes].count
    end

    # -- edge cases the fixtures cannot carry (tmp CSVs, unit grain) -----------

    def test_signed_bce_years_ingest_verbatim_no_year_zero_shift
      with_csv_row("hd_nr" => "HD900001", "dat_jahr_a" => "-20", "dat_jahr_e" => "-1") do |dir|
        make_document("urn:nabu:edh:hd900001")
        build!(canonical_dir: dir)
        row = timeline_for("urn:nabu:edh:hd900001")
        assert_equal(-20, row.fetch(:not_before))
        assert_equal(-1, row.fetch(:not_after), "-1 = 1 BCE, historical numbering (conventions §11)")
      end
    end

    # A lone dat_jahr_a is EDH's spelling of a POINT year, not an open
    # range: the record's own EpiDoc carries <origDate when-custom="…"> for
    # 3,528 of the 3,529 such rows (2026-10-22 census; the 3,529th has no
    # origDate attributes at all). The earlier open-ended reading
    # (not_after NULL, "212–") contradicted upstream's XML.
    def test_lone_dat_jahr_a_is_a_point_year
      with_csv_row("hd_nr" => "HD900002", "dat_jahr_a" => "212") do |dir|
        make_document("urn:nabu:edh:hd900002")
        counts = build!(canonical_dir: dir)
        row = timeline_for("urn:nabu:edh:hd900002")
        assert_equal 212, row.fetch(:not_before)
        assert_equal 212, row.fetch(:not_after)
        assert_equal "year", row.fetch(:precision)
        assert_equal "212", row.fetch(:date_raw)
        assert_equal 0, counts[:undated]
      end
    end

    # GODOT-dated records carry upstream's day and month (dat_tag /
    # dat_monat) — HD072020, the Siscia altar of 22 May 217 (real row,
    # test/fixtures/edh_identities). The typed day rides the same artifact
    # row: precision "day", date_raw the ISO-shaped signed date.
    def test_day_and_month_on_a_point_year_are_day_precision
      make_document("urn:nabu:edh:hd072020")
      build!(canonical_dir: File.join(FIXTURES_ROOT, "edh_identities"))
      row = timeline_for("urn:nabu:edh:hd072020")
      assert_equal [217, 217], row.values_at(:not_before, :not_after)
      assert_equal "day", row.fetch(:precision)
      assert_equal "217-05-22", row.fetch(:date_raw)
      assert_nil row.fetch(:date_class), "an upstream artifact date (the NULL class)"
    end

    def test_month_without_a_day_is_month_precision
      with_csv_row("hd_nr" => "HD900009", "dat_monat" => "3", "dat_jahr_a" => "-44") do |dir|
        make_document("urn:nabu:edh:hd900009")
        build!(canonical_dir: dir)
        row = timeline_for("urn:nabu:edh:hd900009")
        assert_equal "month", row.fetch(:precision)
        assert_equal "-44-03", row.fetch(:date_raw)
      end
    end

    # A day within a year RANGE (a festival day of an undated year — 299
    # rows) keeps the range; the day rides the display string only.
    def test_day_on_a_year_range_keeps_the_range
      with_csv_row("hd_nr" => "HD900010", "dat_tag" => "13", "dat_monat" => "7",
                   "dat_jahr_a" => "171", "dat_jahr_e" => "230") do |dir|
        make_document("urn:nabu:edh:hd900010")
        build!(canonical_dir: dir)
        row = timeline_for("urn:nabu:edh:hd900010")
        assert_equal "range", row.fetch(:precision)
        assert_equal "171–230 (day 13.7.)", row.fetch(:date_raw)
      end
    end

    def test_point_year_gets_year_precision
      with_csv_row("hd_nr" => "HD900003", "dat_jahr_a" => "79", "dat_jahr_e" => "79") do |dir|
        make_document("urn:nabu:edh:hd900003")
        build!(canonical_dir: dir)
        assert_equal "year", timeline_for("urn:nabu:edh:hd900003").fetch(:precision)
      end
    end

    def test_year_zero_is_skipped_counted_never_stored
      with_csv_row("hd_nr" => "HD900004", "dat_jahr_a" => "0", "dat_jahr_e" => "14") do |dir|
        make_document("urn:nabu:edh:hd900004")
        counts = build!(canonical_dir: dir)
        assert_equal 1, counts[:invalid]
        assert_equal 0, @db[:document_axes].count
      end
    end

    def test_undated_but_placed_document_gets_a_place_only_row
      with_csv_row("hd_nr" => "HD900005", "fo_antik" => "Roma") do |dir|
        make_document("urn:nabu:edh:hd900005")
        counts = build!(canonical_dir: dir)
        row = timeline_for("urn:nabu:edh:hd900005")
        assert_nil row.fetch(:not_before)
        assert_nil row.fetch(:precision)
        assert_equal "Roma", row.fetch(:place_name)
        assert_equal 1, counts[:undated]
        assert_equal 1, counts[:documents]
      end
    end

    def test_undated_unplaced_document_gets_no_row
      with_csv_row("hd_nr" => "HD900006") do |dir|
        make_document("urn:nabu:edh:hd900006")
        counts = build!(canonical_dir: dir)
        assert_equal 0, @db[:document_axes].count
        assert_equal 1, counts[:undated]
        assert_equal 0, counts[:documents]
      end
    end

    def test_missing_csv_is_a_quiet_zero
      Dir.mktmpdir do |dir|
        assert_equal({ documents: 0, undated: 0, invalid: 0 }, build!(canonical_dir: dir))
      end
    end

    # -- full-rebuild wiring -----------------------------------------------------

    def test_timeline_builder_rebuild_includes_edh_in_the_summary
      make_document("urn:nabu:edh:hd000001")
      summary = Nabu::Store::TimelineBuilder.rebuild!(catalog: @db, canonical_dir: FIXTURES_ROOT)
      assert_equal 1, summary.edh
      assert_operator summary.total, :>=, 1
    end

    HEADERS = %w[hd_nr fo_antik fo_modern pl_ancient_loc1 koordinaten1 geo_id1
                 dat_tag dat_monat dat_jahr_a dat_jahr_e].freeze

    private

    # A minimal canonical dir whose edh/text CSV holds one row with +fields+
    # (CSV cells, not TEI — the fixture-realism rule concerns markup).
    def with_csv_row(fields)
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "edh", "text"))
        CSV.open(File.join(dir, "edh", "text", "edh_data_text.csv"), "w",
                 write_headers: true, headers: HEADERS) do |csv|
          csv << HEADERS.map { |header| fields[header] }
        end
        yield dir
      end
    end
  end
end
