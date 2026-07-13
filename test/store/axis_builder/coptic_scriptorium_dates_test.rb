# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::AxisBuilder::CopticScriptoriumDates (P17-1): manuscript
  # dates/places from the TT meta headers, run against the REAL adapter
  # fixtures (test/fixtures/coptic-scriptorium — besa dated 0500–0799
  # medium + White Monastery; cpr dated 0700–0799 with an "unknown" place
  # skipped; AP place-only; the bible zip never opened, honestly undated).
  class CopticScriptoriumDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "coptic-scriptorium", name: "Coptic Scriptorium",
        adapter_class: "C", license_class: "nc"
      )
    end

    def seed(urn)
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, language: "cop",
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def build!
      Nabu::Store::AxisBuilder::CopticScriptoriumDates.build(catalog: @db, canonical_dir: FIXTURES_ROOT)
    end

    def test_dated_headers_become_envelope_rows_with_upstream_precision
      besa = seed("urn:nabu:coptic-scriptorium:besa.food.monbbb")
      outcome = build!
      assert_equal 1, outcome[:documents]
      assert_equal 0, outcome[:invalid]
      row = @db[:document_axes].where(document_id: besa.id).first
      assert_equal 500, row[:not_before]
      assert_equal 799, row[:not_after]
      assert_equal "medium", row[:precision]
      assert_equal "between 500 and 799 C.E.", row[:date_raw]
      assert_equal "White Monastery", row[:place_name]
      assert_equal "coptic-scriptorium", row[:axis_source]
    end

    def test_unknown_places_are_skipped_but_the_date_still_lands
      cpr = seed("urn:nabu:coptic-scriptorium:papyri_info.tm82127.cpr_2_237")
      build!
      row = @db[:document_axes].where(document_id: cpr.id).first
      assert_equal 700, row[:not_before]
      assert_equal 799, row[:not_after]
      assert_nil row[:place_name], "origPlace/placeName \"unknown\" must never be stored as a place"
    end

    def test_place_only_headers_get_a_row_with_null_bounds
      ap = seed("urn:nabu:coptic-scriptorium:ap.4.monbeg")
      build!
      row = @db[:document_axes].where(document_id: ap.id).first
      refute_nil row, "an undated but placed manuscript still anchors the place axis"
      assert_nil row[:not_before]
      assert_nil row[:not_after]
      assert_nil row[:precision]
      assert_equal "White Monastery", row[:place_name]
    end

    def test_documents_we_do_not_hold_contribute_nothing
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 0, @db[:document_axes].count
    end

    # The frozen-minting drift pin: the extractor's urn mint must equal the
    # adapter's for every fixture document, or axis rows silently detach.
    def test_extractor_urns_match_the_adapter_minting
      adapter_urns = Nabu::Adapters::CopticScriptorium.new
                                                      .discover(File.join(FIXTURES_ROOT, "coptic-scriptorium"))
                                                      .map(&:id).sort
      extractor_urns = []
      Nabu::Store::AxisBuilder::CopticScriptoriumDates.tt_headers(
        File.join(FIXTURES_ROOT, "coptic-scriptorium")
      ) do |meta|
        extractor_urns << Nabu::Store::AxisBuilder::CopticScriptoriumDates.document_urn(meta)
      end
      # loose files only (the zip is deliberately unread here) — every
      # extractor urn must be one the adapter mints
      assert_equal extractor_urns.sort, adapter_urns & extractor_urns
    end
  end
end
