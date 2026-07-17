# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::AxisBuilder::RiigDates (P25-1): RIIG origDate/origPlace →
  # the date/place axis, over the checked-in riig fixture records
  # (test/fixtures/riig/documents/) — signed BCE bounds, findspot-over-
  # settlement place names, Trismegistos refs, undated-but-placed rows.
  class RiigDatesTest < Minitest::Test
    include StoreTestDB

    # canonical_dir/<riig>/documents/*.xml — the fixtures root IS the
    # canonical layout for the extractor's purposes.
    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "riig", name: "RIIG", adapter_class: "T", license_class: "attribution"
      )
    end

    def make_document(urn)
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: urn, language: "xtg-Grek",
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def axis_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id)).first
    end

    def build!
      Nabu::Store::AxisBuilder::RiigDates.build(catalog: @db, canonical_dir: FIXTURES_ROOT)
    end

    def test_bce_range_with_findspot_and_trismegistos_ref
      make_document("urn:nabu:riig:ahp-01-01")
      counts = build!
      row = axis_for("urn:nabu:riig:ahp-01-01")
      assert_equal(-100, row.fetch(:not_before), "signed historical years, no year 0")
      assert_equal(-1, row.fetch(:not_after))
      assert_equal "range", row.fetch(:precision)
      assert_match(/-I/, row.fetch(:date_raw), "the record's own display text")
      assert_equal "Chastelard de Lardiers", row.fetch(:place_name), "the untyped findspot placeName wins"
      assert_equal "https://www.trismegistos.org/place/21492", row.fetch(:place_ref)
      assert_equal "riig", row.fetch(:axis_source)
      assert_equal 1, counts[:documents]
    end

    def test_documents_not_in_the_catalog_contribute_nothing
      counts = build!
      assert_equal 0, counts[:documents]
      assert_equal 0, @db[:document_axes].count
    end

    def test_fr_siblings_never_join
      make_document("urn:nabu:riig:vau-13-01-fr")
      build!
      assert_equal 0, @db[:document_axes].count,
                   "sibling urns are not minted from filenames — no axis row"
    end

    def test_all_four_fixture_records_join_when_present
      %w[ahp-01-01 all-01-01 gar-10-03 vau-13-01].each { |id| make_document("urn:nabu:riig:#{id}") }
      counts = build!
      assert_equal 4, counts[:documents], "every fixture record is dated or placed"
      assert_equal 0, counts[:invalid]
    end
  end
end
