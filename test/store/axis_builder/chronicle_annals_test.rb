# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::AxisBuilder::ChronicleAnnals (P16-3): the anno-mundi annal
  # extractor over a trimmed-real TOROT chronicle (test/fixtures/axis/torot/
  # lav.xml — Primary Chronicle, Codex Laurentianus: a non-annal "Introduction"
  # div plus annals 6360, 6361 and the range 6369–6370). Passages are seeded
  # with the fixture's real sentence ids so the sid→sequence join is real.
  class ChronicleAnnalsTest < Minitest::Test
    include StoreTestDB

    FIXTURE_DIR = File.expand_path("../../fixtures/axis", __dir__)

    # The fixture's sentence ids, in document order (Introduction, 6360, 6361,
    # 6369–6370).
    INTRO_SIDS = %w[123256 123259].freeze
    ANNAL_SIDS = %w[123699 123701 123731 123754 123756].freeze

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "torot", name: "TOROT", adapter_class: "T", license_class: "open"
      )
    end

    def seed_chronicle(sids: INTRO_SIDS + ANNAL_SIDS)
      doc = Nabu::Store::Document.create(
        source_id: @source.id, urn: "urn:nabu:proiel:lav", title: "The Primary Chronicle",
        language: "orv", content_sha256: "lav", revision: 1, withdrawn: false
      )
      sids.each_with_index do |sid, sequence|
        Nabu::Store::Passage.create(
          document_id: doc.id, urn: "urn:nabu:proiel:lav:#{sid}", sequence: sequence,
          language: "orv", text: "x#{sid}", text_normalized: "x#{sid}",
          content_sha256: sid, revision: 1, withdrawn: false
        )
      end
      doc
    end

    def build!
      Nabu::Store::AxisBuilder.rebuild!(catalog: @db, canonical_dir: FIXTURE_DIR)
    end

    def rows_for(doc)
      @db[:document_axes].where(document_id: doc.id).order(:id).all
    end

    def test_annal_divs_become_passage_grain_rows_with_am_converted_spans
      doc = seed_chronicle
      build!
      envelope, *annals = rows_for(doc)
      assert_equal 3, annals.size

      # AM 6360 → 851/852 CE (the September/March year ambiguity is a span).
      assert_equal 851, annals[0].fetch(:not_before)
      assert_equal 852, annals[0].fetch(:not_after)
      assert_equal "AM 6360", annals[0].fetch(:date_raw)
      assert_equal "am", annals[0].fetch(:precision)
      assert_equal 2, annals[0].fetch(:passage_seq_from) # sids 123699/123701 → seq 2..3
      assert_equal 3, annals[0].fetch(:passage_seq_to)

      # Bare "6361" — a single-sentence annal.
      assert_equal 852, annals[1].fetch(:not_before)
      assert_equal 853, annals[1].fetch(:not_after)
      assert_equal 4, annals[1].fetch(:passage_seq_from)
      assert_equal 4, annals[1].fetch(:passage_seq_to)

      # The range title "6369–6370: The Varangians…" envelopes both AM years.
      assert_equal 860, annals[2].fetch(:not_before)
      assert_equal 862, annals[2].fetch(:not_after)
      assert_equal "AM 6369–6370", annals[2].fetch(:date_raw)

      refute_nil envelope # asserted in detail below
    end

    def test_document_grain_envelope_row_spans_all_annals
      doc = seed_chronicle
      build!
      envelope = rows_for(doc).first
      assert_equal 851, envelope.fetch(:not_before)
      assert_equal 862, envelope.fetch(:not_after)
      assert_nil envelope.fetch(:passage_seq_from) # document grain
      assert_nil envelope.fetch(:passage_seq_to)
      assert_equal "torot", envelope.fetch(:axis_source)
      assert_equal "AM 6360 – AM 6369–6370", envelope.fetch(:date_raw)
    end

    def test_non_annal_div_is_skipped_and_counted
      seed_chronicle
      summary = build!
      assert_equal 3, summary.torot_annals # Introduction is not an annal
      assert_equal 1, summary.torot
    end

    def test_missing_passages_shrink_the_anchor_never_break_it
      # Sentence 123701 (second sentence of annal 6360) never reached the
      # catalog (an empty-text sentence, say): the annal anchors on what exists.
      doc = seed_chronicle(sids: INTRO_SIDS + %w[123699 123731 123754 123756])
      build!
      first_annal = rows_for(doc)[1] # the AM 6360 row
      assert_equal 2, first_annal.fetch(:passage_seq_from)
      assert_equal 2, first_annal.fetch(:passage_seq_to)
    end

    def test_chronicle_absent_from_catalog_inserts_nothing
      build!
      assert_equal 0, @db[:document_axes].count
    end

    def test_rebuild_is_idempotent
      doc = seed_chronicle
      build!
      build!
      assert_equal 4, @db[:document_axes].where(document_id: doc.id).count
    end
  end
end
