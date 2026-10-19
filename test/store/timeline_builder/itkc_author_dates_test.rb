# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

module Store
  # The ITKC author-era lane: okhc's klc munjip records and the held itkc
  # fascicles both carry the ITKC work id in their urns (okhc
  # "urn:nabu:okhc:klc:ITKC_MO_0004A_0010_…", itkc "urn:nabu:itkc:mo-1247a-0010");
  # the itkc-catalog module's 서지 records band each work by its author's
  # life years — a composition-class row labeled by lane (axis_source
  # "<slug>-authors") and by the record it came from (date_raw). A
  # document the metadata lane already dates keeps its own claim alone.
  class ItkcAuthorDatesTest < Minitest::Test
    include StoreTestDB

    LANE = Nabu::Store::TimelineBuilder::ItkcAuthorDates
    # The fixture tree IS a canonical root: test/fixtures/itkc-catalog.
    CANONICAL = File.dirname(Nabu::TestSupport.fixtures("itkc-catalog"))

    def setup
      @db = store_test_db
    end

    def seed(slug, urn, metadata: {}, withdrawn: false)
      source = Nabu::Store::Source.where(slug: slug).first ||
               Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "T",
                                          license_class: "attribution")
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: urn, language: "lzh",
        content_sha256: urn, revision: 1, withdrawn: withdrawn,
        metadata_json: JSON.generate(metadata)
      )
    end

    def okhc(id) = "urn:nabu:okhc:klc:ITKC_MO_#{id}_0010_010_0010"

    def rows_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id)).all
    end

    def test_an_okhc_munjip_record_takes_its_authors_life_band
      seed("okhc", okhc("0004A"))
      counts = LANE.build(catalog: @db, canonical_dir: CANONICAL)
      row = rows_for(okhc("0004A")).fetch(0)
      assert_equal [1168, 1241], [row[:not_before], row[:not_after]]
      assert_equal "era", row[:precision]
      assert_equal "composition", row[:date_class]
      assert_equal "okhc-authors", row[:axis_source]
      assert_equal "저자 이규보 李奎報 1168–1241 (ITKC_MO_0004A 서지)", row[:date_raw]
      assert_equal 1, counts.fetch("okhc").fetch(:documents)
    end

    def test_every_record_of_one_munjip_shares_the_band
      seed("okhc", okhc("1250A"))
      seed("okhc", "urn:nabu:okhc:klc:ITKC_MO_1250A_0020_030_0110")
      LANE.build(catalog: @db, canonical_dir: CANONICAL)
      assert_equal [[1839, 1912]] * 2,
                   @db[:document_axes].where(axis_source: "okhc-authors").select_map(%i[not_before not_after])
    end

    def test_undated_unmatched_and_out_of_scope_records_are_counted_never_guessed
      seed("okhc", okhc("0672A")) # in the catalog, but nothing bounds the work above
      seed("okhc", okhc("0002A")) # a work id the catalog does not hold
      seed("okhc", "urn:nabu:okhc:sagi:sagi_0001") # not a munjip record at all
      counts = LANE.build(catalog: @db, canonical_dir: CANONICAL).fetch("okhc")
      assert_equal({ documents: 0, undated: 1, unmatched: 1, already_dated: 0 }, counts)
      assert_equal 0, @db[:document_axes].count
    end

    def test_a_document_the_metadata_lane_dates_keeps_its_own_claim_alone
      seed("okhc", okhc("0004A"), metadata: { "year" => 1240 })
      seed("itkc", "urn:nabu:itkc:mo-1250a-0010",
           metadata: { "date" => { "not_before" => 1912, "not_after" => 1912, "raw" => "1912" } })
      Nabu::Store::TimelineBuilder::MetadataDates.build(catalog: @db)
      counts = LANE.build(catalog: @db, canonical_dir: CANONICAL)
      assert_equal 1, counts.fetch("okhc").fetch(:already_dated)
      assert_equal 1, counts.fetch("itkc").fetch(:already_dated)
      assert_equal(%w[okhc], rows_for(okhc("0004A")).map { |row| row[:axis_source] })
      assert_equal(%w[itkc], rows_for("urn:nabu:itkc:mo-1250a-0010").map { |row| row[:axis_source] })
    end

    def test_a_silver_estimate_is_no_upstream_claim
      doc = seed("okhc", okhc("0004A"))
      @db[:document_axes].insert(document_id: doc.id, not_before: 1500, not_after: 1600,
                                 date_class: "silver", axis_source: "silver-dates")
      LANE.build(catalog: @db, canonical_dir: CANONICAL)
      assert_equal %w[okhc-authors silver-dates], rows_for(okhc("0004A")).map { |row| row[:axis_source] }.sort
    end

    def test_itkc_fascicles_join_across_the_mo_and_go_catalogs
      seed("itkc", "urn:nabu:itkc:mo-1247a-0010")
      seed("itkc", "urn:nabu:itkc:mo-1255a-0020")
      seed("itkc", "urn:nabu:itkc:go-1432a-0140")
      seed("itkc", "urn:nabu:itkc:kp-c004a-0010") # compiler unknown — stays undated
      seed("itkc", "urn:nabu:itkc:mo-1247a-0010-010-0010", withdrawn: true)
      counts = LANE.build(catalog: @db, canonical_dir: CANONICAL).fetch("itkc")
      assert_equal({ documents: 3, undated: 1, unmatched: 0, already_dated: 0 }, counts)
      assert_equal [1834, 1906], rows_for("urn:nabu:itkc:mo-1247a-0010").fetch(0).values_at(:not_before, :not_after)
      assert_equal [1814, 1888], rows_for("urn:nabu:itkc:go-1432a-0140").fetch(0).values_at(:not_before, :not_after)
      assert_equal "itkc-authors", rows_for("urn:nabu:itkc:mo-1255a-0020").fetch(0)[:axis_source]
    end

    def test_one_sided_bands_keep_their_open_side_open
      seed("okhc", okhc("0009A"))
      seed("okhc", okhc("0003A"))
      LANE.build(catalog: @db, canonical_dir: CANONICAL)
      assert_equal [nil, 1304], rows_for(okhc("0009A")).fetch(0).values_at(:not_before, :not_after)
      assert_equal [nil, 1713], rows_for(okhc("0003A")).fetch(0).values_at(:not_before, :not_after)
    end

    def test_an_absent_catalog_is_a_clean_no_op
      seed("okhc", okhc("0004A"))
      Dir.mktmpdir do |empty|
        counts = LANE.build(catalog: @db, canonical_dir: empty)
        assert_equal 0, counts.fetch("okhc").fetch(:documents)
      end
      assert_equal 0, @db[:document_axes].count
    end

    def test_refresh_replaces_the_lane_for_its_targets_and_the_catalog_only
      seed("okhc", okhc("0004A"))
      seed("itkc", "urn:nabu:itkc:mo-1247a-0010")
      LANE.build(catalog: @db, canonical_dir: CANONICAL)
      assert_equal 1, LANE.refresh_source!(catalog: @db, canonical_dir: CANONICAL, slug: "okhc")
      assert_equal 2, LANE.refresh_source!(catalog: @db, canonical_dir: CANONICAL, slug: "itkc-catalog")
      assert_equal 1, LANE.refresh_source!(catalog: @db, canonical_dir: CANONICAL, slug: "itkc")
      assert_equal 2, @db[:document_axes].count, "refresh never duplicates"
      assert_equal 0, LANE.refresh_source!(catalog: @db, canonical_dir: CANONICAL, slug: "edh")
      assert_equal 2, @db[:document_axes].count
    end

    def test_the_timeline_rebuild_runs_the_lane_after_the_metadata_lane
      seed("okhc", okhc("0004A"))
      seed("okhc", okhc("1250A"), metadata: { "year" => 1900 })
      summary = Nabu::Store::TimelineBuilder.rebuild!(catalog: @db, canonical_dir: CANONICAL)
      assert_equal 1, summary.itkc_authors.fetch("okhc").fetch(:documents)
      assert_equal 1, summary.itkc_authors.fetch("okhc").fetch(:already_dated)
      assert_equal(%w[okhc], rows_for(okhc("1250A")).map { |row| row[:axis_source] })
    end
  end
end
