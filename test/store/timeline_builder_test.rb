# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::TimelineBuilder (P15-2): the date/place extractors over trimmed-real
  # HGV fixtures (test/fixtures/timeline/) + catalog-side goo300k/IMP year suffixes.
  # A fresh in-memory catalog seeded with the DDbDP documents the HGV records
  # join to, so the ddb-hybrid↔urn join is exercised end to end.
  class TimelineBuilderTest < Minitest::Test
    include StoreTestDB

    FIXTURE_DIR = File.expand_path("../fixtures/timeline", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "papyri-ddbdp", name: "DDbDP", adapter_class: "T", license_class: "open"
      )
    end

    def make_document(urn, source: @source, language: "grc")
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: urn, language: language,
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def timeline_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id)).first
    end

    def build!
      Nabu::Store::TimelineBuilder.rebuild!(catalog: @db, canonical_dir: FIXTURE_DIR)
    end

    # -- HGV extractor: the five date shapes ----------------------------------

    def test_bce_point_is_stored_verbatim
      make_document("urn:nabu:ddbdp:bgu:3:994")
      build!
      row = timeline_for("urn:nabu:ddbdp:bgu:3:994")
      assert_equal(-113, row.fetch(:not_before))
      assert_equal(-113, row.fetch(:not_after))
      assert_equal "exact", row.fetch(:precision)
      assert_equal "Pathyris", row.fetch(:place_name)
      assert_equal "26. Aug. 113 v.Chr.", row.fetch(:date_raw)
      assert_equal "hgv", row.fetch(:axis_source)
      assert_includes row.fetch(:place_ref), "pleiades.stoa.org/places/786084"
    end

    def test_ce_range_keeps_both_bounds_and_precision
      make_document("urn:nabu:ddbdp:bgu:2:402")
      build!
      row = timeline_for("urn:nabu:ddbdp:bgu:2:402")
      assert_equal 591, row.fetch(:not_before)
      assert_equal 602, row.fetch(:not_after)
      assert_equal "low", row.fetch(:precision)
      assert_equal "Arsinoites", row.fetch(:place_name)
    end

    def test_open_ended_notafter_leaves_not_before_null
      make_document("urn:nabu:ddbdp:p.cair.zen:1:59108")
      build!
      row = timeline_for("urn:nabu:ddbdp:p.cair.zen:1:59108")
      assert_nil row.fetch(:not_before) # −∞
      assert_equal(-257, row.fetch(:not_after))
    end

    def test_undated_but_placed_document_gets_a_place_only_row
      make_document("urn:nabu:ddbdp:sb:1:4471")
      build!
      row = timeline_for("urn:nabu:ddbdp:sb:1:4471")
      refute_nil row
      assert_nil row.fetch(:not_before)
      assert_nil row.fetch(:not_after)
      assert_equal "Pathyris", row.fetch(:place_name)
    end

    def test_multiple_alternative_origdates_envelope_min_max
      make_document("urn:nabu:ddbdp:p.cair.zen:3:59354")
      build!
      row = timeline_for("urn:nabu:ddbdp:p.cair.zen:3:59354")
      assert_equal(-244, row.fetch(:not_before)) # min of the two alternatives
      assert_equal(-243, row.fetch(:not_after))  # max of the two alternatives
    end

    def test_hgv_record_without_a_matching_document_is_skipped
      # No DDbDP document created for bgu;3;994 → no timeline row, no crash.
      build!
      assert_equal 0, @db[:document_axes].count
    end

    def test_summary_counts_files_and_rows
      make_document("urn:nabu:ddbdp:bgu:3:994")
      summary = build!
      assert_equal 5, summary.hgv_files # five fixture files scanned
      assert_equal 1, summary.hgv       # one joined to a catalog document
    end

    # -- goo300k / IMP: year off the urn suffix -------------------------------

    def test_goo300k_year_from_urn_suffix
      src = Nabu::Store::Source.create(slug: "goo300k", name: "goo", adapter_class: "T", license_class: "open")
      make_document("urn:nabu:goo300k:zrc_00001-1584", source: src, language: "sla")
      summary = build!
      row = timeline_for("urn:nabu:goo300k:zrc_00001-1584")
      assert_equal 1584, row.fetch(:not_before)
      assert_equal 1584, row.fetch(:not_after)
      assert_equal "goo300k", row.fetch(:axis_source)
      assert_equal 1, summary.goo300k
    end

    def test_imp_year_from_urn_suffix
      src = Nabu::Store::Source.create(slug: "imp", name: "imp", adapter_class: "T", license_class: "open")
      make_document("urn:nabu:imp:wiki00266-1889", source: src, language: "sla")
      build!
      row = timeline_for("urn:nabu:imp:wiki00266-1889")
      assert_equal 1889, row.fetch(:not_before)
      assert_equal "imp", row.fetch(:axis_source)
    end

    # -- rebuild-safety: a second build replaces, never duplicates ------------

    def test_rebuild_is_idempotent
      make_document("urn:nabu:ddbdp:bgu:3:994")
      build!
      build!
      assert_equal 1, @db[:document_axes].where(document_id: @db[:documents].first[:id]).count
    end
  end
end
