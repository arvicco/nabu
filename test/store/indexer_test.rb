# frozen_string_literal: true

require "test_helper"
require "tmpdir"

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

    # -- the lemma tier column (P26-0) ---------------------------------------
    # The tier lives on the FULLTEXT-side passage_lemmas rows (no catalog
    # migration — drop-and-rebuild), declared per SOURCE via the registry's
    # lemma_tiers map (absent slug = gold).

    def test_lemma_rows_default_to_gold_tier
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "λεγουσι", sequence: 0,
                        annotations: token_annotations(%w[λέγω λέγουσι]))
      rebuild!

      assert_equal "gold", lemmas.first.fetch(:tier),
                   "no lemma_tiers map given — every row is gold (zero churn for existing sources)"
    end

    def test_lemma_tiers_map_labels_a_silver_source_per_row
      gold_doc = make_document(urn: "urn:d:gold")
      make_passage(gold_doc, urn: "urn:d:gold:1", text_normalized: "x", sequence: 0,
                             annotations: token_annotations(%w[λέγω λέγει]))
      silver_source = Nabu::Store::Source.create(
        slug: "auto", name: "Auto", adapter_class: "TestAdapter", license_class: "open"
      )
      silver_doc = make_document(urn: "urn:d:silver", source: silver_source)
      make_passage(silver_doc, urn: "urn:d:silver:1", text_normalized: "y", sequence: 0,
                               annotations: token_annotations(%w[λέγω λέγοντος]))

      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    lemma_tiers: { "auto" => "silver" })

      assert_equal "gold", lemmas.where(urn: "urn:d:gold:1").get(:tier),
                   "a source ABSENT from the map stays gold"
      assert_equal "silver", lemmas.where(urn: "urn:d:silver:1").get(:tier),
                   "the declared silver source's rows carry the tier"
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

    # -- incremental per-source refresh (P26-5) ------------------------------
    # refresh_source! deletes ONE source's rows from the passage-keyed tables
    # and re-inserts them from the current catalog — the sync-time replacement
    # for the full drop-and-rebuild. Its contract is ROW IDENTITY: after a
    # refresh, the fulltext state must equal what a from-scratch rebuild!
    # would produce (pinned below by building both and comparing row sets).

    def refresh!(slug: "s", **)
      Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: slug, **)
    end

    def test_refresh_reindexes_only_that_sources_rows
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "beta", sequence: 0)
      rebuild!

      # Both sources grow in the catalog; only "s" is refreshed.
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "gamma", sequence: 1)
      make_passage(lit, urn: "urn:d:lit:2", text_normalized: "delta", sequence: 1)
      refresh!

      assert_equal %w[urn:d:lit:1 urn:d:s:1 urn:d:s:2], fts.order(:urn).select_map(:urn),
                   "the refreshed source gains its new row; the other source's slice is untouched"
    end

    # The FTS-deletion mechanism proof (search before/after): passages_fts is
    # a REGULAR (contentful) FTS5 table, so per-row DELETE is real deletion —
    # a removed row must stop matching, and other sources' rows must not.
    def test_refresh_removes_withdrawn_passages_from_the_index
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "μηνιν αειδε", sequence: 0)
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "μηνιν ουλομενην", sequence: 0)
      rebuild!
      assert_equal 2, match("μηνιν").size, "both searchable before the withdrawal"

      Nabu::Store::Passage.first(urn: "urn:d:s:1").update(withdrawn: true)
      refresh!

      assert_equal %w[urn:d:lit:1], match("μηνιν").map { |row| row.fetch(:urn) },
                   "the withdrawn passage must stop matching; the other source's hit survives"
    end

    def test_refresh_returns_the_sources_live_passage_count_only
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1, withdrawn: true)
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "gamma", sequence: 0)
      rebuild!

      assert_equal 1, refresh!, "the count is the SOURCE's live rows, never the corpus total"
    end

    # The consistency proof: after add + revise + withdraw on one source, an
    # incremental refresh leaves passages_fts, passage_lemmas (tiers included),
    # the trigram slice + scope, and the reflex tables row-identical to a
    # from-scratch rebuild of a fresh fulltext db.
    def test_refresh_is_row_identical_to_a_full_rebuild
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "λεγει", sequence: 0,
                        annotations: token_annotations(%w[λέγω λέγει]))
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "outdated", sequence: 1)
      make_passage(doc, urn: "urn:d:s:3", text_normalized: "doomed", sequence: 2)
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "στρατηγοσ", sequence: 0,
                        annotations: token_annotations(%w[στρατηγός στρατηγοσ]))
      options = { fuzzy_slugs: ["s"], lemma_tiers: { "s" => "silver" } }
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, **options)

      # One source mutates: a passage is added, one revised (text AND lemma
      # annotations change), one withdrawn.
      make_passage(doc, urn: "urn:d:s:4", text_normalized: "fresh", sequence: 3,
                        annotations: token_annotations(%w[φέρω φέρει]))
      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(
        text_normalized: "revised", annotations_json: JSON.generate(token_annotations(%w[ὁράω ὁρᾷ]))
      )
      Nabu::Store::Passage.first(urn: "urn:d:s:3").update(withdrawn: true)
      refresh!(**options)

      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh, **options)
        %i[passages_fts passage_lemmas passages_trigram passages_trigram_scope
           reflex_roots reflex_root_stats].each do |table|
          assert_equal table_rows(fresh, table), table_rows(@fulltext, table),
                       "#{table} must be row-identical to a from-scratch rebuild"
        end
      ensure
        fresh.disconnect
      end
    end

    def table_rows(db, table)
      db[table].all.map { |row| row.sort_by { |key, _| key } }.sort_by(&:inspect)
    end

    # Bootstrap safety: against a fulltext db that has never been built (the
    # very first sync), refresh falls back to a FULL rebuild — every source
    # lands, and the return value is still the refreshed source's own count.
    def test_refresh_falls_back_to_a_full_rebuild_when_the_index_is_missing
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "beta", sequence: 0)

      assert_equal 1, refresh!, "the fallback still reports the SOURCE's count"
      assert_equal %w[urn:d:lit:1 urn:d:s:1], fts.order(:urn).select_map(:urn),
                   "the bootstrap fallback indexes the whole corpus"
    end

    # A pre-tier fulltext file (passage_lemmas without the P26-0 tier column)
    # cannot take tiered inserts — refresh detects the old shape and falls
    # back to the full rebuild, which re-creates the current schema.
    def test_refresh_falls_back_when_the_lemma_table_predates_the_tier_column
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "λεγει", sequence: 0,
                        annotations: token_annotations(%w[λέγω λέγει]))
      rebuild!
      @fulltext.alter_table(Nabu::Store::Indexer::LEMMA_TABLE) { drop_column :tier }

      assert_equal 1, refresh!
      assert_equal "gold", lemmas.first.fetch(:tier), "the fallback rebuilt the tiered shape"
    end

    def test_refresh_updates_the_trigram_slice_of_a_fuzzy_source
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "στρατηγοσ", sequence: 0)
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "ιπποσ", sequence: 0)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, fuzzy_slugs: %w[s lit])

      make_passage(doc, urn: "urn:d:s:2", text_normalized: "χαιρειν", sequence: 1)
      refresh!(fuzzy_slugs: %w[s lit])

      assert_equal %w[urn:d:lit:1 urn:d:s:1 urn:d:s:2], trigrams.order(:urn).select_map(:urn),
                   "the fuzzy source's trigram slice refreshes; the other slice is untouched"
      assert_equal %w[lit s], trigram_scope.order(:slug).select_map(:slug)
    end

    def test_refresh_leaves_the_trigram_index_alone_for_a_non_fuzzy_source
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "στρατηγοσ", sequence: 0)
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "ιπποσ", sequence: 0)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, fuzzy_slugs: ["s"])

      make_passage(lit, urn: "urn:d:lit:2", text_normalized: "λογοσ", sequence: 1)
      refresh!(slug: "lit", fuzzy_slugs: ["s"])

      assert_equal %w[urn:d:s:1], trigrams.select_map(:urn),
                   "a non-fuzzy source's refresh must not touch the trigram index"
      assert_equal %w[s], trigram_scope.select_map(:slug)
    end

    # Config-drift, the other direction: a source flagged fuzzy since the
    # last full build gains its trigram slice AND its scope row at refresh.
    def test_refresh_adds_the_trigram_slice_of_a_newly_flagged_source
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "στρατηγοσ", sequence: 0)
      rebuild! # no fuzzy slugs — empty trigram index

      refresh!(fuzzy_slugs: ["s"])

      assert_equal %w[urn:d:s:1], trigrams.select_map(:urn), "the newly flagged source's slice lands"
      assert_equal %w[s], trigram_scope.select_map(:slug)
    end

    # Scope honesty on config drift: a source de-flagged since the last full
    # build loses its trigram rows AND its scope row at its next refresh.
    def test_refresh_drops_the_trigram_slice_of_a_deflagged_source
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "στρατηγοσ", sequence: 0)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, fuzzy_slugs: ["s"])
      assert_equal 1, trigrams.count

      refresh!(fuzzy_slugs: [])

      assert_equal 0, trigrams.count, "the de-flagged source's trigram rows are removed"
      assert_equal 0, trigram_scope.count, "…and its scope row, so coverage reads honestly"
    end

    ALIGN_REGISTRY_YAML = <<~YAML
      nt:
        witnesses:
          - label: s-witness
            extractor: cts-verse
            documents:
              MARK: urn:d:s
    YAML

    def alignment_registry
      Dir.mktmpdir do |dir|
        path = File.join(dir, "alignments.yml")
        File.write(path, ALIGN_REGISTRY_YAML)
        return Nabu::AlignmentRegistry.load(path)
      end
    end

    def test_refresh_rebuilds_alignment_refs_when_the_source_holds_a_witness_document
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1.1", text_normalized: "verse", sequence: 0)
      registry = alignment_registry
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, alignments: registry)
      assert_equal 1, @fulltext[:alignment_refs].count

      make_passage(doc, urn: "urn:d:s:1.2", text_normalized: "next verse", sequence: 1)
      refresh!(alignments: registry)

      assert_equal ["MARK 1.1", "MARK 1.2"], @fulltext[:alignment_refs].order(:ref).select_map(:ref),
                   "a witness source's refresh regenerates the alignment index"
    end

    def test_refresh_skips_the_alignment_rebuild_for_a_non_witness_source
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1.1", text_normalized: "verse", sequence: 0)
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "prose", sequence: 0)
      registry = alignment_registry
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, alignments: registry)

      # A sentinel row proves the table was not dropped and rebuilt.
      @fulltext[:alignment_refs].insert(work: "nt", ref: "SENTINEL", document_urn: "x",
                                        passage_id: 999, passage_urn: "x", seq: 0)
      refresh!(slug: "lit", alignments: registry)

      assert_equal 1, @fulltext[:alignment_refs].where(ref: "SENTINEL").count,
                   "a non-witness source's refresh must not touch the alignment index"
    end

    def reflex_stats = @fulltext[Nabu::Store::ReflexRootsIndexer::STATS_TABLE]

    def test_refresh_rebuilds_the_reflex_stats_when_the_sources_lemma_rows_change
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "λεγει", sequence: 0,
                        annotations: token_annotations(%w[λέγω λέγει]))
      rebuild!
      assert_equal 1, reflex_stats.where(language: "grc").get(:gold_passages)

      make_passage(doc, urn: "urn:d:s:2", text_normalized: "φερει", sequence: 1,
                        annotations: token_annotations(%w[φέρω φέρει]))
      refresh!

      assert_equal 2, reflex_stats.where(language: "grc").get(:gold_passages),
                   "a lemma-bearing source's refresh re-snapshots the reflex stats"
    end

    def test_refresh_skips_the_reflex_rebuild_for_a_lemmaless_source
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "plain", sequence: 0)
      rebuild!

      # A sentinel row proves the stats table was not dropped and rebuilt.
      reflex_stats.insert(language: "zz-sentinel", gold_passages: 1)
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "more", sequence: 1)
      refresh!

      assert_equal 1, reflex_stats.where(language: "zz-sentinel").count,
                   "no lemma rows touched → the reflex closure must not rebuild"
    end

    # A dictionary sync mints no passages but DOES change the crosswalk the
    # closure is built from — the caller forces the reflex rebuild.
    def test_refresh_rebuilds_the_reflex_closure_when_reflexes_changed
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "plain", sequence: 0)
      rebuild!
      reflex_stats.insert(language: "zz-sentinel", gold_passages: 1)

      assert_equal 1, refresh!(reflexes_changed: true)
      assert_equal 0, reflex_stats.where(language: "zz-sentinel").count,
                   "reflexes_changed forces the closure rebuild"
    end
  end
end
