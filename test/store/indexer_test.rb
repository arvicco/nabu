# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::Indexer (P4-1). Catalog is a fresh in-memory SQLite (the house
  # store-test pattern); the fulltext index is a SEPARATE in-memory connection
  # held open for the whole test — an FTS5 sqlite::memory: db only survives as
  # long as its connection does, so #teardown disconnects it last.
  class IndexerTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @source = Nabu::Store::Source.create(
        slug: "s", name: "S", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- helpers -------------------------------------------------------------

    def make_document(urn:, withdrawn: false)
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: "t", language: "grc",
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    # sequence is unique per (document_id, sequence); callers pass distinct seqs.
    def make_passage(document, urn:, text_normalized:, sequence:, withdrawn: false)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: "grc",
        text: text_normalized, text_normalized: text_normalized,
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def rebuild! = Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    def fts = @fulltext[:passages_fts]

    def match(query)
      fts.where(Sequel.lit("passages_fts MATCH ?", Nabu::Normalize.fold_diacritics(query))).all
    end

    # -- tests ---------------------------------------------------------------

    def test_indexes_exactly_the_live_passages
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "μῆνιν", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text_normalized: "ἄειδε", sequence: 1)

      assert_equal 2, rebuild!, "returns the count indexed"
      assert_equal 2, fts.count
      assert_equal %w[urn:d:1:1 urn:d:1:2], fts.order(:urn).select_map(:urn)
    end

    def test_withdrawn_passage_excluded
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "live", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text_normalized: "gone", sequence: 1, withdrawn: true)

      assert_equal 1, rebuild!
      assert_equal %w[urn:d:1:1], fts.select_map(:urn)
    end

    def test_passages_of_a_withdrawn_document_excluded
      live = make_document(urn: "urn:d:live")
      make_passage(live, urn: "urn:d:live:1", text_normalized: "here", sequence: 0)
      # A withdrawn document whose OWN passages are not flagged: the two-level
      # visibility rule must still exclude them.
      dead = make_document(urn: "urn:d:dead", withdrawn: true)
      make_passage(dead, urn: "urn:d:dead:1", text_normalized: "hidden", sequence: 0)

      assert_equal 1, rebuild!
      assert_equal %w[urn:d:live:1], fts.select_map(:urn)
    end

    def test_reindex_is_idempotent
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "alpha", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text_normalized: "beta", sequence: 1)

      assert_equal 2, rebuild!
      assert_equal 2, rebuild!, "a second rebuild indexes the same count"
      assert_equal 2, fts.count, "drop+recreate leaves no duplicate rows"
    end

    # remove_diacritics 2 alone cannot fold precomposed polytonic Greek, so the
    # Indexer folds the search form (Normalize.fold_diacritics). Proof: a
    # passage stored with its polytonic accents intact is found by a
    # diacritic-stripped query.
    def test_greek_passage_findable_by_diacritic_stripped_query
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "μῆνιν", sequence: 0)
      rebuild!

      hits = match("μηνιν")
      assert_equal 1, hits.size, "μῆνιν must be found by the diacritic-stripped μηνιν"
      assert_equal "urn:d:1:1", hits.first.fetch(:urn)
    end

    def test_passage_id_column_links_back_to_the_catalog
      doc = make_document(urn: "urn:d:1")
      passage = make_passage(doc, urn: "urn:d:1:1", text_normalized: "alpha", sequence: 0)
      rebuild!

      assert_equal [passage.id], fts.select_map(:passage_id)
    end
  end
end
