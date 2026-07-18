# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::AxisBuilder::OpenEtruscanDates (P29-0): corpus
  # year_from/year_to (BCE-POSITIVE upstream) sign-flipped to signed
  # historical years + the Larth findspot side-join, over the checked-in
  # open-etruscan fixture CSVs. The BCE sign-flip regression pin lives
  # here; the upstream "0.0" bound (no year 0 exists) is the DateAxis
  # tripwire — counted invalid, never stored, place kept.
  class OpenEtruscanDatesTest < Minitest::Test
    include StoreTestDB

    # canonical_dir/open-etruscan/{corpus,findspots}/… — the fixtures root
    # IS the canonical layout for the extractor's purposes.
    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "open-etruscan", name: "OpenEtruscan", adapter_class: "T", license_class: "attribution"
      )
    end

    def make_document(urn)
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: urn, language: "ett",
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def axis_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id)).first
    end

    def build!
      Nabu::Store::AxisBuilder::OpenEtruscanDates.build(catalog: @db, canonical_dir: FIXTURES_ROOT)
    end

    def test_bce_positive_years_flip_to_signed_historical_years
      make_document("urn:nabu:open-etruscan:cr-2.20")
      counts = build!
      row = axis_for("urn:nabu:open-etruscan:cr-2.20")
      assert_equal(-675, row.fetch(:not_before), "675.0 upstream means 675 BCE — the sign-flip pin")
      assert_equal(-650, row.fetch(:not_after))
      assert_equal "range", row.fetch(:precision)
      assert_equal "675–650 BCE", row.fetch(:date_raw)
      assert_equal "Caere", row.fetch(:place_name), "the Larth findspot side-join on the shared id"
      assert_nil row.fetch(:place_ref), "verbatim city strings carry no gazetteer ref"
      assert_equal "open-etruscan", row.fetch(:axis_source)
      assert_equal 1, counts[:documents]
    end

    def test_dated_unplaced_rows_get_a_date_only_row
      make_document("urn:nabu:open-etruscan:ve-6.2")
      build!
      row = axis_for("urn:nabu:open-etruscan:ve-6.2")
      assert_equal(-650, row.fetch(:not_before))
      assert_equal(-625, row.fetch(:not_after))
      assert_nil row.fetch(:place_name)
    end

    def test_the_year_zero_bound_is_the_tripwire_but_the_place_survives
      make_document("urn:nabu:open-etruscan:etp-313")
      make_document("urn:nabu:open-etruscan:etp-240")
      counts = build!
      assert_nil axis_for("urn:nabu:open-etruscan:etp-313"),
                 "100.0–0.0 with no findspot: invalid date, no place — no row"
      row = axis_for("urn:nabu:open-etruscan:etp-240")
      refute_nil row, "the invalid date must not cost the real findspot"
      assert_nil row.fetch(:not_before)
      assert_equal "Ager Saenensis", row.fetch(:place_name)
      assert_equal 2, counts[:invalid], "both 0.0 bounds counted"
      assert_equal 1, counts[:documents]
    end

    def test_undated_unplaced_rows_contribute_nothing_but_the_honest_count
      make_document("urn:nabu:open-etruscan:cie-2609")
      counts = build!
      assert_equal 0, @db[:document_axes].count
      assert_equal 1, counts[:undated]
    end

    def test_en_siblings_never_join
      make_document("urn:nabu:open-etruscan:etp-192-en")
      build!
      assert_equal 0, @db[:document_axes].count,
                   "sibling urns are not minted from row ids — no axis row"
    end

    def test_findspot_conflicts_resolve_first_wins
      places = Nabu::Store::AxisBuilder::OpenEtruscanDates.findspot_places(FIXTURES_ROOT)
      assert_equal "Clusium", places.fetch("ETP 285"),
                   "the one conflicting id (Clusium / Ager Clusinus) resolves to the first row"
      assert_equal "Caere", places.fetch("Cr 2.20"), "trailing-space ids join stripped"
    end

    def test_documents_not_in_the_catalog_contribute_nothing
      counts = build!
      assert_equal 0, counts[:documents]
      assert_equal 0, @db[:document_axes].count
    end
  end
end
