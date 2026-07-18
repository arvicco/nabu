# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::AxisBuilder::TlaHfDates (P28-2): the pre-cooked
  # dateNotBefore/dateNotAfter integers of the TLA Hugging Face JSONL,
  # wired at PASSAGE grain (dates vary sentence by sentence — the
  # ChronicleAnnals shape: one document-grain envelope row first, then one
  # row per dated record anchored by passage_seq_from/to). Run against the
  # REAL adapter fixtures (test/fixtures/tla-hf — demotic lines dated
  # 201..250 / 101..200 / -332..324 plus one honestly undated; every
  # late-Egyptian line dated BCE).
  class TlaHfDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    DEMOTIC_URN = "urn:nabu:tla-hf:demotic-v18"
    LATE_URN = "urn:nabu:tla-hf:late-egyptian-v19"

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "tla-hf", name: "TLA HF", adapter_class: "T", license_class: "attribution"
      )
    end

    def seed(urn, language: "egy")
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, language: language,
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def build!
      Nabu::Store::AxisBuilder::TlaHfDates.build(catalog: @db, canonical_dir: FIXTURES_ROOT)
    end

    def test_dated_records_become_passage_grain_rows_under_a_document_envelope
      demotic = seed(DEMOTIC_URN)
      outcome = build!
      assert_equal 1, outcome[:documents]
      assert_equal 3, outcome[:sentences], "three dated fixture records"
      assert_equal 1, outcome[:undated], "the empty-dates record is skipped, counted, never guessed"

      rows = @db[:document_axes].where(document_id: demotic.id).order(:id).all
      assert_equal 4, rows.size, "envelope + one row per dated record"

      envelope = rows.first
      assert_nil envelope[:passage_seq_from], "the envelope is the document-grain row"
      assert_equal(-332, envelope[:not_before], "min over the dated records")
      assert_equal 324, envelope[:not_after], "max over the dated records"
      assert_equal "tla-hf", envelope[:axis_source]

      first = rows[1]
      assert_equal 201, first[:not_before]
      assert_equal 250, first[:not_after]
      assert_equal "range", first[:precision]
      assert_equal "201–250", first[:date_raw]
      assert_equal 0, first[:passage_seq_from]
      assert_equal 0, first[:passage_seq_to], "one sentence — the row anchors a single sequence"
    end

    def test_late_egyptian_bce_dates_ride_verbatim_as_signed_years
      late = seed(LATE_URN)
      build!
      envelope = @db[:document_axes].where(document_id: late.id).order(:id).first
      assert_equal(-1292, envelope[:not_before])
      assert_equal(-1077, envelope[:not_after])
    end

    def test_de_siblings_never_get_axis_rows
      seed("#{DEMOTIC_URN}-de", language: "deu")
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 0, @db[:document_axes].count,
                   "the dataset urn joins only the original document"
    end

    def test_documents_we_do_not_hold_contribute_nothing
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 0, @db[:document_axes].count
    end

    # The frozen-minting drift pin: the extractor's urn mint must equal the
    # adapter's discover mint over the shared fixture set, or axis rows
    # silently stop joining (the DamaskiniDates precedent).
    def test_extractor_urn_mint_matches_the_adapter
      adapter_urns = Nabu::Adapters::TlaHf.new
                                          .discover(File.join(FIXTURES_ROOT, "tla-hf"))
                                          .map(&:id).sort
      extractor_urns = Nabu::Adapters::TlaHf::DATASETS.keys
                                                      .map { |slug| "urn:nabu:tla-hf:#{slug}" }.sort
      assert_equal adapter_urns, extractor_urns
    end
  end
end
