# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Store
  # Nabu::Store::TimelineBuilder::OpenitiDates (P41-2): the AH death-year
  # lane. Every OpenITI urn opens with the author's 4-digit hijrī death year
  # (TSV `date` == the prefix, 0 mismatches across 14,107 rows — P41-g), so
  # the extractor reads urns alone (urn = f(canonical), the goo300k/imp
  # shape; no canonical re-parse). CE = round(AH × 0.970225 + 621.5716),
  # the standard tabular conversion. The point envelope is a TERMINUS (the
  # author died that year; composition is on-or-before), not a composition
  # date — precision "year", date_raw names the AH source.
  class OpenitiDatesTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "openiti", name: "OpenITI", adapter_class: "T", license_class: "nc"
      )
    end

    def make_document(urn, language: "ara")
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: urn, language: language,
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def timeline_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id)).first
    end

    def build!
      Nabu::Store::TimelineBuilder::OpenitiDates.build(catalog: @db, canonical_dir: "/nonexistent")
    end

    def test_death_year_converts_ah_to_a_ce_point_envelope
      make_document("urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1", language: "fas")
      counts = build!
      row = timeline_for("urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1")
      assert_equal 1390, row.fetch(:not_before), "AH 792 → round(792×0.970225 + 621.5716) = 1390 CE"
      assert_equal 1390, row.fetch(:not_after)
      assert_equal "year", row.fetch(:precision)
      assert_equal "d. AH 0792", row.fetch(:date_raw), "the terminus is named as a death year"
      assert_nil row.fetch(:place_name), "no gazetteer, no invented places"
      assert_equal "openiti", row.fetch(:axis_source)
      assert_equal({ documents: 1, undated: 0 }, counts)
    end

    def test_the_earliest_and_latest_observed_prefixes_convert
      make_document("urn:nabu:openiti:0001AbuTalibCabdManaf.Diwan.JK007501-ara1")
      make_document("urn:nabu:openiti:0390AbuFarajCukbari.Hadith.ShamAY0032805-ara1")
      build!
      assert_equal 623, timeline_for("urn:nabu:openiti:0001AbuTalibCabdManaf.Diwan.JK007501-ara1")
        .fetch(:not_before), "AH 1, the corpus's earliest author"
      assert_equal 1000, timeline_for("urn:nabu:openiti:0390AbuFarajCukbari.Hadith.ShamAY0032805-ara1")
        .fetch(:not_before)
    end

    def test_a_urn_without_the_ah_prefix_is_counted_undated_never_guessed
      # The MSS guard: MS-shaped uris carry no death year. MSS rows are out
      # of scope (D41-e), so this is belt — counted, never stored.
      make_document("urn:nabu:openiti:MS0044LondonKhalili.DOC21AR25.IEDC0051-ara1")
      counts = build!
      assert_equal({ documents: 0, undated: 1 }, counts)
      assert_equal 0, @db[:document_axes].count
    end

    def test_other_sources_documents_contribute_nothing
      other = Nabu::Store::Source.create(slug: "rem", name: "ReM", adapter_class: "T",
                                         license_class: "attribution")
      Nabu::Store::Document.create(
        source_id: other.id, urn: "urn:nabu:rem:m058", title: "t", language: "gmh",
        content_sha256: "x", revision: 1, withdrawn: false
      )
      counts = build!
      assert_equal({ documents: 0, undated: 0 }, counts)
    end
  end
end
