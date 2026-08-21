# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::TimelineBuilder::NikhEntryDates (P81-1): the leaf-grain
  # date harvest over the NIKH chronicle family — the per-entry machine
  # dates ("1617-01-00L0", the dateOccured @date attr) that ride passage
  # annotations raw become passage-grain year-run rows, and documents
  # WITHOUT a metadata date claim (bibyeonsa books, the goryeosa family,
  # sillok's undated prefaces) gain an honest document-grain envelope.
  # All date strings below are real fixture/catalog values.
  class NikhEntryDatesTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
    end

    def create_source(slug)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "T", license_class: "attribution")
    end

    def create_doc(source, urn, metadata: {})
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, language: "lzh", content_sha256: urn,
        revision: 1, withdrawn: false, metadata_json: JSON.generate(metadata)
      )
    end

    def add_passage(doc, seq, date)
      annotations = date.nil? ? {} : { "date" => date }
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "#{doc.urn}:#{seq + 1}", sequence: seq,
        language: "lzh", text: "文#{seq}", text_normalized: "文#{seq}",
        annotations_json: JSON.generate(annotations),
        content_sha256: "#{doc.urn}:#{seq}", revision: 1, withdrawn: false
      )
    end

    def rows_for(doc)
      @db[:document_axes].where(document_id: doc.id).order(:id).all
    end

    # bb_001's real shape: years INTERLEAVE non-monotonically (1617 前 1616),
    # and the book front carries NO date claim.
    def seed_bibyeonsa
      source = create_source("bibyeonsa")
      doc = create_doc(source, "urn:nabu:bibyeonsa:bb_001", metadata: { "volume" => "bb_001" })
      add_passage(doc, 0, "1617-01-00L0")
      add_passage(doc, 1, "1616-12-30L0")
      add_passage(doc, 2, "1617-01-01L0")
      add_passage(doc, 3, "1617-01-01L0")
      doc
    end

    def test_consecutive_same_year_entries_become_one_passage_grain_run
      doc = seed_bibyeonsa
      Nabu::Store::TimelineBuilder::NikhEntryDates.build(catalog: @db)
      envelope, *runs = rows_for(doc)

      assert_equal 3, runs.size, "1617 / 1616 / 1617 — interleaved years never merge"
      assert_equal([1617, 1616, 1617], runs.map { |r| r[:not_before] })
      assert_equal([1617, 1616, 1617], runs.map { |r| r[:not_after] })
      assert_equal([[0, 0], [1, 1], [2, 3]],
                   runs.map { |r| [r[:passage_seq_from], r[:passage_seq_to]] })
      assert_equal "1617-01-01L0", runs.last[:date_raw], "identical run endpoints collapse"
      assert_equal "1617-01-00L0", runs.first[:date_raw]
      assert(runs.all? { |r| r[:axis_source] == "bibyeonsa-entries" && r[:precision] == "year" })
      refute_nil envelope
    end

    def test_a_document_without_a_metadata_date_claim_gains_the_envelope_row
      doc = seed_bibyeonsa
      Nabu::Store::TimelineBuilder::NikhEntryDates.build(catalog: @db)
      envelope = rows_for(doc).first

      assert_equal 1616, envelope[:not_before]
      assert_equal 1617, envelope[:not_after]
      assert_nil envelope[:passage_seq_from], "document grain"
      assert_equal "1616-12-30L0 – 1617-01-01L0", envelope[:date_raw]
      assert_equal "bibyeonsa-entries", envelope[:axis_source]
    end

    def test_a_document_with_a_metadata_date_claim_gets_runs_but_no_second_envelope
      source = create_source("sillok")
      doc = create_doc(source, "urn:nabu:sillok:wza_100",
                       metadata: { "volume" => "wza_100",
                                   "date" => { "not_before" => 1863, "not_after" => 1863, "raw" => "1863" } })
      add_passage(doc, 0, "1863-12-08L0")
      add_passage(doc, 1, "1863-12-13L0")
      add_passage(doc, 2, "1864-01-02L0") # the lunar year straddles the CE boundary
      Nabu::Store::TimelineBuilder::NikhEntryDates.build(catalog: @db)
      rows = rows_for(doc)

      assert_equal 2, rows.size, "two year runs, NO envelope — MetadataDates owns the document grain"
      assert(rows.all? { |r| r[:passage_seq_from] }, "every row is passage grain")
      assert_equal([[1863, 0, 1], [1864, 2, 2]],
                   rows.map { |r| [r[:not_before], r[:passage_seq_from], r[:passage_seq_to]] })
    end

    def test_filler_and_unparseable_dates_are_skipped_counted_never_guessed
      source = create_source("goryeosa")
      doc = create_doc(source, "urn:nabu:goryeosa:g1", metadata: {})
      add_passage(doc, 0, "0877-01-99L0")  # real: zero-padded year, unknown month/day
      add_passage(doc, 1, "9999-99-99L0")  # real upstream filler — never a year
      add_passage(doc, 2, nil)             # an undated leaf
      summary = Nabu::Store::TimelineBuilder::NikhEntryDates.build(catalog: @db)
      envelope, *runs = rows_for(doc)

      assert_equal 1, runs.size
      assert_equal 877, runs.first[:not_before]
      assert_equal [877, 877], [envelope[:not_before], envelope[:not_after]]
      assert_equal 2, summary.fetch("goryeosa")[:undated_entries],
                   "the filler and the dateless leaf are counted, never guessed"
    end

    def test_summary_counts_documents_and_runs_per_slug
      seed_bibyeonsa
      summary = Nabu::Store::TimelineBuilder::NikhEntryDates.build(catalog: @db)
      assert_equal({ documents: 1, runs: 3, undated_entries: 0 }, summary.fetch("bibyeonsa"))
      assert_equal({ documents: 0, runs: 0, undated_entries: 0 }, summary.fetch("sjw"),
                   "a registered slug with no catalog rows reports zeros")
    end

    def test_refresh_source_is_idempotent_and_scoped
      doc = seed_bibyeonsa
      other_source = create_source("sillok")
      other = create_doc(other_source, "urn:nabu:sillok:wza_100", metadata: {})
      add_passage(other, 0, "1863-12-08L0")

      2.times { Nabu::Store::TimelineBuilder::NikhEntryDates.refresh_source!(catalog: @db, slug: "bibyeonsa") }
      Nabu::Store::TimelineBuilder::NikhEntryDates.refresh_source!(catalog: @db, slug: "sillok")

      assert_equal 4, rows_for(doc).size, "envelope + 3 runs — a re-refresh never duplicates"
      assert_equal 2, rows_for(other).size
      assert_equal 0, Nabu::Store::TimelineBuilder::NikhEntryDates.refresh_source!(catalog: @db, slug: "ref"),
                   "an unregistered slug refreshes to nothing"
    end

    def test_withdrawn_documents_and_passages_never_row
      source = create_source("bibyeonsa")
      doc = create_doc(source, "urn:nabu:bibyeonsa:bb_054", metadata: {})
      add_passage(doc, 0, "1698-01-01L0")
      @db[:documents].where(id: doc.id).update(withdrawn: true)
      Nabu::Store::TimelineBuilder::NikhEntryDates.build(catalog: @db)
      assert_empty rows_for(doc)
    end
  end
end
