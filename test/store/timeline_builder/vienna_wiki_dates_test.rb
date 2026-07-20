# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::TimelineBuilder::ViennaWikiDates (P29-3): the inscription →
  # object join over the checked-in lexlep/tir fixtures — sortdate point
  # years (signed BCE), the wiki's sortdate=0 "unknown" filler, site
  # place names, place-only rows.
  class ViennaWikiDatesTest < Minitest::Test
    include StoreTestDB

    # canonical_dir/<slug>/pages/… — the fixtures root IS the canonical
    # layout for the extractor's purposes.
    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @lexlep = Nabu::Store::Source.create(
        slug: "lexlep", name: "LexLep", adapter_class: "T", license_class: "nc"
      )
      @tir = Nabu::Store::Source.create(
        slug: "tir", name: "TIR", adapter_class: "T", license_class: "nc"
      )
    end

    def make_document(source, urn)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: urn, language: "cel",
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def timeline_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id)).first
    end

    def build!
      Nabu::Store::TimelineBuilder::ViennaWikiDates.build(catalog: @db, canonical_dir: FIXTURES_ROOT)
    end

    def all_fixture_documents!
      %w[ao-1.1 be-1 bg-1 bi-8].each { |id| make_document(@lexlep, "urn:nabu:lexlep:#{id}") }
      %w[ak-1.1 ak-1.12 bz-10.1].each { |id| make_document(@tir, "urn:nabu:tir:#{id}") }
    end

    def test_sortdate_point_year_with_site_place
      make_document(@lexlep, "urn:nabu:lexlep:ao-1.1")
      counts = build!
      row = timeline_for("urn:nabu:lexlep:ao-1.1")
      assert_equal(-100, row.fetch(:not_before), "sortdate is a signed historical year")
      assert_equal(-100, row.fetch(:not_after), "a sortdate is a point — both bounds")
      assert_equal "circa", row.fetch(:precision), "a sort key is an approximation, never 'exact'"
      assert_match(/late 2/, row.fetch(:date_raw), "the object's own display text")
      assert_equal "Aosta", row.fetch(:place_name)
      assert_nil row.fetch(:place_ref)
      assert_equal "lexlep", row.fetch(:axis_source)
      assert_equal 1, counts[:lexlep][:documents]
    end

    def test_sortdate_zero_is_the_wikis_unknown_filler_never_a_year
      make_document(@lexlep, "urn:nabu:lexlep:bg-1")
      counts = build!
      row = timeline_for("urn:nabu:lexlep:bg-1")
      assert_nil row.fetch(:not_before), "BG·1 Bergamo carries sortdate=0 + date=unknown — undated"
      assert_equal "Bergamo", row.fetch(:place_name), "the place-only row still lands"
      assert_nil row.fetch(:precision)
      assert_equal 1, counts[:lexlep][:documents]
      assert_equal 1, counts[:lexlep][:undated]
    end

    def test_tir_joins_through_the_slash_bearing_site
      make_document(@tir, "urn:nabu:tir:bz-10.1")
      counts = build!
      row = timeline_for("urn:nabu:tir:bz-10.1")
      assert_equal(-300, row.fetch(:not_before))
      assert_equal "5th–2nd centuries BC", row.fetch(:date_raw)
      assert_equal "Pfatten / Vadena", row.fetch(:place_name)
      assert_equal "tir", row.fetch(:axis_source)
      assert_equal 1, counts[:tir][:documents]
    end

    def test_missing_object_page_contributes_nothing
      make_document(@lexlep, "urn:nabu:lexlep:bi-8")
      counts = build!
      assert_equal 0, @db[:document_axes].count, "BI·8's object page is not cached — no row"
      assert_equal 0, counts[:lexlep][:documents]
      assert_equal 1, counts[:lexlep][:undated]
    end

    def test_full_fixture_census
      all_fixture_documents!
      counts = build!
      assert_equal 2, counts[:lexlep][:documents], "AO·1.1 dated+placed, BG·1 place-only"
      assert_equal 3, counts[:lexlep][:undated], "BG·1, BE·1, BI·8"
      assert_equal 3, counts[:tir][:documents], "AK-1.1/AK-1.12 place-only, BZ-10.1 dated"
      assert_equal 2, counts[:tir][:undated]
      assert_equal 0, counts[:lexlep][:invalid]
      assert_equal 0, counts[:tir][:invalid]
    end

    def test_documents_not_in_the_catalog_contribute_nothing
      counts = build!
      assert_equal 0, counts[:lexlep][:documents]
      assert_equal 0, @db[:document_axes].count
    end
  end
end
