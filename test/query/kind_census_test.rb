# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::KindCensus (P99-3 — №R-63): the kind axis' browse view —
  # head-grain class counts (distinct documents, distinct sources), the
  # honesty buckets counted beside the classes, the unclassified
  # remainder announced, and the --unmapped curation worklist (raw
  # values by count per source). Indexed GROUP BY only — quasi-instant
  # per the desk-commands law.
  class KindCensusTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
      @edr = source("edr")
      @cdli = source("cdli")
      @bare = source("bare") # live docs, no kind rows — unclassified
      kind(doc(@edr, "urn:e:1"), "funerary/epitaph", "sepulcralis")
      kind(doc(@edr, "urn:e:2"), "funerary", "tombstone")
      d3 = doc(@cdli, "urn:c:1")
      kind(d3, "funerary/epitaph", "Grabstein")
      kind(d3, "legal", "Legal")
      kind(doc(@cdli, "urn:c:2"), "unmapped", "Literary")
      kind(doc(@cdli, "urn:c:3"), "unknown", "uncertain")
      doc(@bare, "urn:b:1")
      doc(@bare, "urn:b:2")
    end

    def source(slug)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "X",
                                 license_class: "open")
    end

    def doc(src, urn)
      Nabu::Store::Document.create(source_id: src.id, urn: urn, language: "la",
                                   title: "t", canonical_path: urn,
                                   content_sha256: Digest::SHA256.hexdigest(urn))
    end

    def kind(document, value, raw)
      @db[:document_facets].insert(document_id: document.id, facet: "kind",
                                   value: value, raw: raw)
    end

    def census = Nabu::Query::KindCensus.new(catalog: @db).run

    def test_heads_fold_subs_and_count_distinct_documents_and_sources
      row = census.classes.find { |r| r.head == "funerary" }
      assert_equal 3, row.documents, "epitaph + bare head fold into one funerary family"
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
      assert_equal 2, census.unclassified_documents, "bare's live docs"
      assert_equal 1, census.unclassified_sources
      assert_equal 5, census.classified_documents,
                   "every doc carrying any kind row, buckets included"
    end

    def test_summary_carries_elapsed
      assert_operator census.seconds, :>=, 0
    end

    def test_unmapped_worklist_ranks_raw_values_per_source
      rows = Nabu::Query::KindCensus.new(catalog: @db).unmapped_worklist
      assert_equal([["cdli", "Literary", 1]], rows.map { |r| [r.slug, r.raw, r.documents] })
    end
  end
end
