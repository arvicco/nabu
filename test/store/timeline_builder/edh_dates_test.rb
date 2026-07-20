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

    def test_open_ended_not_before_only_leaves_not_after_null
      with_csv_row("hd_nr" => "HD900002", "dat_jahr_a" => "212") do |dir|
        make_document("urn:nabu:edh:hd900002")
        counts = build!(canonical_dir: dir)
        row = timeline_for("urn:nabu:edh:hd900002")
        assert_equal 212, row.fetch(:not_before)
        assert_nil row.fetch(:not_after)
        assert_equal "range", row.fetch(:precision)
        assert_equal "212–", row.fetch(:date_raw)
        assert_equal 0, counts[:undated]
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

    HEADERS = %w[hd_nr fo_antik fo_modern pl_ancient_loc1 geo_id1 dat_jahr_a dat_jahr_e].freeze

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
