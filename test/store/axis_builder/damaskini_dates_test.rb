# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::AxisBuilder::DamaskiniDates (P23-1): manuscript dates and
  # places from the TSV headers, run against the REAL adapter fixtures
  # (test/fixtures/damaskini — berlinski "Pleven?, 1791" point-dated,
  # nedelnik1806 "Râmnic, 1806", veles "XV c." century-only with no place).
  # These are witness (copying/printing) dates — the right axis for a
  # corpus whose texts are 15th–19th-c. copies of older works.
  class DamaskiniDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "damaskini", name: "Damaskini",
        adapter_class: "D", license_class: "attribution"
      )
    end

    def seed(urn, language: "bul")
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, language: language,
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def build!
      Nabu::Store::AxisBuilder::DamaskiniDates.build(catalog: @db, canonical_dir: FIXTURES_ROOT)
    end

    def test_point_dated_header_becomes_a_year_row_with_place
      berlinski = seed("urn:nabu:damaskini:berlinski--slovo-petki")
      outcome = build!
      assert_equal 1, outcome[:documents]
      row = @db[:document_axes].where(document_id: berlinski.id).first
      assert_equal 1791, row[:not_before]
      assert_equal 1791, row[:not_after]
      assert_equal "year", row[:precision]
      assert_equal "1791", row[:date_raw]
      assert_equal "Pleven?", row[:place_name], "upstream's question mark kept verbatim"
      assert_equal "damaskini", row[:axis_source]
    end

    def test_century_only_header_becomes_an_honest_range_with_no_place
      veles = seed("urn:nabu:damaskini:veles--trojanskata", language: "chu")
      build!
      row = @db[:document_axes].where(document_id: veles.id).first
      assert_equal 1401, row[:not_before]
      assert_equal 1500, row[:not_after]
      assert_equal "range", row[:precision], "a century is an envelope, never a midpoint"
      assert_equal "XV c.", row[:date_raw]
      assert_nil row[:place_name]
    end

    def test_en_siblings_never_get_axis_rows
      seed("urn:nabu:damaskini:berlinski--slovo-petki-en", language: "eng")
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 0, @db[:document_axes].count,
                   "the TSV filename joins only the original document urn"
    end

    def test_documents_we_do_not_hold_contribute_nothing
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 0, @db[:document_axes].count
    end

    # The frozen-minting drift pin: the extractor's urn mint (TSV filename,
    # downcased) must equal the adapter's discover mint over the shared
    # fixture set, or axis rows silently stop joining.
    def test_extractor_urn_mint_matches_the_adapter
      adapter_urns = Nabu::Adapters::Damaskini.new
                                              .discover(File.join(FIXTURES_ROOT, "damaskini"))
                                              .map(&:id).sort
      extractor_urns = Dir.glob(File.join(FIXTURES_ROOT, "damaskini", "tsv", "**", "*.txt"))
                          .map { |path| Nabu::Store::AxisBuilder::DamaskiniDates.document_urn(path) }
                          .sort
      assert_equal adapter_urns, extractor_urns
    end
  end
end
