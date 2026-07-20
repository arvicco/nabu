# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::TimelineBuilder::OraccDates (P16-3): ORACC catalogue dates over
  # trimmed-real catalogue.json fixtures (test/fixtures/timeline/oracc/). A fresh
  # in-memory catalog seeded with the documents the members join to, so the
  # project:textid→urn join (base + "-en" translation) is exercised end to end.
  class OraccDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURE_DIR = File.expand_path("../../fixtures/timeline", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "oracc", name: "ORACC", adapter_class: "T", license_class: "open"
      )
    end

    def make_document(urn, language: "akk")
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
      Nabu::Store::TimelineBuilder.rebuild!(catalog: @db, canonical_dir: FIXTURE_DIR)
    end

    # -- regnal date_of_origin (SAA formulas) ----------------------------------

    def test_regnal_formula_resolves_to_the_kings_reign
      make_document("urn:nabu:oracc:saao-saa01:P224395") # Sargon2.000.00.00
      build!
      row = timeline_for("urn:nabu:oracc:saao-saa01:P224395")
      assert_equal(-721, row.fetch(:not_before))
      assert_equal(-705, row.fetch(:not_after))
      assert_equal "reign", row.fetch(:precision)
      assert_equal "Sargon2.000.00.00", row.fetch(:date_raw)
      assert_equal "oracc", row.fetch(:axis_source)
    end

    def test_eponym_limu_formula_still_resolves_by_king
      make_document("urn:nabu:oracc:saao-saa02:P500551") # Esarhaddon.limu Nabu-belu-usur.02.16
      build!
      row = timeline_for("urn:nabu:oracc:saao-saa02:P500551")
      assert_equal(-680, row.fetch(:not_before))
      assert_equal(-669, row.fetch(:not_after))
      assert_equal "reign", row.fetch(:precision)
    end

    def test_unknown_king_zeros_fall_back_to_the_period
      make_document("urn:nabu:oracc:saao-saa02:P336039") # 00.000.00.00, period Neo-Assyrian
      build!
      row = timeline_for("urn:nabu:oracc:saao-saa02:P336039")
      assert_equal(-911, row.fetch(:not_before))
      assert_equal(-612, row.fetch(:not_after))
      assert_equal "period", row.fetch(:precision)
      assert_equal "Neo-Assyrian", row.fetch(:date_raw)
    end

    def test_every_census_attested_king_has_a_reign
      # The 2026-07-13 census found exactly these king spellings in the SAA
      # date_of_origin formulas; each must resolve, or the doc silently
      # degrades to its period.
      %w[Sargon2 Sennacherib Esarhaddon Assurbanipal Tiglath-pileser3
         Shalmaneser3 Shalmaneser5 Shamshi-Adad5 Adad-narari3 Assur-dan3
         Assur-etel-ilani Sin-sharru-ishkun].each do |king|
        assert Nabu::Store::TimelineBuilder::OraccDates::REIGNS.key?(king), "#{king} missing from REIGNS"
      end
    end

    # -- absolute date_of_origin (royal inscriptions) --------------------------

    def test_absolute_bce_range_is_negated
      make_document("urn:nabu:oracc:rinap-rinap1:Q003414") # 744-727 (Tiglath-pileser III)
      build!
      row = timeline_for("urn:nabu:oracc:rinap-rinap1:Q003414")
      assert_equal(-744, row.fetch(:not_before))
      assert_equal(-727, row.fetch(:not_after))
      assert_equal "range", row.fetch(:precision)
      assert_equal "744-727", row.fetch(:date_raw)
    end

    def test_ca_range_keeps_the_ca_precision
      make_document("urn:nabu:oracc:riao:Q005837") # ca. 1233-1197 (Tukulti-Ninurta I)
      build!
      row = timeline_for("urn:nabu:oracc:riao:Q005837")
      assert_equal(-1233, row.fetch(:not_before))
      assert_equal(-1197, row.fetch(:not_after))
      assert_equal "ca", row.fetch(:precision)
    end

    def test_mixed_ca_range_parses
      make_document("urn:nabu:oracc:riao:Q003700") # 668-ca. 631 (Assurbanipal)
      build!
      row = timeline_for("urn:nabu:oracc:riao:Q003700")
      assert_equal(-668, row.fetch(:not_before))
      assert_equal(-631, row.fetch(:not_after))
    end

    def test_century_phrase_maps_to_bce_century_bounds
      make_document("urn:nabu:oracc:riao:Q006693") # 9th-8th century
      build!
      row = timeline_for("urn:nabu:oracc:riao:Q006693")
      assert_equal(-900, row.fetch(:not_before))
      assert_equal(-701, row.fetch(:not_after))
      assert_equal "century", row.fetch(:precision)
    end

    # -- period fallback --------------------------------------------------------

    def test_period_maps_via_the_middle_chronology_table
      make_document("urn:nabu:oracc:dcclt:P212382", language: "sux") # Old Babylonian, Nippur
      build!
      row = timeline_for("urn:nabu:oracc:dcclt:P212382")
      assert_equal(-1900, row.fetch(:not_before))
      assert_equal(-1600, row.fetch(:not_after))
      assert_equal "period", row.fetch(:precision)
      assert_equal "Nippur", row.fetch(:place_name)
      assert_equal "https://pleiades.stoa.org/places/912910", row.fetch(:place_ref)
    end

    def test_unmapped_period_is_skipped_and_counted_never_guessed
      make_document("urn:nabu:oracc:dcclt:P230009", language: "sux") # period "uncertain"
      summary = build!
      row = timeline_for("urn:nabu:oracc:dcclt:P230009")
      # Undated — but the provenience (Nippur) still earns a place-only row.
      assert_nil row.fetch(:not_before)
      assert_nil row.fetch(:not_after)
      assert_equal "Nippur", row.fetch(:place_name)
      assert_equal 1, summary.oracc_undated
    end

    def test_compound_or_period_envelopes_its_parts
      parsed = Nabu::Store::TimelineBuilder::OraccDates.period_range("Late Middle Assyrian or early Neo-Assyrian")
      assert_equal(-1400, parsed.fetch(:not_before)) # Middle Assyrian opens
      assert_equal(-612, parsed.fetch(:not_after))   # Neo-Assyrian closes
    end

    def test_ascending_range_is_unparseable_not_misread_as_ce
      assert_nil Nabu::Store::TimelineBuilder::OraccDates.parse_date_of_origin("681-704")
    end

    def test_year_zero_is_unparseable_never_stored
      assert_nil Nabu::Store::TimelineBuilder::OraccDates.parse_date_of_origin("000")
      assert_nil Nabu::Store::TimelineBuilder::OraccDates.parse_date_of_origin("704-000")
    end

    # -- the translation witness ------------------------------------------------

    def test_translation_document_carries_its_tablets_timeline
      make_document("urn:nabu:oracc:saao-saa01:P224395")
      make_document("urn:nabu:oracc:saao-saa01:P224395-en", language: "eng")
      summary = build!
      row = timeline_for("urn:nabu:oracc:saao-saa01:P224395-en")
      assert_equal(-721, row.fetch(:not_before))
      assert_equal "Nimrud (Kalhu)", row.fetch(:place_name)
      assert_equal 2, summary.oracc # tablet + translation each counted
    end

    # -- plumbing ----------------------------------------------------------------

    def test_member_without_a_catalog_document_inserts_nothing
      build!
      assert_equal 0, @db[:document_axes].count
    end

    def test_rebuild_is_idempotent
      make_document("urn:nabu:oracc:saao-saa01:P224395")
      build!
      build!
      assert_equal 1, @db[:document_axes].count
    end
  end
end
