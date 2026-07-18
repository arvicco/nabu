# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::AxisBuilder::CeipomDates (P29-1): document dates and
  # findspots from CEIPoM's texts.csv, run against the REAL adapter
  # fixtures (test/fixtures/ceipom). Upstream dates are signed-year FLOAT
  # strings ("-675.0"), always both bounds when dated (censused: 3,872 of
  # 3,875 dated); Provenance is always non-empty but 10 values are
  # degenerate ("?", "0", "Provenance unknown [found & written]") — not
  # places; GeoID rides verbatim as place_ref; WGS84 coordinates stay
  # document metadata (the EDH coordinates decision). One degenerate
  # inverted range upstream (text 819: -100 → -51300) is counted invalid,
  # never stored.
  class CeipomDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "ceipom", name: "CEIPoM", adapter_class: "A", license_class: "attribution"
      )
    end

    def seed(text_id, language: "lat")
      Nabu::Store::Document.create(
        source_id: @source.id, urn: "urn:nabu:ceipom:#{text_id}", language: language,
        content_sha256: text_id.to_s, revision: 1, withdrawn: false
      )
    end

    def build!
      Nabu::Store::AxisBuilder::CeipomDates.build(catalog: @db, canonical_dir: FIXTURES_ROOT)
    end

    def test_fibula_praenestina_gets_signed_year_bounds_and_findspot
      fibula = seed(2)
      outcome = build!
      assert_equal 1, outcome[:documents]
      row = @db[:document_axes].where(document_id: fibula.id).first
      assert_equal(-675, row[:not_before])
      assert_equal(-625, row[:not_after])
      assert_equal "range", row[:precision]
      assert_equal "-675.0 – -625.0", row[:date_raw], "upstream's own float strings, verbatim"
      assert_equal "Praeneste (Palestrina)", row[:place_name]
      assert_equal "ceipom", row[:axis_source]
    end

    def test_geo_id_rides_verbatim_as_place_ref_when_present
      seed(954, language: "osc")
      build!
      row = @db[:document_axes].first
      assert_equal "Capua (Santa Maria Capua Vetere)", row[:place_name]
      assert_equal "3311.0", row[:place_ref], "the bare upstream GeoID, verbatim — never resolved"
    end

    def test_fully_degenerate_text_mints_no_row_and_counts_both_residues
      seed(2584, language: "xve")
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 1, outcome[:undated]
      assert_equal 1, outcome[:unplaced], "Provenance \"0\" is not a place; no coordinates either"
      assert_equal 0, @db[:document_axes].count
    end

    def test_the_inverted_range_is_counted_invalid_never_stored
      seed(819)
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 1, outcome[:invalid], "text 819's -100 → -51300 upstream typo"
      assert_equal 0, @db[:document_axes].count
    end

    def test_documents_we_do_not_hold_contribute_nothing
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 0, outcome[:undated]
      assert_equal 0, outcome[:unplaced]
      assert_equal 0, @db[:document_axes].count
    end

    def test_every_placed_dated_fixture_text_gets_exactly_one_row
      Nabu::Adapters::Ceipom.new.discover(File.join(FIXTURES_ROOT, "ceipom")).each do |ref|
        seed(ref.id.delete_prefix("urn:nabu:ceipom:"))
      end
      outcome = build!
      # 16 parseable + we seed only those; of them 2584 is undated+unplaced
      # and 819 invalid — 14 rows.
      assert_equal 14, outcome[:documents]
      assert_equal 1, outcome[:undated]
      assert_equal 1, outcome[:unplaced]
      assert_equal 1, outcome[:invalid]
      assert_equal 14, @db[:document_axes].count
    end

    # The frozen-minting drift pin: the extractor's urn mint must equal the
    # adapter's discover mint over the shared fixture set (sentence-less
    # texts excluded on both sides), or axis rows silently stop joining.
    def test_extractor_urn_mint_matches_the_adapter
      adapter_urns = Nabu::Adapters::Ceipom.new
                                           .discover(File.join(FIXTURES_ROOT, "ceipom"))
                                           .map(&:id).sort
      extractor_urns = Nabu::Store::AxisBuilder::CeipomDates
                       .text_urns(File.join(FIXTURES_ROOT, "ceipom")).sort
      assert_equal(adapter_urns, extractor_urns & adapter_urns,
                   "every adapter urn must be mintable by the extractor")
    end
  end
end
