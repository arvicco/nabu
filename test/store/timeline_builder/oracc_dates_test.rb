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

    def timeline_for(urn, axis_source: "oracc")
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id), axis_source: axis_source).first
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

    # -- regnal_dates (the catalogue's reign span, between date_of_origin and
    #    the period) ------------------------------------------------------------

    # riao Q006482 (Sargon II's Annals of Room II) carries no date_of_origin
    # — before, it fell to the whole Neo-Assyrian period band; its
    # regnal_dates "721-705" is Sargon II's reign.
    def test_regnal_dates_band_a_member_without_date_of_origin
      make_document("urn:nabu:oracc:riao:Q006482")
      build!
      row = timeline_for("urn:nabu:oracc:riao:Q006482")
      assert_equal(-721, row.fetch(:not_before))
      assert_equal(-705, row.fetch(:not_after))
      assert_equal "reign", row.fetch(:precision)
      assert_equal "721-705", row.fetch(:date_raw)
    end

    def test_regnal_dates_shapes_parse_with_bc_suffix_and_ca
      dates = Nabu::Store::TimelineBuilder::OraccDates
      assert_equal [-721, -705], dates.parse_regnal_dates("721–705 BC").values_at(:not_before, :not_after)
      assert_equal [-668, -631], dates.parse_regnal_dates("668–ca. 631 BC").values_at(:not_before, :not_after)
      assert_equal [-626, -612], dates.parse_regnal_dates("ca. 626–612 BC").values_at(:not_before, :not_after)
      assert_equal "reign", dates.parse_regnal_dates("668-ca. 631")[:precision]
      assert_nil dates.parse_regnal_dates("unknown")
    end

    def test_date_of_origin_still_wins_over_regnal_dates
      make_document("urn:nabu:oracc:saao-saa01:P224395") # Sargon2.000.00.00 + regnal 721–705 BC
      build!
      assert_equal "Sargon2.000.00.00", timeline_for("urn:nabu:oracc:saao-saa01:P224395").fetch(:date_raw)
    end

    # -- the SAA second place: the letter's SENDER location -------------------

    # A letter's sender_loc is where it was WRITTEN; provenience is where it
    # was FOUND. The sender place rides its own place-only axis row under
    # axis_source "oracc-sender" — a labeled class beside the provenience
    # row, never merged into it.
    def test_sender_location_rides_its_own_labeled_place_row
      make_document("urn:nabu:oracc:saao-saa01:P313416")
      build!
      found = timeline_for("urn:nabu:oracc:saao-saa01:P313416")
      assert_equal "Kuyunjik (Nineveh)", found.fetch(:place_name), "the provenience row is untouched"
      sender = timeline_for("urn:nabu:oracc:saao-saa01:P313416", axis_source: "oracc-sender")
      assert_equal "Assyria", sender.fetch(:place_name)
      assert_equal "https://pleiades.stoa.org/places/29492", sender.fetch(:place_ref)
      assert_in_delta 36.2, sender.fetch(:place_lat)
      assert_in_delta 43.2, sender.fetch(:place_lon), 0.001, "upstream writes lon,lat (Nineveh: 43.15,36.36)"
      assert_nil sender.fetch(:not_before), "a sender row carries no date — the tablet's row does"
    end

    def test_sender_without_pleiades_keeps_the_name_alone
      make_document("urn:nabu:oracc:saao-saa01:P224395") # sender_loc Hamath, no pleiades
      build!
      sender = timeline_for("urn:nabu:oracc:saao-saa01:P224395", axis_source: "oracc-sender")
      assert_equal "Hamath", sender.fetch(:place_name)
      assert_nil sender.fetch(:place_ref)
      assert_nil sender.fetch(:place_lat)
    end

    def test_unknown_sender_placeholders_mint_no_row
      dates = Nabu::Store::TimelineBuilder::OraccDates
      assert_nil dates.extract_sender("sender_loc" => "(unknown)", "pleiades_sender_loc" => "not assigned",
                                      "sender_loc_coordinates" => "N/A")
      assert_nil dates.extract_sender({})
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

    # P62-1: the 80k-doc gap was ONE glob depth — epsd2/admin/ur3 unpacks
    # its catalogue at <project>/<sub>/<sub>/catalogue.json (the P31-0
    # multi-segment root, hitting the EXTRACTOR this time). The fixture is
    # the real epsd2 catalogue trimmed to two Ur III members; "XXXX" and
    # regnal "SH44" date_of_origin shapes fall through to the period band.
    def test_triply_nested_catalogues_are_walked_and_ur_iii_bands
      make_document("urn:nabu:oracc:epsd2-admin-ur3:P100001", language: "sux")
      build!
      row = timeline_for("urn:nabu:oracc:epsd2-admin-ur3:P100001")
      refute_nil row, "the depth-3 catalogue must be discovered"
      assert_equal(-2100, row[:not_before])
      assert_equal(-2000, row[:not_after])
      assert_equal "period", row[:precision]
      assert_equal "Umma", row[:place_name]
    end

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
      assert_equal 2, @db[:document_axes].count, "the tablet row + its sender-place row"
    end
  end
end
