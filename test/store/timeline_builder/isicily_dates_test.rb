# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::TimelineBuilder::IsicilyDates (P29-4): I.Sicily origDate/
  # origPlace → the timeline, over the checked-in isicily fixture
  # records (test/fixtures/isicily/inscriptions/) — the -custom Julian
  # attributes as signed years, ancient-over-modern place names, Pleiades
  # refs over GeoNames, metadata-only records still joining (their header
  # is most of their machine-readable value).
  class IsicilyDatesTest < Minitest::Test
    include StoreTestDB

    # canonical_dir/<isicily>/inscriptions/*.xml — the fixtures root IS
    # the canonical layout for the extractor's purposes.
    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "isicily", name: "I.Sicily", adapter_class: "T", license_class: "attribution"
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

    def build!
      Nabu::Store::TimelineBuilder::IsicilyDates.build(catalog: @db, canonical_dir: FIXTURES_ROOT)
    end

    def test_ce_range_with_modern_findspot_and_geonames_ref
      make_document("urn:nabu:isicily:isic000001")
      counts = build!
      row = timeline_for("urn:nabu:isicily:isic000001")
      assert_equal 51, row.fetch(:not_before), "notBefore-custom, base-10 (\"0051\" is not octal)"
      assert_equal 300, row.fetch(:not_after)
      assert_equal "range", row.fetch(:precision)
      assert_equal "between later 1st and 3rd century CE", row.fetch(:date_raw)
      assert_equal "Caltanissetta", row.fetch(:place_name),
                   "the ancient placeName is empty — the modern one is the honest fallback"
      assert_equal "http://sws.geonames.org/2525448", row.fetch(:place_ref)
      assert_equal "isicily", row.fetch(:axis_source)
      assert_equal 1, counts[:documents]
    end

    def test_bce_bounds_are_signed_years_with_pleiades_ref
      make_document("urn:nabu:isicily:isic001510")
      build!
      row = timeline_for("urn:nabu:isicily:isic001510")
      assert_equal(-600, row.fetch(:not_before), "signed historical years, no year 0")
      assert_equal(-401, row.fetch(:not_after))
      assert_equal "Selinus", row.fetch(:place_name), "the ancient name wins when present"
      assert_equal "http://pleiades.stoa.org/places/462489", row.fetch(:place_ref)
    end

    def test_a_metadata_only_record_still_feeds_the_timeline
      make_document("urn:nabu:isicily:isic020002")
      counts = build!
      row = timeline_for("urn:nabu:isicily:isic020002")
      assert_equal(-500, row.fetch(:not_before),
                   "the Elymian record has no citable text but a dated, placed header")
      assert_equal(-480, row.fetch(:not_after))
      assert_equal "Segesta", row.fetch(:place_name)
      assert_equal "https://pleiades.stoa.org/places/462487", row.fetch(:place_ref)
      assert_equal 1, counts[:documents]
    end

    def test_documents_not_in_the_catalog_contribute_nothing
      counts = build!
      assert_equal 0, counts[:documents]
      assert_equal 0, @db[:document_axes].count
    end

    def test_all_nine_fixture_records_join_when_present
      %w[
        isic000001 isic000451 isic000764 isic001510 isic001620
        isic001895 isic002954 isic003475 isic020002
      ].each { |id| make_document("urn:nabu:isicily:#{id}") }
      counts = build!
      assert_equal 9, counts[:documents], "every fixture record is dated or placed"
      assert_equal 0, counts[:invalid]
      assert_equal 0, counts[:undated]
    end
  end
end
