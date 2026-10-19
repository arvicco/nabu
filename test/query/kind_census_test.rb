# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::KindCensus (P99-3 — owner-ruled 2026-09-13): the kind axis' browse view,
  # read from PRECOMPILED data only — kind_stats (per-source per-head
  # counts, KindBuilder-written) + source_stats (library totals). The
  # one live query is the --unmapped worklist over the bucket subset.
  class KindCensusTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
      @edr = source("edr", live: 2)
      @cdli = source("cdli", live: 3)
      @bare = source("bare", live: 2) # live docs, no kind rows — unclassified
      stat(@edr, "funerary", 2)
      stat(@edr, nil, 2)
      stat(@cdli, "funerary", 1)
      stat(@cdli, "legal", 1)
      stat(@cdli, "unmapped", 1)
      stat(@cdli, "unknown", 1)
      stat(@cdli, nil, 3)
    end

    def source(slug, live:)
      src = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "X",
                                       license_class: "open")
      @db[:source_stats].insert(source_id: src.id, live_documents: live,
                                updated_at: Time.now, note: "")
      src
    end

    def stat(src, head, documents)
      @db[:kind_stats].insert(source_id: src.id, head: head, documents: documents)
    end

    def census = Nabu::Query::KindCensus.new(catalog: @db).run

    def test_heads_sum_documents_and_count_sources
      row = census.classes.find { |r| r.head == "funerary" }
      assert_equal 3, row.documents, "per-source distinct counts are additive"
      assert_equal 2, row.sources
      assert_equal 1, census.classes.find { |r| r.head == "legal" }.documents
    end

    def test_classes_rank_by_document_count_with_buckets_separated
      assert_equal %w[funerary legal], census.classes.map(&:head),
                   "unmapped and unknown are buckets, not class rows"
      assert_equal 1, census.unmapped_documents
      assert_equal 1, census.unknown_documents
    end

    def test_the_unclassified_remainder_is_announced
      assert_equal 5, census.classified_documents, "the NULL-head totals sum"
      assert_equal 2, census.unclassified_documents, "bare's live docs"
      assert_equal 1, census.unclassified_sources
    end

    def test_summary_carries_elapsed
      assert_operator census.seconds, :>=, 0
    end

    def test_missing_stats_table_is_the_honest_nil
      @db.drop_table(:kind_stats)
      assert_nil census, "a pre-032 catalog reports the hint, never a scan"
    end

    def test_unmapped_worklist_ranks_raw_values_per_source
      doc = Nabu::Store::Document.create(
        source_id: @cdli.id, urn: "urn:c:1", language: "la", title: "t",
        canonical_path: "urn:c:1", content_sha256: Digest::SHA256.hexdigest("urn:c:1")
      )
      @db[:document_facets].insert(document_id: doc.id, facet: "kind",
                                   value: "unmapped", raw: "Literary")
      rows = Nabu::Query::KindCensus.new(catalog: @db).unmapped_worklist
      assert_equal([["cdli", "Literary", 1]], rows.map { |r| [r.slug, r.raw, r.documents] })
    end

    # -- the open-vocabulary census (vocabulary: open) -------------------------
    #
    # KindBuilder precompiles an open source's uncovered values into
    # kind_stats under the `uncovered:` prefix; the census counts them
    # apart from the classes and never mistakes them for a head or a
    # classified source.

    def seed_open_vocabulary
      @eebo = source("eebo", live: 4)
      stat(@eebo, "sermon", 1)
      stat(@eebo, nil, 1)
      stat(@eebo, "uncovered:Plague.", 3)
      stat(@eebo, "uncovered:Ireland -- History.", 2)
      stat(@eebo, "uncovered:Quakers.", 2)
      stat(@eebo, "uncovered:", 3)
      @topical = source("topical", live: 2) # open, but nothing it carries is covered
      stat(@topical, "uncovered:Taxation.", 2)
      stat(@topical, "uncovered:", 2)
    end

    def test_uncovered_values_are_counted_apart_from_the_classes
      seed_open_vocabulary
      report = census
      refute(report.classes.any? { |r| r.head.start_with?("uncovered:") },
             "an uncovered census row is never a class row")
      assert_includes report.classes.map(&:head), "sermon"
      assert_equal 4, report.uncovered_values, "distinct uncovered values across open sources"
      assert_equal 5, report.uncovered_documents, "docs carrying any uncovered value (per-source totals sum)"
      assert_equal 2, report.uncovered_sources
    end

    def test_an_open_source_with_only_uncovered_values_stays_unclassified
      seed_open_vocabulary
      report = census
      assert_equal 6, report.classified_documents, "the NULL-head totals: edr 2 + cdli 3 + eebo 1"
      assert_equal 2, report.unclassified_sources,
                   "bare and the all-uncovered source — an uncovered row is not a classification"
    end

    def test_uncovered_worklist_ranks_values_with_a_cap_and_the_full_count
      seed_open_vocabulary
      worklist = Nabu::Query::KindCensus.new(catalog: @db).uncovered_worklist(limit: 2)
      assert_equal 4, worklist.total, "the full count rides beside the capped rows"
      assert_equal([["eebo", "Plague.", 3], ["eebo", "Ireland -- History.", 2]],
                   worklist.rows.map { |r| [r.slug, r.raw, r.documents] })
    end

    def test_uncovered_worklist_is_empty_without_open_sources
      worklist = Nabu::Query::KindCensus.new(catalog: @db).uncovered_worklist(limit: 10)
      assert_equal 0, worklist.total
      assert_empty worklist.rows
      assert_equal 0, census.uncovered_values
    end
  end
end
