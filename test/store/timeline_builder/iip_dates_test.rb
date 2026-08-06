# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::TimelineBuilder::IipDates (P30-6): IIP origin/date +
  # origin/placeName → the timeline, over the checked-in iip
  # fixture records (test/fixtures/iip/epidoc-files/) — plain
  # notBefore/notAfter as signed years, settlement-over-region place
  # names (the settlement's own text, without its embedded <geo> child),
  # no gazetteer refs (the corpus carries none), metadata-only records
  # still joining (caes0371: dateless but placed — the place-only row).
  class IipDatesTest < Minitest::Test
    include StoreTestDB

    # canonical_dir/<iip>/epidoc-files/*.xml — the fixtures root IS the
    # canonical layout for the extractor's purposes.
    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "iip", name: "IIP", adapter_class: "T", license_class: "nc"
      )
    end

    def make_document(urn)
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: urn, language: "grc",
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def timeline_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id)).first
    end

    def build!
      Nabu::Store::TimelineBuilder::IipDates.build(catalog: @db, canonical_dir: FIXTURES_ROOT)
    end

    def test_ce_range_with_settlement_and_verbatim_raw
      make_document("urn:nabu:iip:abur0001")
      counts = build!
      row = timeline_for("urn:nabu:iip:abur0001")
      assert_equal 300, row.fetch(:not_before), "notBefore=\"0300\", base-10 (never octal)"
      assert_equal 700, row.fetch(:not_after)
      assert_equal "range", row.fetch(:precision)
      assert_equal "300 CE - 700 CE", row.fetch(:date_raw)
      assert_equal "Bethennim", row.fetch(:place_name),
                   "the settlement's own text — its embedded <geo> child never leaks into the name"
      assert_nil row.fetch(:place_ref), "IIP carries no gazetteer refs — an honest absence"
      assert_equal "iip", row.fetch(:axis_source)
      assert_equal 1, counts[:documents]
    end

    def test_bce_bounds_are_signed_years
      make_document("urn:nabu:iip:jeru0490")
      build!
      row = timeline_for("urn:nabu:iip:jeru0490")
      assert_equal(-100, row.fetch(:not_before), "notBefore=\"-0100\" is 100 BCE, signed, no year 0")
      assert_equal 100, row.fetch(:not_after)
      assert_equal "Jerusalem", row.fetch(:place_name)
    end

    def test_a_dateless_record_gets_a_place_only_row_and_counts_undated
      make_document("urn:nabu:iip:caes0371")
      counts = build!
      row = timeline_for("urn:nabu:iip:caes0371")
      assert_nil row.fetch(:not_before), "period=\"Unknown\", no bounds — never guessed"
      assert_nil row.fetch(:not_after)
      assert_nil row.fetch(:precision)
      assert_equal "Caesarea", row.fetch(:place_name)
      assert_equal 1, counts[:documents]
      assert_equal 1, counts[:undated]
    end

    def test_documents_not_in_the_catalog_contribute_nothing
      counts = build!
      assert_equal 0, counts[:documents]
      assert_equal 0, @db[:document_axes].count
    end

    def test_all_six_fixture_records_join_when_present
      %w[abur0001 caes0022 caes0371 dabb0001 hkur0001 jeru0490].each do |id|
        make_document("urn:nabu:iip:#{id}")
      end
      counts = build!
      assert_equal 6, counts[:documents], "every fixture record is dated or placed"
      assert_equal 0, counts[:invalid], "zero year-0 bounds exist in the corpus"
      assert_equal 1, counts[:undated], "caes0371 is the dateless-but-placed one"
    end

    # -- the P59-0 reversed-bounds repairs (real offending records) ---------

    def test_unsigned_bce_bounds_negate_on_the_raw_era_signal
      # masa0797: notBefore="0027" notAfter="0026" for "27-26 BCE" — the
      # sign dropped upstream; the raw's BCE signal repairs it.
      make_document("urn:nabu:iip:masa0797")
      build!
      row = timeline_for("urn:nabu:iip:masa0797")
      assert_equal(-27, row.fetch(:not_before))
      assert_equal(-26, row.fetch(:not_after))
      assert_equal "27-26 BCE", row.fetch(:date_raw), "the raw rides verbatim"
    end

    def test_reversed_ce_bounds_order_normalize
      # zoor0395: notBefore="0355" notAfter="0354" for "354/355 CE" — the
      # slash-order claim, seats swapped upstream.
      make_document("urn:nabu:iip:zoor0395")
      build!
      row = timeline_for("urn:nabu:iip:zoor0395")
      assert_equal 354, row.fetch(:not_before)
      assert_equal 355, row.fetch(:not_after)
    end

    def test_signed_reversed_bounds_swap_and_are_never_re_negated
      # idum0080: notBefore="-0036" notAfter="-0335" for "Approximately
      # 336-335 BCE" — an upstream digit typo (-36 for -336) plus reversal.
      # Repair is mechanical: order-normalize upstream's own claim; the
      # typo'd digit stays upstream's to fix (the raw carries the truth).
      # This was THE row that slipped a bogus arc:imp assignment past
      # containment in P58 (reversed intervals satisfy it vacuously).
      make_document("urn:nabu:iip:idum0080")
      build!
      row = timeline_for("urn:nabu:iip:idum0080")
      assert_equal(-335, row.fetch(:not_before))
      assert_equal(-36, row.fetch(:not_after))
      assert_operator row.fetch(:not_before), :<=, row.fetch(:not_after),
                      "no reversed interval ever reaches the axes"
    end
  end
end
