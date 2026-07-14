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

    def make_document(urn:, withdrawn: false, source: @source)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: "t", language: "grc",
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    # sequence is unique per (document_id, sequence); callers pass distinct seqs.
    def make_passage(document, urn:, text_normalized:, sequence:, withdrawn: false,
                     language: "grc", annotations: nil)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text_normalized, text_normalized: text_normalized,
        content_sha256: "x", revision: 1, withdrawn: withdrawn,
        annotations_json: annotations ? JSON.generate(annotations) : "{}"
      )
    end

    # The stored annotation shape both treebank parser families emit: a
    # "tokens" array of lean hashes with "lemma"/"form" (ConlluParser keeps the
    # CoNLL-U LEMMA/FORM columns; ProielParser the token @lemma/@form attrs).
    def token_annotations(*pairs)
      { "tokens" => pairs.map { |lemma, form| { "lemma" => lemma, "form" => form }.compact } }
    end

    def rebuild! = Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    def fts = @fulltext[:passages_fts]

    def lemmas = @fulltext[Nabu::Store::Indexer::LEMMA_TABLE]

    # Raw MATCH: the Indexer's contract is index-as-stored, so tests query
    # with the already-folded form (query-side folding is Search's job).
    def match(query)
      fts.where(Sequel.lit("passages_fts MATCH ?", query)).all
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

    # P6-4: text_normalized is already the boundary-minted search form, so the
    # Indexer applies NO transform — what the catalog stores is byte-for-byte
    # what the index carries.
    def test_indexes_text_normalized_as_stored
      doc = make_document(urn: "urn:d:1")
      # Deliberately accented: if the Indexer still folded, the stored index
      # form would differ from the catalog column.
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "μῆνιν", sequence: 0)
      rebuild!

      assert_equal "μῆνιν", fts.first.fetch(:text_normalized),
                   "index must carry text_normalized exactly as stored"
    end

    # The boundary-folded form is findable by its own bytes (the end-to-end
    # accent-insensitive contract now lives in Search + Normalize.search_form).
    def test_folded_search_form_findable_as_indexed
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "μηνιν", sequence: 0)
      rebuild!

      hits = match("μηνιν")
      assert_equal 1, hits.size
      assert_equal "urn:d:1:1", hits.first.fetch(:urn)
    end

    def test_passage_id_column_links_back_to_the_catalog
      doc = make_document(urn: "urn:d:1")
      passage = make_passage(doc, urn: "urn:d:1:1", text_normalized: "alpha", sequence: 0)
      rebuild!

      assert_equal [passage.id], fts.select_map(:passage_id)
    end

    # -- the lemma index (P7-5) ----------------------------------------------

    def test_lemma_rows_built_from_stored_annotations
      doc = make_document(urn: "urn:d:1")
      passage = make_passage(doc, urn: "urn:d:1:1", text_normalized: "λεγουσι", sequence: 0,
                                  annotations: token_annotations(%w[λέγω λέγουσι]))
      rebuild!

      row = lemmas.first
      assert_equal 1, lemmas.count
      assert_equal "λεγω", row.fetch(:lemma_folded), "the index side folds the lemma (search_form)"
      assert_equal "λέγω", row.fetch(:lemma_raw), "the upstream spelling is kept for display"
      assert_equal "λέγουσι", row.fetch(:surface_forms)
      assert_equal passage.id, row.fetch(:passage_id)
      assert_equal "urn:d:1:1", row.fetch(:urn)
      assert_equal "grc", row.fetch(:language)
      assert(@fulltext.indexes(:passage_lemmas).values.any? { |i| i[:columns] == [:language] },
             "passage_lemmas.language index missing (P18-4 follow-up — the language card scans without it)")
    end

    # Non-treebank passages (annotations "{}", or annotations without token
    # lemmas — e.g. EpiDoc gap info) contribute no rows: honest absence.
    def test_passages_without_lemma_annotations_contribute_no_rows
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "μηνιν", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text_normalized: "αειδε", sequence: 1,
                        annotations: { "citation" => "1.1" })
      # A CoNLL-U MWT range token has form but NO lemma; it must not index.
      make_passage(doc, urn: "urn:d:1:3", text_normalized: "essetque", sequence: 2,
                        annotations: { "tokens" => [{ "id" => "14-15", "form" => "essetque" }] })
      rebuild!

      assert_equal 0, lemmas.count
    end

    # One row per (passage, folded lemma): repeated attestations aggregate
    # their distinct surface forms instead of multiplying rows.
    def test_lemma_rows_dedup_per_passage_with_aggregated_surface_forms
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "x", sequence: 0,
                        annotations: token_annotations(%w[λέγω λέγειν], %w[λέγω εἰπεῖν], %w[λέγω λέγειν]))
      rebuild!

      assert_equal 1, lemmas.count
      assert_equal "λέγειν, εἰπεῖν", lemmas.first.fetch(:surface_forms)
    end

    # The fold is per-language, like text_normalized: a Latin lemma takes the
    # lat v→u rule; final-sigma Greek dictionary forms take grc ς→σ (λόγος —
    # lemmas routinely END in ς — folds to λογοσ, consistent because BOTH
    # sides fold: Query::LemmaSearch matches the query_forms union).
    def test_lemma_fold_is_per_language
      grc = make_document(urn: "urn:d:grc")
      make_passage(grc, urn: "urn:d:grc:1", text_normalized: "λογον", sequence: 0,
                        annotations: token_annotations(%w[λόγος λόγον]))
      lat = make_document(urn: "urn:d:lat")
      make_passage(lat, urn: "urn:d:lat:1", text_normalized: "uidemur", sequence: 0,
                        language: "lat", annotations: token_annotations(%w[video videmur]))
      rebuild!

      assert_equal "λογοσ", lemmas.where(urn: "urn:d:grc:1").get(:lemma_folded),
                   "grc final sigma folds ς→σ in the dictionary form"
      assert_equal "uideo", lemmas.where(urn: "urn:d:lat:1").get(:lemma_folded),
                   "lat folds v→u in the lemma"
    end

    def test_lemma_rows_of_withdrawn_passages_excluded
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "x", sequence: 0, withdrawn: true,
                        annotations: token_annotations(%w[λέγω λέγει]))
      rebuild!

      assert_equal 0, lemmas.count
    end

    def test_lemma_table_rebuild_is_idempotent
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "x", sequence: 0,
                        annotations: token_annotations(%w[λέγω λέγει]))

      rebuild!
      rebuild!

      assert_equal 1, lemmas.count, "drop+recreate leaves no duplicate lemma rows"
    end

    # -- the trigram fragment index (P16-4) ----------------------------------

    def trigrams = @fulltext[Nabu::Store::Indexer::TRIGRAM_TABLE]

    def trigram_scope = @fulltext[Nabu::Store::Indexer::TRIGRAM_SCOPE_TABLE]

    # A second source standing in for a literary (non-documentary) shelf.
    def literary_source
      @literary_source ||= Nabu::Store::Source.create(
        slug: "lit", name: "Lit", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def test_trigram_index_scoped_to_the_fuzzy_slugs_only
      doc = make_document(urn: "urn:d:pap")
      make_passage(doc, urn: "urn:d:pap:1", text_normalized: "στρατηγοσ", sequence: 0)
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "στρατηγοσ και", sequence: 0)

      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, fuzzy_slugs: ["s"])

      assert_equal %w[urn:d:pap:1], trigrams.select_map(:urn),
                   "the literary source's passages must NOT be trigram-indexed"
      assert_equal %w[s], trigram_scope.select_map(:slug), "the scope table records what was indexed"
      assert_equal 2, fts.count, "the word index stays corpus-wide"
    end

    def test_trigram_tables_exist_empty_without_fuzzy_slugs
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "στρατηγοσ", sequence: 0)
      rebuild!

      assert_equal 0, trigrams.count, "no scope, no rows — the table still exists (queries degrade)"
      assert_equal 0, trigram_scope.count
    end

    def test_trigram_index_supports_infix_match
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "τωι στρατηγωι χαιρειν", sequence: 0)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, fuzzy_slugs: ["s"])

      hits = trigrams.where(Sequel.lit("passages_trigram MATCH ?", '"ρατηγ"')).all
      assert_equal %w[urn:d:1:1], hits.map { |row| row.fetch(:urn) },
                   "a mid-word fragment must match — the point of the trigram tokenizer"
    end

    def test_trigram_excludes_withdrawn_passages
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "gone away", sequence: 0, withdrawn: true)
      make_passage(doc, urn: "urn:d:1:2", text_normalized: "here now", sequence: 1)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, fuzzy_slugs: ["s"])

      assert_equal %w[urn:d:1:2], trigrams.select_map(:urn)
    end

    def test_trigram_reindex_is_idempotent
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "στρατηγοσ", sequence: 0)

      2.times { Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, fuzzy_slugs: ["s"]) }

      assert_equal 1, trigrams.count, "drop+recreate leaves no duplicate trigram rows"
      assert_equal 1, trigram_scope.count, "…nor duplicate scope rows"
    end

    # Rebuild-safety: the trigram index is derived-of-derived — a FRESH
    # fulltext db regenerates it from the catalog's passages alone.
    def test_trigram_index_regenerates_into_a_fresh_fulltext_db
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "στρατηγοσ", sequence: 0)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, fuzzy_slugs: ["s"])

      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh, fuzzy_slugs: ["s"])
        assert_equal %w[urn:d:1:1], fresh[Nabu::Store::Indexer::TRIGRAM_TABLE].select_map(:urn)
        assert_equal %w[s], fresh[Nabu::Store::Indexer::TRIGRAM_SCOPE_TABLE].select_map(:slug)
      ensure
        fresh.disconnect
      end
    end
  end
end
