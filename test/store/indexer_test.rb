# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "digest"
require "logger"
require "stringio"

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
                     language: "grc", annotations: nil, sha: "x")
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text_normalized, text_normalized: text_normalized,
        content_sha256: sha, revision: 1, withdrawn: withdrawn,
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

    def postings = @fulltext[Nabu::Store::Indexer::CHAR_POSTINGS_TABLE]

    def fts = @fulltext[:passages_fts]

    def lemmas = @fulltext[Nabu::Store::Indexer::LEMMA_TABLE]

    # A passage's lemma rows by its urn — resolved through the catalog, the
    # lemma table keys passages by id only.
    def lemmas_of(urn) = lemmas.where(passage_id: @catalog[:passages].where(urn: urn).select_map(:id))

    # Raw MATCH: the Indexer's contract is index-as-stored, so tests query
    # with the already-folded form (query-side folding is Search's job).
    # passages_fts is CONTENTLESS (P93-1) — no stored column values — so a
    # hit is its rowid (= passages.id), selected explicitly.
    def match(query)
      fts.where(Sequel.lit("passages_fts MATCH ?", query))
         .select(Sequel.lit("rowid").as(:rowid)).all
    end

    # Readable assertions map contentless rowids back through the catalog.
    def urns_of(ids) = @catalog[:passages].where(id: ids).select_map(:urn).sort

    def fts_urns = urns_of(fts.select_map(Sequel.lit("rowid")))

    def match_urns(query) = urns_of(match(query).map { |row| row.fetch(:rowid) })

    # -- tests ---------------------------------------------------------------

    def test_indexes_exactly_the_live_passages
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "μῆνιν", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text_normalized: "ἄειδε", sequence: 1)

      assert_equal 2, rebuild!, "returns the count indexed"
      assert_equal 2, fts.count
      assert_equal %w[urn:d:1:1 urn:d:1:2], fts_urns
    end

    def test_withdrawn_passage_excluded
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "live", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text_normalized: "gone", sequence: 1, withdrawn: true)

      assert_equal 1, rebuild!
      assert_equal %w[urn:d:1:1], fts_urns
    end

    def test_passages_of_a_withdrawn_document_excluded
      live = make_document(urn: "urn:d:live")
      make_passage(live, urn: "urn:d:live:1", text_normalized: "here", sequence: 0)
      # A withdrawn document whose OWN passages are not flagged: the two-level
      # visibility rule must still exclude them.
      dead = make_document(urn: "urn:d:dead", withdrawn: true)
      make_passage(dead, urn: "urn:d:dead:1", text_normalized: "hidden", sequence: 0)

      assert_equal 1, rebuild!
      assert_equal %w[urn:d:live:1], fts_urns
    end

    def test_reindex_is_idempotent
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "alpha", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text_normalized: "beta", sequence: 1)

      assert_equal 2, rebuild!
      assert_equal 2, rebuild!, "a second rebuild indexes the same count"
      assert_equal 2, fts.count, "drop+recreate leaves no duplicate rows"
    end

    # P93-1: a fresh build mints a CONTENTLESS table — the folded
    # text lives ONCE, in the catalog; the index stores only its inverted
    # index. No urn/passage_id payload columns exist, and reads of the
    # declared columns return NULL (contentless semantics) — MATCH is the
    # only read the table serves. P6-4 still holds upstream: what feeds the
    # tokenizer is text_normalized byte-for-byte (accent-folded μηνιν is
    # findable below because the INDEX side applied no second transform).
    def test_fresh_build_is_contentless
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "μηνιν", sequence: 0)
      rebuild!

      refute_includes fts.columns, :urn, "no payload columns in the contentless shape"
      refute_includes fts.columns, :passage_id
      assert_nil fts.first.fetch(:text_normalized),
                 "contentless — the text is never stored a second time (the contentless-index point)"
      assert_equal 1, match("μηνιν").size, "…but the inverted index still answers MATCH"
    end

    # The boundary-folded form is findable by its own bytes (the end-to-end
    # accent-insensitive contract now lives in Search + Normalize.search_form).
    def test_folded_search_form_findable_as_indexed
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "μηνιν", sequence: 0)
      rebuild!

      assert_equal %w[urn:d:1:1], match_urns("μηνιν")
    end

    # P93-1: identity in the contentless shape is the ROWID, minted as the
    # catalog passage id — the join back to pristine text and annotations.
    def test_rowid_is_the_catalog_passage_id
      doc = make_document(urn: "urn:d:1")
      passage = make_passage(doc, urn: "urn:d:1:1", text_normalized: "alpha", sequence: 0)
      rebuild!

      assert_equal [passage.id], fts.select_map(Sequel.lit("rowid"))
    end

    # -- the language column (P42-3) -----------------------------------------
    # passages_fts carries each row's language as ONE indexed sentinel token
    # ("0lang" + folded code) so Query::Search can put --lang INSIDE the
    # MATCH (the P40-r2 window-starvation genus). Sentinel, not the bare
    # code: bare codes are real words ("is") and would pollute both plain
    # MATCHes and the P42-2 fts5vocab df probe.

    # The pre-P42-3 table shape — the owner's live fulltext file until the
    # next full rebuild.
    OLD_FTS_DDL = <<~SQL
      CREATE VIRTUAL TABLE passages_fts USING fts5(
        text_normalized,
        urn UNINDEXED,
        passage_id UNINDEXED,
        tokenize = 'unicode61 remove_diacritics 2'
      )
    SQL

    def test_fresh_build_carries_the_language_sentinel_token
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "aurora", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text_normalized: "aurora", sequence: 1, language: "lat")
      rebuild!

      assert_includes fts.columns, :language, "a from-scratch build mints the P42-3 column"
      assert_equal %w[urn:d:1:2], match_urns(%{aurora AND language : ("0langlat")}),
                   "the sentinel token filters the MATCH itself — the P42-3 point"
    end

    def test_language_token_collapses_multi_part_codes_to_one_equality_token
      deva = make_document(urn: "urn:d:deva")
      make_passage(deva, urn: "urn:d:deva:1", text_normalized: "dharman", sequence: 0,
                         language: "san-Deva")
      iast = make_document(urn: "urn:d:iast")
      make_passage(iast, urn: "urn:d:iast:1", text_normalized: "dharman", sequence: 0,
                         language: "san")
      rebuild!

      assert_equal "0langsandeva", Nabu::Store::Indexer.language_token("san-Deva"),
                   "downcased, non-alphanumerics stripped — one token, never several"
      assert_equal %w[urn:d:iast:1], match_urns(%{dharman AND language : ("0langsan")}),
                   "a san filter must NOT prefix-bleed into san-Deva rows (equality, as the catalog WHERE had)"
    end

    def test_incremental_refresh_writes_the_old_shape_into_a_pre_rebuild_table
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      # Downgrade to the pre-P42-3 shape: the openiti load pattern — the
      # owner's live file keeps taking incremental syncs until the rebuild.
      @fulltext.drop_table(:passages_fts)
      @fulltext.run(OLD_FTS_DDL)

      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      assert_equal 2, refresh!
      refute_includes fts.columns, :language, "an incremental sync never upgrades the table shape"
      assert_equal %w[urn:d:s:1 urn:d:s:2], fts.order(:urn).select_map(:urn),
                   "new syncs land in the old shape unchanged"
    end

    # -- the source column (P81-3) -------------------------------------------
    # passages_fts carries each row's SOURCE SLUG as one indexed sentinel
    # token ("0src" + folded slug) so Query::Search can put --source/--axis
    # INSIDE the MATCH — the same starvation genus as P42-3's language
    # column, found live 2026-08-20 (`search 王 --source sillok` empty while
    # sillok holds matches: the global top-window held none).

    # The pre-P81-3 table shape (language column present, no source) — the
    # owner's live fulltext file until the next full rebuild.
    PRE_SOURCE_FTS_DDL = <<~SQL
      CREATE VIRTUAL TABLE passages_fts USING fts5(
        text_normalized,
        language,
        urn UNINDEXED,
        passage_id UNINDEXED,
        tokenize = 'unicode61 remove_diacritics 2'
      )
    SQL

    def test_fresh_build_carries_the_source_sentinel_token
      other = Nabu::Store::Source.create(
        slug: "nabu-data", name: "N", adapter_class: "TestAdapter", license_class: "open"
      )
      make_passage(make_document(urn: "urn:d:1"), urn: "urn:d:1:1", text_normalized: "aurora", sequence: 0)
      make_passage(make_document(urn: "urn:d:2", source: other),
                   urn: "urn:d:2:1", text_normalized: "aurora", sequence: 0)
      rebuild!

      assert_includes fts.columns, :source, "a from-scratch build mints the P81-3 column"
      assert_equal "0srcnabudata", Nabu::Store::Indexer.source_token("nabu-data"),
                   "downcased, non-alphanumerics stripped — one token per slug, never several"
      assert_equal %w[urn:d:2:1], match_urns(%{aurora AND source : ("0srcnabudata")}),
                   "the sentinel token filters the MATCH itself — the P81-3 point"
    end

    def test_incremental_refresh_writes_the_pre_source_shape_unchanged
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      # Downgrade to the pre-P81-3 shape (language yes, source no): the
      # owner's live file keeps taking incremental syncs until the rebuild.
      @fulltext.drop_table(:passages_fts)
      @fulltext.run(PRE_SOURCE_FTS_DDL)

      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      assert_equal 2, refresh!
      refute_includes fts.columns, :source, "an incremental sync never upgrades the table shape"
      assert_equal "0langgrc", fts.where(urn: "urn:d:s:2").get(:language),
                   "the language token still writes into a language-bearing table"
    end

    # -- the contentless shape (P93-1) --------------------------------
    # A fresh build mints passages_fts contentless (rowid = passages.id, no
    # payload columns); a legacy CONTENTFUL file — the owner's live fulltext
    # until the next full rebuild — keeps taking syncs in its own shape,
    # payload columns populated.

    # The pre-P93-1 shape (language + source present, contentful).
    PRE_CONTENTLESS_FTS_DDL = <<~SQL
      CREATE VIRTUAL TABLE passages_fts USING fts5(
        text_normalized,
        language,
        source,
        urn UNINDEXED,
        passage_id UNINDEXED,
        tokenize = 'unicode61 remove_diacritics 2'
      )
    SQL

    def test_incremental_refresh_writes_the_contentful_shape_unchanged
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      @fulltext.drop_table(:passages_fts)
      @fulltext.run(PRE_CONTENTLESS_FTS_DDL)

      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      assert_equal 2, refresh!
      assert_equal %w[urn:d:s:1 urn:d:s:2], fts.order(:urn).select_map(:urn),
                   "a pre-P93 contentful file keeps its payload columns populated through syncs"
      assert_equal "0langgrc", fts.where(urn: "urn:d:s:2").get(:language)
      assert_equal "0srcs", fts.where(urn: "urn:d:s:2").get(:source)
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
      refute row.key?(:urn), "the passage urn is derivable from passage_id — never stored twice"
      assert_equal "grc", row.fetch(:language)
      assert(@fulltext.indexes(:passage_lemmas).values.any? { |i| i[:columns] == [:language] },
             "passage_lemmas.language index missing (P18-4 follow-up — the language card scans without it)")
    end

    # The fts_lemma v2 shape: passage-keyed lookups (sync deletes, the
    # frequency snapshots, the silver coverage guard, parallels/cognates/
    # vocab) ride a passage_id B-tree; the urn column and its index are gone.
    def test_fresh_lemma_table_is_passage_keyed
      make_passage(make_document(urn: "urn:d:1"), urn: "urn:d:1:1", text_normalized: "λεγουσι", sequence: 0,
                                                  annotations: token_annotations(%w[λέγω λέγουσι]))
      rebuild!

      refute_includes lemmas.columns, :urn
      assert_nil Nabu::Store::Indexer.require_v2_lemmas!(@fulltext), "the v2 guard passes a fresh table"
      indexed = @fulltext.indexes(:passage_lemmas).values.map { |i| i[:columns] }
      assert_equal [%i[language], %i[lemma_folded], %i[passage_id]], indexed.sort
      assert_equal "v2-passage-keyed", Nabu::Store::Indexer::STAGE_VERSIONS.fetch("fts_lemma"),
                   "the narrowing is a derivation change: a v1-stamped index reads stale"
    end

    # The v1 lemma shape (urn column + urn index) is retired ahead of the
    # from-scratch rebuild that mints v2 everywhere: an incremental refresh
    # over a v1 file refuses with the rebuild hint instead of keeping the
    # urn-keyed dual path alive.
    def test_incremental_refresh_refuses_a_v1_lemma_table_with_the_rebuild_hint
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "λεγει", sequence: 0,
                        annotations: token_annotations(%w[λέγω λέγει]))
      rebuild!
      LegacyLemmaTable.widen!(@fulltext, @catalog)

      error = assert_raises(Nabu::Store::Indexer::LegacyLemmaShape) { refresh! }
      assert_match(/predates the v2 lemma shape.*full rebuild/, error.message)
      assert_match(/nabu rebuild/, error.message, "the hint names the command")
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

      assert_equal "λογοσ", lemmas_of("urn:d:grc:1").get(:lemma_folded),
                   "grc final sigma folds ς→σ in the dictionary form"
      assert_equal "uideo", lemmas_of("urn:d:lat:1").get(:lemma_folded),
                   "lat folds v→u in the lemma"
    end

    def test_lemma_rows_of_withdrawn_passages_excluded
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "x", sequence: 0, withdrawn: true,
                        annotations: token_annotations(%w[λέγω λέγει]))
      rebuild!

      assert_equal 0, lemmas.count
    end

    # P105-5d: the fts+lemma slice walked cbeta's 8.75M passages for
    # ~55 minutes with ZERO ticks — the no-silent-passes class. The batch
    # loop ticks per batch now, on both the rebuild and refresh paths.
    TickSpy = Struct.new(:ticks) do
      def stage(*); end
      def load_tick(count, _errored) = (self.ticks ||= []) << count
    end

    def test_passage_batches_tick_progress_on_rebuild_and_refresh
      doc = make_document(urn: "urn:d:1")
      rows = (0...Nabu::Store::Indexer::BATCH_SIZE).map do |i|
        { document_id: doc.id, urn: "urn:d:1:#{i}", sequence: i, language: "grc",
          text: "alpha", text_normalized: "alpha", content_sha256: "x", revision: 1,
          withdrawn: false, annotations_json: "{}" }
      end
      @catalog[:passages].multi_insert(rows)
      spy = TickSpy.new([])
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, progress: spy)
      refute_empty spy.ticks, "a full batch must tick under rebuild"

      spy = TickSpy.new([])
      Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext,
                                           slug: "s", progress: spy)
      refute_empty spy.ticks, "a full batch must tick under the incremental slice"
    end

    def test_a_partial_batch_stays_silent
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "alpha", sequence: 0)
      spy = TickSpy.new([])
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, progress: spy)
      assert_empty spy.ticks, "a small corpus must not chatter (nor stamp passage " \
                              "counts onto sync's open parse+load stage)"
    end

    def test_lemma_table_rebuild_is_idempotent
      doc = make_document(urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "x", sequence: 0,
                        annotations: token_annotations(%w[λέγω λέγει]))

      rebuild!
      rebuild!

      assert_equal 1, lemmas.count, "drop+recreate leaves no duplicate lemma rows"
    end

    # -- the per-source lemma-key registry (P118-R4 S1) ----------------------
    # bhsa/dss carry their gold lexemes under their OWN token keys (bhsa
    # lex_utf8; dss Abegg's lex + the BHSA crosswalk lex_utf8_etcbc) — never
    # "lemma" — so before the registry ~0.9M tokens never reached --lemma.

    def make_slug_source(slug)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter",
                                 license_class: "open")
    end

    def test_bhsa_lexemes_mint_lemma_rows_from_lex_utf8
      doc = make_document(urn: "urn:d:bhsa", source: make_slug_source("bhsa"))
      make_passage(doc, urn: "urn:d:bhsa:1", text_normalized: "x", sequence: 0, language: "hbo",
                        annotations: { "tokens" => [
                          { "form" => "אָדָ֥ם", "lex" => ">DM/", "lex_utf8" => "אדם" },
                          { "form" => "שֵׁ֖ת", "lex" => "CT/", "lex_utf8" => "שׁת" }
                        ] })
      rebuild!

      assert_equal 2, lemmas.count
      row = lemmas.where(lemma_raw: "אדם").first
      refute_nil row, "the consonantal lexeme (lex_utf8) is the key, not the ETCBC transliteration"
      assert_equal "אדם", row.fetch(:lemma_folded)
      assert_equal "אָדָ֥ם", row.fetch(:surface_forms)
      assert_equal "gold", row.fetch(:tier)
      assert_equal "שת", lemmas.where(lemma_raw: "שׁת").get(:lemma_folded), "the shin dot folds away"
    end

    def test_dss_lexemes_strip_homograph_suffixes_and_reject_placeholders
      doc = make_document(urn: "urn:d:dss", source: make_slug_source("dss"))
      make_passage(doc, urn: "urn:d:dss:1", text_normalized: "x", sequence: 0, language: "hbo",
                        annotations: { "tokens" => [
                          { "form" => "את", "lex" => "אֵת_1", "lex_utf8_etcbc" => "אֵת" },
                          { "form" => "ול", "lex" => " # ל # " },
                          { "full" => "ε", "lex" => " # " },
                          { "form" => "ו", "lex_utf8_etcbc" => "וְ" }
                        ] })
      rebuild!

      assert_equal %w[את ו], lemmas.order(:lemma_folded).select_map(:lemma_folded),
                   "Abegg's lex (homograph suffix stripped) and the crosswalk fold together; " \
                   "'#'-placeholder lexemes mint nothing"
      assert_equal "אֵת", lemmas.where(lemma_folded: "את").get(:lemma_raw)
    end

    def test_registered_sources_never_read_the_default_lemma_key
      doc = make_document(urn: "urn:d:bhsa", source: make_slug_source("bhsa"))
      make_passage(doc, urn: "urn:d:bhsa:1", text_normalized: "x", sequence: 0, language: "hbo",
                        annotations: { "tokens" => [{ "form" => "x", "lemma" => "stray" }] })
      rebuild!

      assert_equal 0, lemmas.count
    end

    def test_lemma_key_registry_rows_survive_the_incremental_slice
      doc = make_document(urn: "urn:d:bhsa", source: make_slug_source("bhsa"))
      make_passage(doc, urn: "urn:d:bhsa:1", text_normalized: "x", sequence: 0, language: "hbo",
                        annotations: { "tokens" => [{ "form" => "אָדָ֥ם", "lex_utf8" => "אדם" }] })
      rebuild!
      Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "bhsa")

      assert_equal ["אדם"], lemmas.select_map(:lemma_folded)
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

      assert_equal "gold", lemmas_of("urn:d:gold:1").get(:tier),
                   "a source ABSENT from the map stays gold"
      assert_equal "silver", lemmas_of("urn:d:silver:1").get(:tier),
                   "the declared silver source's rows carry the tier"
    end

    # -- the equivalence tier (P34-3) ----------------------------------------
    # A source declared `lemma_tier: equivalence` (CEIPoM) has NO citation-form
    # "lemma" key — its tokens carry scholar-curated Classical-Latin
    # equivalents under "latin_equivalent". Those values mint lemma rows as
    # LATIN keys (folded AND labeled lat) on the non-Latin passages, under the
    # distinct "equivalence" tier: never gold (not attestation), never silver
    # (not automatic).

    def make_equivalence_source(slug: "cle")
      Nabu::Store::Source.create(
        slug: slug, name: "CLE", adapter_class: "TestAdapter", license_class: "attribution"
      )
    end

    # The CEIPoM token shape: opaque lemma_id, no "lemma" key, CLE riding
    # under "latin_equivalent" (absent when upstream held the "-" null).
    def cle_annotations(*pairs)
      { "tokens" => pairs.map do |cle, form|
        { "lemma_id" => "12970a", "latin_equivalent" => cle, "form" => form }.compact
      end }
    end

    def equivalence_rebuild!(slug: "cle")
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    lemma_tiers: { slug => "equivalence" })
    end

    def test_equivalence_source_mints_latin_keys_under_the_equivalence_tier
      doc = make_document(urn: "urn:d:ig", source: make_equivalence_source)
      make_passage(doc, urn: "urn:d:ig:1", text_normalized: "aves anzeriates", sequence: 0,
                        language: "xum", annotations: cle_annotations(%w[avis aves]))
      equivalence_rebuild!

      row = lemmas.first
      refute_nil row, "the CLE value must mint a lemma-index row"
      assert_equal "equivalence", row.fetch(:tier)
      assert_equal "lat", row.fetch(:language),
                   "the key is a Latin dictionary form — folded and labeled lat, " \
                   "not the passage's language"
      assert_equal "auis", row.fetch(:lemma_folded), "CLE folds by the LAT rule (v→u)"
      assert_equal "avis", row.fetch(:lemma_raw), "the raw key keeps the scholar's spelling"
      assert_equal "aves", row.fetch(:surface_forms),
                   "the non-Latin surface forms ride along — what makes the hit readable"
    end

    def test_equivalence_tokens_without_the_cle_key_mint_no_rows
      doc = make_document(urn: "urn:d:1", source: make_equivalence_source)
      # The lean "-"-skipping adapter omits the key entirely on null CLE.
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "x", sequence: 0, language: "osc",
                        annotations: { "tokens" => [{ "lemma_id" => "9a", "form" => "x" }] })
      equivalence_rebuild!

      assert_equal 0, lemmas.count, "no CLE, no row — honest absence"
    end

    def test_equivalence_source_never_minted_from_a_lemma_key
      # The tier declaration says the source's OWN lemma layer is not a
      # citation form (CEIPoM: opaque IDs) — an equivalence source reads
      # latin_equivalent ONLY, so a stray "lemma" key cannot leak in as a
      # gold-shaped row under the equivalence label.
      doc = make_document(urn: "urn:d:1", source: make_equivalence_source)
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "x", sequence: 0, language: "osc",
                        annotations: { "tokens" => [{ "lemma" => "12970a", "form" => "x" }] })
      equivalence_rebuild!

      assert_equal 0, lemmas.count
    end

    def test_equivalence_rows_group_per_folded_key_with_gold_sources_unaffected
      gold_doc = make_document(urn: "urn:d:gold")
      make_passage(gold_doc, urn: "urn:d:gold:1", text_normalized: "x", sequence: 0,
                             annotations: token_annotations(%w[λέγω λέγει]))
      cle_doc = make_document(urn: "urn:d:cle", source: make_equivalence_source)
      make_passage(cle_doc, urn: "urn:d:cle:1", text_normalized: "y", sequence: 0,
                            language: "xum",
                            annotations: cle_annotations(%w[avis aves], %w[avis avif],
                                                         %w[observo anzeriates]))
      equivalence_rebuild!

      assert_equal "gold", lemmas_of("urn:d:gold:1").get(:tier),
                   "a source absent from the map stays gold, untouched"
      avis = lemmas_of("urn:d:cle:1").where(lemma_folded: "auis").all
      assert_equal 1, avis.size, "one row per (passage, folded key), not per token"
      assert_equal "aves, avif", avis.first.fetch(:surface_forms),
                   "distinct surface forms aggregate on the one row"
      assert_equal %w[equivalence equivalence],
                   lemmas_of("urn:d:cle:1").select_map(:tier),
                   "every CLE row carries the equivalence tier"
    end

    def test_equivalence_rebuild_is_idempotent
      doc = make_document(urn: "urn:d:1", source: make_equivalence_source)
      make_passage(doc, urn: "urn:d:1:1", text_normalized: "x", sequence: 0, language: "xum",
                        annotations: cle_annotations(%w[avis aves]))

      equivalence_rebuild!
      equivalence_rebuild!

      assert_equal 1, lemmas.count, "drop+recreate leaves no duplicate equivalence rows"
    end

    # The rebuild invariant (P34-3): an incremental refresh of the equivalence
    # source leaves the lemma table row-identical to a from-scratch rebuild —
    # equivalence rows are derived data, re-derived at every rebuild.
    def test_equivalence_refresh_is_row_identical_to_a_full_rebuild
      source = make_equivalence_source
      doc = make_document(urn: "urn:d:cle", source: source)
      make_passage(doc, urn: "urn:d:cle:1", text_normalized: "x", sequence: 0, language: "xum",
                        annotations: cle_annotations(%w[avis aves]))
      options = { lemma_tiers: { "cle" => "equivalence" } }
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, **options)

      make_passage(doc, urn: "urn:d:cle:2", text_normalized: "y", sequence: 1, language: "xum",
                        annotations: cle_annotations(%w[porta persondro]))
      Nabu::Store::Passage.first(urn: "urn:d:cle:1").update(
        annotations_json: JSON.generate(cle_annotations(%w[observo anzeriates]))
      )
      Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext,
                                           slug: "cle", **options)

      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh, **options)
        assert_equal table_rows(fresh, :passage_lemmas), table_rows(@fulltext, :passage_lemmas),
                     "refreshed equivalence rows must equal a from-scratch rebuild"
      ensure
        fresh.disconnect
      end
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

    # -- the CJK bigram lane (P93-3) --------------------------------
    # A CONTENTLESS second lane over the cjk-flagged sources: each Han/kana
    # run indexed as overlapping character pairs (+ trailing unigram), so
    # mid-run substrings match as bigram phrases. Same scope-table honesty
    # as the trigram lane; rowid = passages.id like the main index.

    def cjk = @fulltext[Nabu::Store::Indexer::CJK_TABLE]

    def cjk_scope = @fulltext[Nabu::Store::Indexer::CJK_SCOPE_TABLE]

    def cjk_match_urns(query)
      urns_of(cjk.where(Sequel.lit("passages_cjk MATCH ?", query))
                 .select_map(Sequel.lit("rowid")))
    end

    def cjk_rebuild!(slugs: ["s"], **)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, cjk_slugs: slugs, **)
    end

    def test_cjk_lane_scoped_to_the_flagged_sources_and_contentless
      doc = make_document(urn: "urn:d:s")
      passage = make_passage(doc, urn: "urn:d:s:1", text_normalized: "時乘六龍以御天", sequence: 0,
                                  language: "lzh")
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "六龍飛天", sequence: 0, language: "lzh")
      cjk_rebuild!

      assert_equal [passage.id], cjk.select_map(Sequel.lit("rowid")),
                   "only the flagged source's rows land, rowid = passages.id"
      refute_includes cjk.columns, :urn, "contentless — no payload columns"
      assert_nil cjk.first.fetch(:cjk), "contentless — the token stream is never stored"
      assert_equal %w[s], cjk_scope.select_map(:slug), "the scope table records what was indexed"
    end

    def test_cjk_tables_exist_empty_without_flagged_slugs
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "六龍", sequence: 0, language: "lzh")
      rebuild!

      assert_equal 0, cjk.count, "no scope, no rows — the table still exists (queries degrade)"
      assert_equal 0, cjk_scope.count
    end

    def test_cjk_lane_matches_a_mid_run_substring
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "時乘六龍以御天", sequence: 0,
                        language: "lzh")
      cjk_rebuild!

      assert_equal %w[urn:d:s:1], cjk_match_urns('"六龍"'),
                   "the mid-run case: the pair sits mid-run and must match"
      assert_equal %w[urn:d:s:1], cjk_match_urns('"六龍 龍以"'),
                   "longer substrings are phrases of consecutive bigrams"
      assert_equal %w[urn:d:s:1], cjk_match_urns('"御" *'),
                   "a single char reaches every position via prefix"
    end

    def test_cjk_bigram_phrases_never_bridge_separate_runs
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "六龍, 飛天", sequence: 0, language: "lzh")
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "六龍飛天", sequence: 1, language: "lzh")
      cjk_rebuild!

      assert_equal %w[urn:d:s:2], cjk_match_urns('"龍飛"'),
                   "a pair spanning a run break exists only where the run is unbroken"
    end

    def test_cjk_lane_skips_runless_and_withdrawn_passages
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "arma virumque", sequence: 0,
                        language: "lat")
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "六龍", sequence: 1, language: "lzh",
                        withdrawn: true)
      make_passage(doc, urn: "urn:d:s:3", text_normalized: "飛天", sequence: 2, language: "lzh")
      cjk_rebuild!

      assert_equal [passage_id("urn:d:s:3")], cjk.select_map(Sequel.lit("rowid")),
                   "runless passages contribute no row; withdrawn are excluded"
    end

    def test_cjk_lane_carries_the_language_and_source_sentinels
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "六龍", sequence: 0, language: "lzh")
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "六龍", sequence: 1, language: "jpn")
      cjk_rebuild!

      assert_equal %w[urn:d:s:2], cjk_match_urns(%{"六龍" AND language : ("0langjpn")}),
                   "--lang composes inside the lane's MATCH, exactly like the main index"
      assert_equal %w[urn:d:s:1 urn:d:s:2], cjk_match_urns(%{"六龍" AND source : ("0srcs")})
    end

    # 2026-11-11 maintenance ruling: the lane is REBUILD-CADENCE — rebuilds
    # are its ONLY writer. A source refresh leaves it exactly as the last
    # rebuild built it (the in-place slice rewrites it used to run —
    # 2 × 3.77M statements on ndl-kotenseki — were where the multi-hour
    # engine grinds lived), so between rebuilds it serves at most one
    # rebuild-cadence stale.
    def test_cjk_refresh_never_touches_the_lane
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "六龍", sequence: 0, language: "lzh")
      cjk_rebuild!

      make_passage(doc, urn: "urn:d:s:2", text_normalized: "飛天", sequence: 1, language: "lzh")
      refresh!
      assert_equal [passage_id("urn:d:s:1")], cjk.select_map(Sequel.lit("rowid")),
                   "the refresh leaves the lane as the last rebuild built it"
      assert_equal %w[s], cjk_scope.select_map(:slug), "…scope row included"
    end

    def test_cjk_lane_refresh_rebuilds_on_scope_drift_or_flagged_replays
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "六龍", sequence: 0, language: "lzh")
      rebuild! # no cjk slugs — empty lane, empty scope

      # Newly flagged since the last build: the scope drifted — rebuild.
      count = Nabu::Store::Indexer.refresh_cjk_lane!(catalog: @catalog, fulltext: @fulltext,
                                                     cjk_slugs: ["s"], replayed_slugs: [])
      assert_equal 1, count
      assert_equal [passage_id("urn:d:s:1")], cjk.select_map(Sequel.lit("rowid"))
      assert_equal %w[s], cjk_scope.select_map(:slug)

      # No flagged replay, no drift: the lane is left alone (stale rows prove it).
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "飛天", sequence: 1, language: "lzh")
      assert_nil Nabu::Store::Indexer.refresh_cjk_lane!(catalog: @catalog, fulltext: @fulltext,
                                                        cjk_slugs: ["s"], replayed_slugs: ["other"])
      assert_equal 1, cjk.count

      # A flagged source replayed: the rebuild catches the lane up.
      assert_equal 2, Nabu::Store::Indexer.refresh_cjk_lane!(catalog: @catalog, fulltext: @fulltext,
                                                             cjk_slugs: ["s"], replayed_slugs: ["s"])
      assert_equal 2, cjk.count

      # De-flagging lands at the rebuild too: the lane rebuilds to empty.
      assert_equal 0, Nabu::Store::Indexer.refresh_cjk_lane!(catalog: @catalog, fulltext: @fulltext,
                                                             cjk_slugs: [], replayed_slugs: [])
      assert_equal 0, cjk.count
      assert_equal 0, cjk_scope.count
    end

    def test_cjk_lane_is_idempotent_and_regenerates_into_a_fresh_db
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "六龍", sequence: 0, language: "lzh")
      2.times { cjk_rebuild! }
      assert_equal 1, cjk.count
      assert_equal 1, cjk_scope.count

      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh, cjk_slugs: ["s"])
        assert_equal [passage_id("urn:d:s:1")],
                     fresh[Nabu::Store::Indexer::CJK_TABLE].select_map(Sequel.lit("rowid"))
      ensure
        fresh.disconnect
      end
    end

    # The 2026-11-11 stalls ran the lane's writes for hours with ZERO
    # output. All lane writing now happens at the rebuild, which announces
    # its stage and ticks per full batch (insert_cjk_batches below).
    CjkSpy = Struct.new(:stages, :ticks) do
      def stage(label, **) = (self.stages ||= []) << label
      def load_tick(count, _errored) = (self.ticks ||= []) << count
    end

    def test_the_cjk_lane_rebuild_announces_itself
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "六龍", sequence: 0, language: "lzh")
      rebuild! # no cjk slugs — the lane refresh below rebuilds on scope drift
      spy = CjkSpy.new

      Nabu::Store::Indexer.refresh_cjk_lane!(catalog: @catalog, fulltext: @fulltext,
                                             cjk_slugs: ["s"], replayed_slugs: [], progress: spy)

      assert(spy.stages.any? { |label| label.include?("cjk bigram lane") },
             "the lane rebuild announces its stage (got: #{spy.stages.inspect})")
    end

    def test_cjk_insert_batches_tick_per_full_batch
      doc = make_document(urn: "urn:d:s")
      3.times do |i|
        make_passage(doc, urn: "urn:d:s:#{i + 1}", text_normalized: "六龍#{i}", sequence: i, language: "lzh")
      end
      rebuild!
      spy = CjkSpy.new
      rows = Nabu::Store::Indexer.send(:cjk_passages, @catalog, ["s"])
      Nabu::Store::Indexer.send(:insert_cjk_batches, @fulltext, rows, progress: spy, batch_size: 2)

      assert_equal [2], spy.ticks, "one tick per FULL batch; the partial final batch stays silent"
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

      assert_equal %w[urn:d:lit:1 urn:d:s:1 urn:d:s:2], fts_urns,
                   "the refreshed source gains its new row; the other source's slice is untouched"
    end

    # The FTS-deletion mechanism proof (search before/after): the contentless
    # shape deletes by rowid (= passage id) under contentless_delete=1 — a
    # removed row must stop matching, and other sources' rows must not.
    def test_refresh_removes_withdrawn_passages_from_the_index
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "μηνιν αειδε", sequence: 0)
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "μηνιν ουλομενην", sequence: 0)
      rebuild!
      assert_equal 2, match("μηνιν").size, "both searchable before the withdrawal"

      Nabu::Store::Passage.first(urn: "urn:d:s:1").update(withdrawn: true)
      refresh!

      assert_equal %w[urn:d:lit:1], match_urns("μηνιν"),
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
        # passages_fts is contentless — column values are unreadable, so its
        # identity comparison is the rowid set (= the indexed passage ids)
        # plus a MATCH probe against the revised text.
        assert_equal fts_rowids(fresh), fts_rowids(@fulltext),
                     "passages_fts must hold the identical rowid set"
        %i[passage_lemmas passages_trigram passages_trigram_scope
           reflex_roots reflex_root_stats].each do |table|
          assert_equal table_rows(fresh, table), table_rows(@fulltext, table),
                       "#{table} must be row-identical to a from-scratch rebuild"
        end
        assert_equal %w[urn:d:s:2], match_urns("revised"),
                     "the refreshed slice answers MATCH with the revised tokens"
      ensure
        fresh.disconnect
      end
    end

    def table_rows(db, table)
      db[table].all.map { |row| row.sort_by { |key, _| key } }.sort_by(&:inspect)
    end

    def fts_rowids(db) = db[:passages_fts].select_map(Sequel.lit("rowid")).sort

    # -- the bulk slice mode (P111-1) ----------------------------------
    # A content-bearing re-parse of a big source rewrites millions of fts
    # rows; under the default merge config the automerge/deletemerge
    # machinery fires DURING the delete storm and the batched inserts (the
    # kanripo 6h18m shape). The governed recipe defers the delete-triggered
    # merges (deletemerge 0 — BULK_MERGE_SETTINGS; automerge/crisismerge
    # stay untouched, the 2026-10-01 wedge lesson), ensure-restores the
    # defaults, then consolidates in an announced bounded merge loop.
    # The contract stays ROW IDENTITY.

    BulkSpy = Struct.new(:stages) do
      def stage(label, **) = (self.stages ||= []) << label
      def load_tick(*); end
    end

    def merge_config(db, key) = db[:passages_fts_config].where(k: key).get(:v)

    def test_bulk_refresh_is_row_identical_to_a_full_rebuild
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "λεγει", sequence: 0,
                        annotations: token_annotations(%w[λέγω λέγει]))
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "outdated", sequence: 1)
      make_passage(doc, urn: "urn:d:s:3", text_normalized: "王道", sequence: 2, language: "lzh")
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "στρατηγοσ", sequence: 0)
      options = { cjk_slugs: ["s"] }
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, **options)

      make_passage(doc, urn: "urn:d:s:4", text_normalized: "fresh", sequence: 3)
      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(text_normalized: "revised")
      Nabu::Store::Passage.first(urn: "urn:d:s:1").update(withdrawn: true)
      refresh!(bulk_threshold: 1, **options)

      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh, **options)
        assert_equal fts_rowids(fresh), fts_rowids(@fulltext),
                     "passages_fts must hold the identical rowid set through the bulk path"
        assert_equal cjk_rowids(fresh), cjk_rowids(@fulltext),
                     "the cjk lane must hold the identical rowid set through the bulk path"
        assert_equal %w[urn:d:s:2], match_urns("revised"),
                     "the bulk-refreshed slice answers MATCH after the merge loop"
      ensure
        fresh.disconnect
      end
    end

    def cjk_rowids(db) = db[Nabu::Store::Indexer::CJK_TABLE].select_map(Sequel.lit("rowid")).sort

    # The 2026-10-01 wedge pin: fts5 caps TOTAL segments at 2000
    # (fts5AllocateSegid → SQLITE_FULL, reading as "disk full"), and
    # crisismerge is clamped to 1999 per-level — so disabling automerge
    # lets a big insert flood hit the cap and WEDGE the index (even merge
    # commands need a segment allocation). Bulk mode must only ever touch
    # deletemerge; the insert-side merge machinery stays on.
    def test_bulk_mode_never_touches_automerge_or_crisismerge
      assert_equal %w[deletemerge], Nabu::Store::Indexer::BULK_MERGE_SETTINGS.keys,
                   "automerge/crisismerge must stay at their defaults during bulk writes"
      assert_equal %w[deletemerge], Nabu::Store::Indexer::DEFAULT_MERGE_SETTINGS.keys
    end

    def test_bulk_refresh_restores_the_merge_config
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!

      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      refresh!(bulk_threshold: 1)

      Nabu::Store::Indexer::DEFAULT_MERGE_SETTINGS.each do |key, value|
        stored = merge_config(@fulltext, key)
        assert(stored.nil? || stored.to_i == value,
               "#{key} must read back at its default after a bulk refresh (got #{stored.inspect})")
      end
    end

    def test_bulk_write_mode_restores_config_when_the_block_raises
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!

      assert_raises(RuntimeError) do
        Nabu::Store::Indexer.with_bulk_write_mode(@fulltext, [:passages_fts]) { raise "boom" }
      end
      Nabu::Store::Indexer::DEFAULT_MERGE_SETTINGS.each do |key, value|
        stored = merge_config(@fulltext, key)
        assert(stored.nil? || stored.to_i == value,
               "#{key} must be restored even when the bulk block raises (got #{stored.inspect})")
      end
    end

    def test_bulk_refresh_announces_and_small_slices_stay_quiet
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!

      spy = BulkSpy.new([])
      refresh!(bulk_threshold: 1, progress: spy)
      assert(spy.stages.any? { |label| label.include?("bulk mode") },
             "an at-threshold slice announces bulk mode")
      assert(spy.stages.any? { |label| label.include?("merge") },
             "the consolidation merge stage announces itself")

      spy = BulkSpy.new([])
      refresh!(progress: spy)
      refute(spy.stages.any? { |label| label.include?("bulk mode") },
             "a below-threshold slice must keep the ordinary path")
    end

    # -- the slice-pending marker + crash semantics (P111-1b) ----------------
    # The live SQLITE_FULL crash (2026-10-01): a monolithic 8.9M-row slice
    # transaction retained every written page version in the WAL and filled
    # ~500 GB of free disk at 11% of the insert pass. Bulk mode therefore
    # runs WITHOUT the wrapping transaction (short autocommitted batches,
    # WAL checkpointed) — a mid-run failure leaves a PARTIAL slice — and the
    # fulltext file itself records the unfinished slice so the next refresh
    # heals it instead of being skipped over it.

    def slice_rows = @fulltext[Nabu::Store::Indexer::SLICE_REFRESHES_TABLE]

    def test_refresh_marks_its_slice_finished
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      refresh!

      refute_nil slice_rows.first(slug: "s")[:finished_at]
      refute Nabu::Store::Indexer.slice_pending?(@fulltext, "s")
    end

    def test_a_crashed_slice_stays_pending_and_heals_on_the_next_refresh
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      rebuild!
      refresh!

      # Simulate the crash: the marker never finished and the slice is half
      # written (one of the source's rows missing). A real crash removes the
      # row's sidecar sha FIRST (the fts_row_shas invariant), so the
      # simulation drops both.
      slice_rows.where(slug: "s").update(finished_at: nil)
      doomed = @catalog[:passages].where(urn: "urn:d:s:2").get(:id)
      @fulltext[:passages_fts].where(rowid: doomed).delete
      @fulltext[Nabu::Store::Indexer::ROW_SHAS_TABLE].where(rowid: doomed).delete

      assert Nabu::Store::Indexer.slice_pending?(@fulltext, "s")
      refresh!

      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh)
        assert_equal fts_rowids(fresh), fts_rowids(@fulltext),
                     "the heal re-refresh restores row identity"
      ensure
        fresh.disconnect
      end
      refute Nabu::Store::Indexer.slice_pending?(@fulltext, "s")
    end

    # P112-3: a finished slice stamps the catalog state it serves.
    def test_refresh_stamps_the_catalog_state_it_serves
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      rebuild!
      refresh!

      stamp = Nabu::Store::Indexer.slice_stamps(@fulltext).fetch("s")

      assert_equal 2, stamp[:live_rows]
      assert_equal @catalog[:passages].max(:id), stamp[:max_passage_id]
    end

    # A P111-era slice_refreshes table (no stamp columns) upgrades in place
    # at the next refresh instead of crashing on the unknown columns.
    def test_refresh_upgrades_a_p111_era_marker_table
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      @fulltext.create_table(Nabu::Store::Indexer::SLICE_REFRESHES_TABLE) do
        String :slug, primary_key: true
        String :started_at, null: false
        String :finished_at
      end

      refresh!

      stamp = Nabu::Store::Indexer.slice_stamps(@fulltext).fetch("s")

      assert_equal 1, stamp[:live_rows], "the upgraded table carries the fresh stamp"
    end

    def test_rebuild_clears_pending_markers
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      refresh!
      slice_rows.where(slug: "s").update(finished_at: nil)

      rebuild!

      refute Nabu::Store::Indexer.slice_pending?(@fulltext, "s"),
             "a full rebuild leaves nothing pending"
    end

    # The forbidding_index_work pattern: swap one Indexer entry point for a
    # raiser, restore after — write_char_postings runs AFTER the fts inserts
    # inside the stage body, so it simulates a mid-slice crash.
    # +name+: the in-slice writer to fail — the delta grain moves the
    # postings by arithmetic, so a delta crash rides its coverage write.
    def raising_char_postings(name = :write_char_postings)
      mod = Nabu::Store::Indexer
      original = mod.method(name)
      mod.define_singleton_method(name) { |*, **| raise "boom" }
      yield
    ensure
      mod.define_singleton_method(name, original)
    end

    def test_bulk_slice_failure_persists_partial_state_and_stays_pending
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "fresh", sequence: 1)

      raising_char_postings do
        assert_raises(RuntimeError) { refresh!(bulk_threshold: 1) }
      end

      assert Nabu::Store::Indexer.slice_pending?(@fulltext, "s"),
             "the crashed bulk slice reads pending"
      assert_equal 2, fts.count,
                   "bulk mode holds no wrapping txn — the inserts before the crash persist"
      Nabu::Store::Indexer::DEFAULT_MERGE_SETTINGS.each do |key, value|
        stored = merge_config(@fulltext, key)
        assert(stored.nil? || stored.to_i == value,
               "#{key} must be restored even through the crash")
      end

      refresh!(bulk_threshold: 1)
      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh)
        assert_equal fts_rowids(fresh), fts_rowids(@fulltext), "the re-refresh heals"
      ensure
        fresh.disconnect
      end
    end

    def test_ordinary_slice_failure_rolls_back_atomically
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "fresh", sequence: 1)

      raising_char_postings do
        assert_raises(RuntimeError) { refresh! }
      end

      assert_equal 1, fts.count,
                   "the ordinary slice keeps its single-transaction atomic-swap contract"
      assert Nabu::Store::Indexer.slice_pending?(@fulltext, "s"),
             "even a rolled-back failure reads pending — the slice never refreshed"
    end

    def test_bulk_refresh_truncates_the_wal
      Dir.mktmpdir do |dir|
        path = File.join(dir, "ft.sqlite3")
        disk = Nabu::Store.connect_fulltext(path)
        begin
          doc = make_document(urn: "urn:d:s")
          make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
          Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: disk)
          make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
          Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: disk, slug: "s",
                                               bulk_threshold: 1)
          wal = "#{path}-wal"
          assert(!File.exist?(wal) || File.empty?(wal),
                 "bulk mode checkpoints (TRUNCATE) — the WAL never accumulates the slice")
        ensure
          disk.disconnect
        end
      end
    end

    # checkpoint_wal! returns the engine's answer row instead of discarding
    # it: TRUNCATE degrades silently against a pinned reader.
    def test_checkpoint_returns_the_engine_result_row
      Dir.mktmpdir do |dir|
        disk = Nabu::Store.connect_fulltext(File.join(dir, "ft.sqlite3"))
        begin
          disk.create_table(:t) { Integer :x }
          disk[:t].insert(x: 1)
          result = Nabu::Store::Indexer.checkpoint_wal!(disk)

          assert_equal %i[busy log checkpointed], result.keys
          assert_equal 0, result[:busy], "an unpinned TRUNCATE checkpoint completes"
          assert_equal result[:log], result[:checkpointed], "every frame was checkpointed"
        ensure
          disk.disconnect
        end
      end
    end

    def test_checkpoint_announces_when_a_reader_pins_the_wal
      Dir.mktmpdir do |dir|
        path = File.join(dir, "ft.sqlite3")
        disk = Nabu::Store.connect_fulltext(path)
        reader = Sequel.connect("sqlite://#{path}")
        begin
          disk.create_table(:t) { Integer :x }
          disk[:t].insert(x: 1)
          disk.run("PRAGMA busy_timeout = 0") # never wait on the pinned reader
          reader.synchronize do |conn|
            conn.execute("BEGIN")
            conn.execute("SELECT count(*) FROM t") # opens the read snapshot
            disk[:t].insert(x: 2) # frames past the reader's mark
            spy = BulkSpy.new([])
            result = Nabu::Store::Indexer.checkpoint_wal!(disk, progress: spy)
            conn.execute("COMMIT")

            assert_equal 1, result[:busy], "TRUNCATE cannot finish under a pinned reader"
            assert(spy.stages.any? { |label| label.include?("wal checkpoint refused (reader pinning)") },
                   "the refusal is announced, never silent (got #{spy.stages.inspect})")
          end
        ensure
          reader.disconnect
          disk.disconnect
        end
      end
    end

    # A LEGACY contentful passages_fts keeps the ordinary path even past the
    # threshold — the bulk recipe is designed against the contentless shape,
    # and legacy files upgrade at their next full rebuild anyway.
    def test_bulk_mode_never_engages_on_a_legacy_contentful_table
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      @fulltext.drop_table(:passages_fts)
      @fulltext.run(<<~SQL)
        CREATE VIRTUAL TABLE passages_fts USING fts5(
          text_normalized, language, source, urn UNINDEXED, passage_id UNINDEXED,
          tokenize = 'unicode61 remove_diacritics 2'
        )
      SQL

      spy = BulkSpy.new([])
      refresh!(bulk_threshold: 1, progress: spy)
      refute(spy.stages.any? { |label| label.include?("bulk mode") },
             "a legacy contentful table must not take the bulk recipe")
    end

    # -- universal deferred deletemerge (the ndl-kotenseki incident) ---------
    # A 17,505-row delta against a 57 GB index hung 5h+ inside
    # fts5IndexMerge → fts5DataDelete: the bulk gate measured the DELTA,
    # while the hazard is the INDEX's accumulated tombstone debt — a small
    # delta ran with deletemerge=10 live and paid the debt's segment merges
    # inside one atomic transaction. The deferral (+ consolidation) is now
    # universal for the contentless shape; the threshold decides only the
    # transaction shape.

    # Swap one Indexer entry point for a recording wrapper, restore after.
    def observing(name)
      mod = Nabu::Store::Indexer
      original = mod.method(name)
      calls = []
      mod.define_singleton_method(name) do |*args, **kwargs, &blk|
        calls << original.call(*args, **kwargs, &blk)
        calls.last
      end
      yield calls
    ensure
      mod.define_singleton_method(name, original)
    end

    def assert_default_deletemerge(message)
      stored = merge_config(@fulltext, "deletemerge")
      assert(stored.nil? || stored.to_i == Nabu::Store::Indexer::DEFAULT_MERGE_SETTINGS["deletemerge"],
             "#{message} (got #{stored.inspect})")
    end

    def test_delta_grain_refresh_defers_deletemerge_during_the_write
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)

      seen = nil
      mod = Nabu::Store::Indexer
      original = mod.method(:insert_passage_batches)
      mod.define_singleton_method(:insert_passage_batches) do |fulltext, *rest, **kwargs|
        seen = fulltext[:passages_fts_config].where(k: "deletemerge").get(:v)
        original.call(fulltext, *rest, **kwargs)
      end
      begin
        refresh!(delta: delta_of(upserted: %w[urn:d:s:2]))
      ensure
        mod.define_singleton_method(:insert_passage_batches, original)
      end

      refute_nil seen, "the deferral is written as explicit index config during the write"
      assert_equal Nabu::Store::Indexer::BULK_MERGE_SETTINGS["deletemerge"], seen.to_i,
                   "a small delta writes with deletemerge deferred — the debt is the index's, not the delta's"
      assert_default_deletemerge("the default is restored once the write completes")
      assert_equal %w[urn:d:s:2], match_urns("beta")
    end

    # The universal recipe's cost claim: on a debt-free index the
    # consolidation probe exits after ONE no-op merge chunk per governed
    # table (the command row is the only change total_changes sees).
    def test_consolidation_runs_after_a_small_delta_and_is_a_no_op_on_a_clean_index
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)

      spy = BulkSpy.new([])
      observing(:consolidate_merges!) do |chunks|
        refresh!(delta: delta_of(upserted: %w[urn:d:s:2]), progress: spy)
        governed = Nabu::Store::Indexer.governed_fts_tables(@fulltext)
        assert_equal [Nabu::Store::Indexer::TABLE, Nabu::Store::Indexer::CJK_TABLE], governed
        assert_equal [1] * governed.size, chunks,
                     "one no-op chunk per governed table — the clean-index probe exits at once"
      end
      assert(spy.stages.any? { |label| label.include?("merge consolidation") },
             "the consolidation stage runs (announced) after every slice write")
      refute(spy.stages.any? { |label| label.include?("bulk mode") },
             "a small delta keeps the ordinary (atomic) transaction shape")
    end

    # The maintenance rail owns merge consolidation: the sync path runs ONE
    # bounded probe chunk per governed table, and debt beyond it is
    # REPORTED ("run nabu index maintain"), never paid inline.
    NoteSpy = Struct.new(:stages, :notes) do
      def stage(label, **) = (self.stages ||= []) << label
      def note(line) = (self.notes ||= []) << line
      def load_tick(*); end
    end

    def test_the_sync_path_reports_merge_debt_past_its_one_probe_chunk
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      # Planted debt: automerge off, one level-0 segment per committed insert.
      Nabu::Store::Indexer.apply_merge_settings(@fulltext, :passages_fts, { "automerge" => 0 })
      12.times do |i|
        fts.insert(rowid: 9_000 + i, text_normalized: "debt", language: Nabu::Store::Indexer.language_token("grc"),
                   source: Nabu::Store::Indexer.source_token("s"))
      end
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      spy = NoteSpy.new([], [])
      chunks = 0
      mod = Nabu::Store::Indexer
      original = mod.method(:merge_chunk!)
      # A chunk that barely dents a huge debt (the live shape) — at test
      # scale one real chunk would merge everything.
      mod.define_singleton_method(:merge_chunk!) do |*|
        chunks += 1
        1
      end
      begin
        refresh!(delta: delta_of(upserted: %w[urn:d:s:2]), progress: spy)
      ensure
        mod.define_singleton_method(:merge_chunk!, original)
      end

      assert_equal Nabu::Store::Indexer.governed_fts_tables(@fulltext).size, chunks,
                   "the sync path runs exactly one probe chunk per governed table"
      line = spy.notes.find { |note| note.include?("passages_fts") }
      assert_match(/merge debt.*run nabu index maintain/, line.to_s, "the debt is reported (#{spy.notes.inspect})")
    end

    def test_a_clean_index_reports_no_merge_debt
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      spy = NoteSpy.new([], [])
      refresh!(delta: delta_of(upserted: %w[urn:d:s:2]), progress: spy)

      assert_empty spy.notes.grep(/merge debt/)
    end

    def test_a_small_write_stays_atomic_under_deferred_merges
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "fresh", sequence: 1)

      raising_char_postings(:write_passage_chars) do
        assert_raises(RuntimeError) { refresh!(delta: delta_of(upserted: %w[urn:d:s:2])) }
      end

      assert_equal 1, fts.count, "below the threshold the write is one atomic transaction"
      assert_default_deletemerge("the deferral is ensure-restored even when the atomic write rolls back")
    end

    def test_threshold_decides_only_the_transaction_shape
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!

      shapes = []
      mod = Nabu::Store::Indexer
      original = mod.method(:slice_write_unit)
      mod.define_singleton_method(:slice_write_unit) do |fulltext, bulk:, **kwargs, &blk|
        shapes << bulk
        original.call(fulltext, bulk: bulk, **kwargs, &blk)
      end
      begin
        refresh!
        refresh!(bulk_threshold: 1)
      ensure
        mod.define_singleton_method(:slice_write_unit, original)
      end

      assert_equal [false, true], shapes, "below threshold: atomic txn; at/above: autocommit + checkpoint"
    end

    def test_governed_tables_key_only_on_the_contentless_shape
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "王道", sequence: 0, language: "lzh")
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, cjk_slugs: ["s"])

      assert_equal [Nabu::Store::Indexer::TABLE, Nabu::Store::Indexer::CJK_TABLE],
                   Nabu::Store::Indexer.governed_fts_tables(@fulltext)

      @fulltext.drop_table(:passages_fts)
      @fulltext.run(<<~SQL)
        CREATE VIRTUAL TABLE passages_fts USING fts5(
          text_normalized, language, source, urn UNINDEXED, passage_id UNINDEXED,
          tokenize = 'unicode61 remove_diacritics 2'
        )
      SQL
      assert_empty Nabu::Store::Indexer.governed_fts_tables(@fulltext),
                   "a legacy contentful file keeps the old untouched path"
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
      assert_equal %w[urn:d:lit:1 urn:d:s:1], fts_urns,
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

    # The registry fingerprint (alignment_refs = f(catalog, alignments.yml)):
    # a sync whose content is unchanged skips the slice, so the registry
    # edit itself must be what triggers the alignment rebuild.
    def registry_at(dir, yaml)
      path = File.join(dir, "alignments.yml")
      File.write(path, yaml)
      Nabu::AlignmentRegistry.load(path)
    end

    def test_the_registry_fingerprint_is_semantic
      fingerprint = ->(reg) { Nabu::Store::AlignmentIndexer.fingerprint(reg) }
      Dir.mktmpdir do |dir|
        first = fingerprint.call(registry_at(dir, ALIGN_REGISTRY_YAML))
        assert_equal first, fingerprint.call(registry_at(dir, ALIGN_REGISTRY_YAML))
        assert_equal first, fingerprint.call(registry_at(dir, "# a comment\n#{ALIGN_REGISTRY_YAML}")),
                     "a comment-only edit derives nothing new"
        refute_equal first, fingerprint.call(registry_at(dir, ALIGN_REGISTRY_YAML.sub("MARK", "LUKE"))),
                     "a witness edit is a change"
      end
    end

    def test_registry_refresh_is_a_no_op_while_the_registry_is_unchanged
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1.1", text_normalized: "verse", sequence: 0)
      registry = alignment_registry
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, alignments: registry)
      @fulltext[:alignment_refs].insert(work: "nt", ref: "SENTINEL", document_urn: "x",
                                        passage_id: 999, passage_urn: "x", seq: 0)

      assert_nil Nabu::Store::Indexer.refresh_alignment_registry!(
        catalog: @catalog, fulltext: @fulltext, slug: "s", alignments: alignment_registry
      )
      assert_equal 1, @fulltext[:alignment_refs].where(ref: "SENTINEL").count, "the table was left alone"
    end

    def test_a_changed_registry_rebuilds_only_the_alignment_refs_for_a_witness_source
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1.1", text_normalized: "verse", sequence: 0)
      Dir.mktmpdir do |dir|
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                      alignments: registry_at(dir, "{}\n"))
        assert_equal 0, @fulltext[:alignment_refs].count
        fts_before = @fulltext[:passages_fts].count

        wired = registry_at(dir, ALIGN_REGISTRY_YAML)
        assert_equal 1, Nabu::Store::Indexer.refresh_alignment_registry!(
          catalog: @catalog, fulltext: @fulltext, slug: "s", alignments: wired
        )
        assert_equal ["MARK 1.1"], @fulltext[:alignment_refs].select_map(:ref), "the new witness materialized"
        assert_equal fts_before, @fulltext[:passages_fts].count, "the FTS slice was not touched"
        assert_nil Nabu::Store::Indexer.refresh_alignment_registry!(
          catalog: @catalog, fulltext: @fulltext, slug: "s", alignments: wired
        ), "the stamp advanced: the next sync skips again"
      end
    end

    def test_a_changed_registry_clears_a_dropped_witness_on_its_sources_sync
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1.1", text_normalized: "verse", sequence: 0)
      Dir.mktmpdir do |dir|
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                      alignments: registry_at(dir, ALIGN_REGISTRY_YAML))
        assert_equal 1, @fulltext[:alignment_refs].count

        assert_equal 0, Nabu::Store::Indexer.refresh_alignment_registry!(
          catalog: @catalog, fulltext: @fulltext, slug: "s", alignments: registry_at(dir, "{}\n")
        ), "the source no longer witnesses anything, but its stale refs go"
        assert_equal 0, @fulltext[:alignment_refs].count
      end
    end

    def test_a_changed_registry_leaves_a_non_witness_source_alone
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1.1", text_normalized: "verse", sequence: 0)
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "prose", sequence: 0)
      Dir.mktmpdir do |dir|
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                      alignments: registry_at(dir, "{}\n"))

        assert_nil Nabu::Store::Indexer.refresh_alignment_registry!(
          catalog: @catalog, fulltext: @fulltext, slug: "lit", alignments: registry_at(dir, ALIGN_REGISTRY_YAML)
        ), "the witness source's own sync materializes it"
      end
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
    # closure is built from — the caller forces the closure re-walk. The
    # gold stats are a function of the lemma table alone, which no
    # crosswalk edit moves, so they are kept (the delta grain's O(Δ) rule —
    # no corpus-wide lemma scan behind a dictionary sync).
    def test_refresh_rebuilds_the_reflex_closure_when_reflexes_changed
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "plain", sequence: 0)
      rebuild!
      @fulltext[Nabu::Store::ReflexRootsIndexer::TABLE].insert(language: "zz", lemma_folded: "x",
                                                               root_urn: "urn:sentinel")
      reflex_stats.insert(language: "zz-sentinel", gold_passages: 1)

      assert_equal 1, refresh!(reflexes_changed: true)
      assert_empty @fulltext[Nabu::Store::ReflexRootsIndexer::TABLE].where(root_urn: "urn:sentinel"),
                   "reflexes_changed forces the closure re-walk"
      assert_equal 1, reflex_stats.where(language: "zz-sentinel").count,
                   "the gold stats are not re-snapshotted behind a crosswalk change"
    end

    # -- the char-postings index (P65 gate: `nabu char 纹` must be instant) --
    #
    # The Han corpus panel used to LIKE-scan the passages table at desk time
    # — 180 s at the 68M-row census (2026-08-10, the hang the owner caught).
    # -- passage_chars (P72-1, the coverage index) -------------------------
    # Per LIVE Han-bearing passage: its sorted distinct chars, count, and
    # the four RAREST by global docs-rank (r1..r4, each indexed) — the
    # graded-reading lane's candidate columns: a passage with ≤N foreign
    # chars must carry one of its N+1 rarest inside the charset.

    def passage_chars = @fulltext[Nabu::Store::Indexer::PASSAGE_CHARS_TABLE]

    def test_passage_chars_store_sorted_distinct_han_with_rarest_ranking
      doc = make_document(urn: "urn:d:s")
      # 木 appears in 3 passages (commonest), 林 in 2, 森 in 1 (rarest).
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "木木林", sequence: 0, language: "lzh")
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "木林森", sequence: 1, language: "lzh")
      make_passage(doc, urn: "urn:d:s:3", text_normalized: "木 alone", sequence: 2, language: "lzh")
      make_passage(doc, urn: "urn:d:s:4", text_normalized: "no han", sequence: 3, language: "eng")
      rebuild!

      row = passage_chars.first(rowid: passage_id("urn:d:s:2"))
      assert_equal 3, row[:nchars]
      assert_equal %w[木 林 森].sort.join, row[:chars], "distinct chars, sorted, deduped"
      assert_equal "森", row[:r1], "the globally rarest char leads"
      assert_equal "林", row[:r2]
      assert_equal "木", row[:r3]
      assert_nil row[:r4], "fewer chars than slots -> NULL"
      assert_equal "木", passage_chars.first(rowid: passage_id("urn:d:s:1"))[:r2],
                   "duplicates collapse before ranking"
      assert_nil passage_chars.first(rowid: passage_id("urn:d:s:4")),
                 "han-less passages have no row"
    end

    def test_passage_chars_exclude_withdrawn_and_refresh_swaps_one_source
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "棄", sequence: 0, language: "lzh")
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "棄", sequence: 1, language: "lzh",
                        withdrawn: true)
      rebuild!
      assert_equal 1, passage_chars.count

      other = Nabu::Store::Source.create(
        slug: "t2", name: "T2", adapter_class: "TestAdapter", license_class: "open"
      )
      other_doc = make_document(urn: "urn:d:t2", source: other)
      make_passage(other_doc, urn: "urn:d:t2:1", text_normalized: "国", sequence: 0, language: "lzh")
      Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "t2")
      assert_equal 1, passage_chars.where(source_id: other.id).count,
                   "refresh fills the new source's slice"
      assert_equal 1, passage_chars.where(source_id: @source.id).count,
                   "the untouched source's slice survives"
    end

    def passage_id(urn) = @catalog[:passages].where(urn: urn).get(:id)

    # The postings ride the SAME streaming pass as the fts/lemma tables:
    # per (source, char, language), the count of live passages containing
    # each character outside plain ASCII (P86-3 widened the class from
    # Han-only — the universal card's corpus panel for any script). Desk
    # time is one B-tree lookup.

    def test_char_postings_count_non_ascii_chars_per_language_docwise
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "棄而棄之", sequence: 0, language: "lzh")
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "棄の国", sequence: 1, language: "jpn")
      make_passage(doc, urn: "urn:d:s:3", text_normalized: "no han here", sequence: 2, language: "eng")
      make_passage(doc, urn: "urn:d:s:4", text_normalized: "μῆνιν ἄειδε", sequence: 3, language: "grc")
      rebuild!

      assert_equal 1, postings.where(char: "棄", language: "lzh").get(:docs),
                   "a char twice in ONE passage counts one doc"
      assert_equal 1, postings.where(char: "棄", language: "jpn").get(:docs)
      assert_equal 1, postings.where(char: "国").get(:docs)
      assert_empty postings.where(language: "eng").all, "plain-ASCII passages contribute nothing"
      assert_equal 1, postings.where(char: "の").get(:docs),
                   "P86-3 (flipping the P65 Han-only pin): kana posts now"
      assert_equal 1, postings.where(char: "μ", language: "grc").get(:docs),
                   "Greek posts — the widening's point"
    end

    def test_char_postings_carry_the_class_stamp_on_full_builds_only
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "棄", sequence: 0, language: "lzh")
      rebuild!
      stamp = postings.where(source_id: Nabu::Store::Indexer::POSTINGS_CLASS_SOURCE)
      assert_equal 1, stamp.count, "one sentinel row, idempotent across rebuilds"
      assert_equal Nabu::Store::Indexer::POSTINGS_CLASS, stamp.get(:language)
      rebuild!
      assert_equal 1, postings.where(source_id: Nabu::Store::Indexer::POSTINGS_CLASS_SOURCE).count
      assert_empty postings.where(char: "").exclude(
        source_id: Nabu::Store::Indexer::POSTINGS_CLASS_SOURCE
      ).all, "the sentinel never collides with a real posting"
    end

    def test_char_postings_exclude_withdrawn_and_are_idempotent
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "棄", sequence: 0, language: "lzh")
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "棄", sequence: 1, language: "lzh",
                        withdrawn: true)
      rebuild!
      rebuild!
      assert_equal 1, postings.where(char: "棄").get(:docs)
    end

    def test_refresh_swaps_only_that_sources_postings_slice
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "棄", sequence: 0, language: "lzh")
      other = Nabu::Store::Source.create(
        slug: "t", name: "T", adapter_class: "TestAdapter", license_class: "open"
      )
      other_doc = make_document(urn: "urn:d:t", source: other)
      make_passage(other_doc, urn: "urn:d:t:1", text_normalized: "棄国", sequence: 0, language: "lzh")
      rebuild!
      assert_equal 2, postings.where(char: "棄").sum(:docs)

      make_passage(doc, urn: "urn:d:s:2", text_normalized: "纹", sequence: 1, language: "lzh")
      refresh!
      assert_equal 1, postings.where(char: "纹").get(:docs), "the new passage's chars land"
      assert_equal 2, postings.where(char: "棄").sum(:docs)
      assert_equal 1, postings.where(char: "国").get(:docs), "the other source's slice is untouched"
    end

    def test_refresh_builds_the_postings_table_when_a_pre_p65_index_lacks_it
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "棄", sequence: 0, language: "lzh")
      rebuild!
      @fulltext.drop_table(Nabu::Store::Indexer::CHAR_POSTINGS_TABLE)

      refresh!
      assert_equal 1, postings.where(char: "棄").get(:docs),
                   "a pre-P65 fulltext file gains the postings on its next sync"
    end

    # -- the text_search seam (P112-2) ---------------------------------
    # A row whose stored text_normalized is the "" sentinel (identical to
    # text — the loader's slimming) must index under its text: every
    # indexer read goes through the text_search generated column.

    def test_sentinel_normalized_rows_index_under_their_text
      doc = make_document(urn: "urn:d:1")
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "urn:d:1:1", sequence: 0, language: "lzh",
        text: "王道蕩蕩", text_normalized: "", content_sha256: "x", revision: 1,
        withdrawn: false, annotations_json: "{}"
      )

      assert_equal 1, rebuild!
      assert_equal %w[urn:d:1:1], match_urns("王道蕩蕩"),
                   "the sentinel row is searchable by its text"
      assert_equal 3, postings.exclude(char: "").where(source_id: @source.id).count,
                   "char postings read the coalesced form (王/道/蕩 distinct)"
    end

    # -- the delta grain (P112-1) --------------------------------------
    # With the loader's IndexDelta on hand, refresh_source! refreshes exactly
    # the changed rows instead of rewriting the source's whole slice (the
    # measured pathology: an 8.9M-row cbeta rewrite serving a 35-document
    # heal). The contract stays ROW IDENTITY against a from-scratch rebuild;
    # the PROOF of the grain is that untouched rows are never rewritten.

    # A delta whose sets are resolved from catalog urns, exactly as the
    # loader would have minted it.
    def delta_of(upserted: [], removed: [])
      delta = Nabu::Store::IndexDelta.new
      upserted.each { |urn| delta.upsert(passage_id_of(urn), urn) }
      removed.each { |urn| delta.remove(passage_id_of(urn), urn) }
      delta
    end

    def passage_id_of(urn) = @catalog[:passages].where(urn: urn).get(:id)

    def test_delta_refresh_is_row_identical_to_a_full_rebuild
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "λεγει", sequence: 0,
                        annotations: token_annotations(%w[λέγω λέγει]))
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "outdated", sequence: 1)
      make_passage(doc, urn: "urn:d:s:3", text_normalized: "doomed 棄", sequence: 2, language: "lzh")
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "στρατηγοσ 棄", sequence: 0,
                        annotations: token_annotations(%w[στρατηγός στρατηγοσ]))
      options = { fuzzy_slugs: ["s"], cjk_slugs: ["s"], lemma_tiers: { "s" => "silver" } }
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, **options)

      # add + revise (text and lemmas) + withdraw, exactly the slice test's
      # mutation set — applied through a delta this time.
      make_passage(doc, urn: "urn:d:s:4", text_normalized: "fresh 王道", sequence: 3,
                        annotations: token_annotations(%w[φέρω φέρει]))
      # A revision moves the content sha, exactly as the loader mints it.
      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(
        text_normalized: "revised 国", content_sha256: "ab12",
        annotations_json: JSON.generate(token_annotations(%w[ὁράω ὁρᾷ]))
      )
      Nabu::Store::Passage.first(urn: "urn:d:s:3").update(withdrawn: true)
      delta = delta_of(upserted: %w[urn:d:s:4 urn:d:s:2], removed: %w[urn:d:s:3])
      refresh!(delta: delta, **options)

      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh, **options)
        assert_equal fts_rowids(fresh), fts_rowids(@fulltext),
                     "passages_fts must hold the identical rowid set at the delta grain"
        # The cjk lane is REBUILD-CADENCE (2026-11-11 ruling): the delta
        # deliberately leaves it as the pre-delta build made it — stale
        # until the next rebuild, never rewritten inline.
        assert_equal [passage_id_of("urn:d:s:3")], cjk_rowids(@fulltext),
                     "the cjk lane keeps the pre-delta build's rows at the delta grain"
        %i[passage_lemmas passages_trigram passages_trigram_scope lemma_frequencies
           passage_chars reflex_roots reflex_root_stats].each do |table|
          assert_equal table_rows(fresh, table), table_rows(@fulltext, table),
                       "#{table} must be row-identical to a from-scratch rebuild"
        end
        # char_postings at the delta grain: "s" mixes Greek with Han, and
        # urn:d:s:2 was REVISED — its old text is gone and passage_chars
        # holds only Han, so its exact decrement is unknowable. The
        # aggregate is flagged stale (never silently recomputed inline)
        # and the maintenance rail's recompute converges it exactly.
        assert Nabu::Store::StaleAggregates.stale?(@fulltext, aggregate: "char_postings", scope: "s"),
               "the unsound revision flags the source's postings stale"
        Nabu::Store::Indexer.recompute_char_postings!(catalog: @catalog, fulltext: @fulltext, slug: "s")

        assert_equal table_rows(fresh, :char_postings), table_rows(@fulltext, :char_postings),
                     "the rail's recompute converges char_postings to the rebuild's rows"
        refute Nabu::Store::StaleAggregates.stale?(@fulltext, aggregate: "char_postings", scope: "s")
        assert_equal %w[urn:d:s:2], match_urns("revised"),
                     "the delta-refreshed slice answers MATCH with the revised tokens"
        assert_empty match_urns("doomed"), "the removed row stops matching"
      ensure
        fresh.disconnect
      end
    end

    # THE GRAIN PROOF: a row outside the delta is never rewritten. A
    # manually removed fts row of the same source stays missing after a
    # delta refresh (the slice rewrite would heal it) — the refresh touched
    # only the delta's rows.
    def test_delta_refresh_leaves_rows_outside_the_delta_untouched
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      rebuild!

      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(text_normalized: "revised")
      tampered = passage_id_of("urn:d:s:1")
      @fulltext[:passages_fts].where(rowid: tampered).delete

      refresh!(delta: delta_of(upserted: %w[urn:d:s:2]))

      refute_includes fts_rowids(@fulltext), tampered,
                      "the untouched row was not rewritten — the refresh worked the delta grain"
      assert_equal %w[urn:d:s:2], match_urns("revised")
    end

    def test_overflowed_delta_falls_back_to_the_slice_rewrite
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      rebuild!

      # The tamper the delta grain would preserve (test above) must HEAL
      # under the fallback: an overflowed delta carries no usable sets.
      tampered = passage_id_of("urn:d:s:1")
      @fulltext[:passages_fts].where(rowid: tampered).delete
      overflowed = Nabu::Store::IndexDelta.new(cap: 0)
      overflowed.upsert(passage_id_of("urn:d:s:2"), "urn:d:s:2")

      assert_predicate overflowed, :overflowed?
      refresh!(delta: overflowed)

      assert_includes fts_rowids(@fulltext), tampered,
                      "the overflow fallback rewrites the whole slice"
    end

    def test_healing_refresh_ignores_the_delta
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      rebuild!
      refresh!

      # A crashed prior slice: pending marker + a half-written slice. The
      # next refresh arrives with a (valid, small) delta — but the crashed
      # run's work is NOT in it, so the heal must rewrite the whole slice.
      slice_rows.where(slug: "s").update(finished_at: nil)
      tampered = passage_id_of("urn:d:s:1")
      @fulltext[:passages_fts].where(rowid: tampered).delete
      @fulltext[Nabu::Store::Indexer::ROW_SHAS_TABLE].where(rowid: tampered).delete # the crash shape
      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(text_normalized: "revised", content_sha256: "ab12")

      refresh!(delta: delta_of(upserted: %w[urn:d:s:2]))

      assert_includes fts_rowids(@fulltext), tampered,
                      "a pending slice heals the crashed run's rows — the delta's baseline is lost"
      assert_equal %w[urn:d:s:2], match_urns("revised"), "and the load's own change lands too"
      refute Nabu::Store::Indexer.slice_pending?(@fulltext, "s")
    end

    def test_empty_delta_still_marks_the_slice_finished
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      rebuild!

      count = refresh!(delta: Nabu::Store::IndexDelta.new)

      assert_equal 1, count, "the return stays the source's live count"
      refute Nabu::Store::Indexer.slice_pending?(@fulltext, "s")
    end

    def test_delta_refresh_returns_the_sources_live_count
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "alpha", sequence: 0)
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "beta", sequence: 1)
      rebuild!
      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(text_normalized: "revised")

      assert_equal 2, refresh!(delta: delta_of(upserted: %w[urn:d:s:2])),
                   "the count is the source's live total, not the delta size"
    end

    def test_delta_refresh_swaps_the_sign_coverage_rows_by_id
      sign_source = Nabu::Store::Source.create(
        slug: Nabu::Store::Indexer::SIGN_SOURCES.first, name: "Signs",
        adapter_class: "TestAdapter", license_class: "open"
      )
      doc = make_document(urn: "urn:d:sign", source: sign_source)
      make_passage(doc, urn: "urn:d:sign:1", text_normalized: "ak", sequence: 0, language: "akk")
      make_passage(doc, urn: "urn:d:sign:2", text_normalized: "min", sequence: 1, language: "akk")
      sign_list = Nabu::SignList.load(File.join(Nabu::TestSupport.fixtures("osl"), "osl.asl"))
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, sign_list: sign_list)
      table = @fulltext[Nabu::Store::Indexer::PASSAGE_SIGNS_TABLE]

      assert_equal 2, table.count, "both sign passages carry coverage rows"
      untouched = table.first(rowid: passage_id_of("urn:d:sign:1")).values

      Nabu::Store::Passage.first(urn: "urn:d:sign:2").update(text_normalized: "min ak")
      refresh!(slug: sign_source.slug, sign_list: sign_list,
               delta: delta_of(upserted: %w[urn:d:sign:2]))

      assert_equal 2, table.count
      assert_equal untouched, table.first(rowid: passage_id_of("urn:d:sign:1")).values,
                   "the unchanged passage's coverage row is untouched"
      revised = table.first(rowid: passage_id_of("urn:d:sign:2"))

      assert_equal 2, revised[:nsigns], "the revised passage's coverage re-tokenized (AK + MIN)"
    end

    # -- the exact-diff heal (fts_row_shas) ----------------------------------
    # A crashed slice refresh used to heal by rewriting the WHOLE slice —
    # the contentless index cannot say what it indexed. The fts_row_shas
    # sidecar records, per indexed rowid, the first 8 bytes of the catalog
    # sha it was indexed from; a heal diffs that against the catalog and
    # re-does exactly the drifted rows. The invariant: a row's sidecar sha
    # is removed BEFORE any of its fts/lemma rows go and written LAST after
    # they land, so a current sha means fully indexed at the fts+lemma grain.

    def row_shas = @fulltext[Nabu::Store::Indexer::ROW_SHAS_TABLE]

    def sha_hex(text) = Digest::SHA256.hexdigest(text)

    def heal_fixture
      doc = make_document(urn: "urn:d:s")
      %w[alpha beta gamma delta epsilon].each_with_index do |word, index|
        make_passage(doc, urn: "urn:d:s:#{index + 1}", text_normalized: word, sequence: index,
                          sha: sha_hex(word), annotations: token_annotations([word, word]))
      end
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "στρατηγοσ", sequence: 0, sha: sha_hex("σ"))
      rebuild!
      doc
    end

    # The crashed run: marker left pending, one revision whose fts row was
    # rewritten but whose lemma + sidecar writes never landed, one added row
    # whose fts insert landed alone, and one withdrawal whose sidecar delete
    # landed but whose fts/lemma deletes did not.
    # A crash that leaves the lemma rows moved without the census delta is
    # a BULK-shape crash (an atomic run rolls back whole), so the run had
    # journaled its census baseline and recorded its shape first — exactly
    # as refresh_source! does before a bulk unit's first write.
    def crash_mid_refresh(doc)
      source_ids = @catalog[:passages].where(document_id: doc.id).select_map(:id)
      Nabu::Store::Indexer.write_census_baseline!(@fulltext, "s", source_ids)
      revised = Nabu::Store::Passage.first(urn: "urn:d:s:2")
      revised.update(text_normalized: "revised", content_sha256: sha_hex("revised"),
                     annotations_json: JSON.generate(token_annotations(%w[revised revised])))
      row_shas.where(rowid: revised.id).delete
      lemmas.where(passage_id: revised.id).delete
      fts.where(rowid: revised.id).delete
      fts.insert(rowid: revised.id, text_normalized: "revised", language: Nabu::Store::Indexer.language_token("grc"),
                 source: Nabu::Store::Indexer.source_token("s"))
      added = make_passage(doc, urn: "urn:d:s:6", text_normalized: "zeta", sequence: 5, sha: sha_hex("zeta"))
      fts.insert(rowid: added.id, text_normalized: "zeta", language: Nabu::Store::Indexer.language_token("grc"),
                 source: Nabu::Store::Indexer.source_token("s"))
      withdrawn = Nabu::Store::Passage.first(urn: "urn:d:s:3")
      withdrawn.update(withdrawn: true)
      row_shas.where(rowid: withdrawn.id).delete
      slice_rows.where(slug: "s").update(finished_at: nil) if @fulltext.table_exists?(:slice_refreshes)
      Nabu::Store::Indexer.mark_slice_pending!(@fulltext, "s", shape: "bulk")
      [revised.id, added.id, withdrawn.id]
    end

    def assert_identical_to_a_fresh_rebuild
      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh)
        assert_equal fts_rowids(fresh), fts_rowids(@fulltext), "passages_fts holds the identical rowid set"
        %i[passage_lemmas lemma_frequencies fts_row_shas char_postings].each do |table|
          assert_equal table_rows(fresh, table), table_rows(@fulltext, table),
                       "#{table} must be row-identical to a from-scratch rebuild"
        end
      ensure
        fresh.disconnect
      end
    end

    def test_rebuild_records_a_sidecar_sha_per_indexed_row
      heal_fixture

      assert_equal fts_rowids(@fulltext), row_shas.select_map(:rowid).sort
      alpha = @catalog[:passages].first(urn: "urn:d:s:1")

      assert_equal [sha_hex("alpha")[0, 16]].pack("H*"), row_shas.first(rowid: alpha[:id])[:sha],
                   "the grain: the first 8 bytes of the catalog sha"
      assert_equal 8, row_shas.first(rowid: alpha[:id])[:sha].bytesize
      assert_equal [@source.id], row_shas.where(rowid: alpha[:id]).select_map(:source_id)
    end

    def test_a_heal_with_the_sidecar_moves_only_the_drifted_rows
      doc = heal_fixture
      drifted = crash_mid_refresh(doc)
      inserted = nil
      deleted_ids = nil
      mod = Nabu::Store::Indexer
      original_insert = mod.method(:insert_passage_batches)
      original_delete = mod.method(:delete_fts_rows_by_rowid)
      mod.define_singleton_method(:insert_passage_batches) do |*args, **kw|
        original_insert.call(*args, **kw).tap { |result| inserted = result.first }
      end
      mod.define_singleton_method(:delete_fts_rows_by_rowid) do |fulltext, table, ids, **kw|
        deleted_ids = ids.to_a.sort if table == :passages_fts
        original_delete.call(fulltext, table, ids, **kw)
      end
      begin
        refresh!
      ensure
        mod.define_singleton_method(:insert_passage_batches, original_insert)
        mod.define_singleton_method(:delete_fts_rows_by_rowid, original_delete)
      end

      assert_equal drifted.sort, deleted_ids, "exactly the drifted rowids leave the index"
      assert_equal 2, inserted, "exactly the drifted LIVE rows are re-derived (revised + added)"
      refute Nabu::Store::Indexer.slice_pending?(@fulltext, "s")
      assert_identical_to_a_fresh_rebuild
      assert_equal %w[urn:d:s:2], match_urns("revised")
      assert_empty match_urns("gamma"), "the withdrawn row stops matching"
    end

    def test_the_exact_heal_survives_the_bulk_transaction_shape
      doc = heal_fixture
      crash_mid_refresh(doc)
      refresh!(bulk_threshold: 1)

      assert_identical_to_a_fresh_rebuild
    end

    # 2026-11-11 maintenance ruling: a heal — like every refresh — leaves
    # the cjk lane entirely alone. A crashed run's lane damage (stale or
    # missing bigram rows) waits for the next rebuild, which rebuilds the
    # lane whole as a linear append; the sidecar heal repairs the MAIN
    # index only.
    def test_a_heal_leaves_the_cjk_lane_alone
      doc = make_document(urn: "urn:d:s")
      %w[天地玄黃 宇宙洪荒].each_with_index do |text, i|
        make_passage(doc, urn: "urn:d:s:#{i + 1}", text_normalized: text, sequence: i,
                          language: "lzh", sha: sha_hex(text))
      end
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, cjk_slugs: ["s"])

      revised = Nabu::Store::Passage.first(urn: "urn:d:s:2")
      revised.update(text_normalized: "乾坤一擲", content_sha256: sha_hex("乾坤一擲"))
      Nabu::Store::Indexer.mark_slice_pending!(@fulltext, "s")
      refresh!

      assert_equal %w[urn:d:s:2], match_urns("乾坤一擲"), "the heal repairs the main index"
      assert_equal 2, cjk.count, "the lane keeps the last rebuild's rows untouched"
      assert_equal %w[urn:d:s:2], cjk_match_urns('"宇宙"'),
                   "…stale bigrams included — they wait for the next rebuild"
    end

    def test_a_heal_without_the_sidecar_falls_back_to_the_full_slice
      doc = heal_fixture
      crash_mid_refresh(doc)
      @fulltext.drop_table(Nabu::Store::Indexer::ROW_SHAS_TABLE) # a fulltext predating the sidecar
      inserted = nil
      observing(:insert_passage_batches) do |calls|
        refresh!
        inserted = calls.first.first
      end

      assert_equal 5, inserted, "the whole live slice is rewritten (5 live rows of s)"
      live_ids = @catalog[:passages].where(urn: (1..6).map { |i| "urn:d:s:#{i}" }, withdrawn: false)
                                    .select_map(:id).sort

      assert_equal live_ids, row_shas.where(source_id: @source.id).select_map(:rowid).sort,
                   "the full-slice rewrite brings the sidecar and populates the whole slice"
      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh)
        assert_equal fts_rowids(fresh), fts_rowids(@fulltext)
        assert_equal table_rows(fresh, :passage_lemmas), table_rows(@fulltext, :passage_lemmas)
      ensure
        fresh.disconnect
      end
    end

    def test_incremental_readiness_never_requires_the_sidecar
      heal_fixture
      @fulltext.drop_table(Nabu::Store::Indexer::ROW_SHAS_TABLE)

      assert Nabu::Store::Indexer.incremental_ready?(@fulltext)
    end

    def test_the_sidecar_sha_is_written_last_and_removed_first
      doc = heal_fixture
      Nabu::Store::Passage.first(urn: "urn:d:s:1").update(text_normalized: "changed", content_sha256: sha_hex("c"))
      make_passage(doc, urn: "urn:d:s:6", text_normalized: "zeta", sequence: 5, sha: sha_hex("zeta"),
                        annotations: token_annotations(%w[zeta zeta]))
      io = StringIO.new
      logger = Logger.new(io)
      @fulltext.loggers << logger
      begin
        refresh!
      ensure
        @fulltext.loggers.delete(logger)
      end
      config_command = /'(merge|deletemerge)'/
      writes = io.string.lines.grep_v(config_command).filter_map do |line|
        case line
        when /DELETE FROM `fts_row_shas`/ then :sidecar_delete
        when /DELETE FROM `passage_lemmas`/ then :lemma_delete
        when /DELETE FROM `passages_fts`/ then :fts_delete
        when /INSERT INTO `passages_fts`/ then :fts_insert
        when /INSERT INTO `passage_lemmas`/ then :lemma_insert
        when /INSERT (OR REPLACE )?INTO `fts_row_shas`/ then :sidecar_insert
        end
      end

      assert_equal :sidecar_delete, writes.first,
                   "the sidecar sha goes BEFORE any fts/lemma row (got #{writes.inspect})"
      assert_operator writes.index(:sidecar_delete), :<, writes.index(:lemma_delete)
      assert_operator writes.index(:lemma_delete), :<, writes.index(:fts_delete)
      assert_equal :sidecar_insert, writes.last, "the sidecar sha lands LAST, after the batch's fts and lemma rows"
      assert_operator writes.index(:fts_insert), :<, writes.index(:lemma_insert)
      assert_operator writes.index(:lemma_insert), :<, writes.index(:sidecar_insert)
    end

    def test_withdrawn_and_removed_rows_leave_the_sidecar
      doc = heal_fixture
      gone = Nabu::Store::Passage.first(urn: "urn:d:s:3")
      gone.update(withdrawn: true)
      refresh!

      assert_nil row_shas.first(rowid: gone.id), "a slice rewrite drops the withdrawn row's sha"

      removed = Nabu::Store::Passage.first(urn: "urn:d:s:4")
      removed.update(withdrawn: true)
      refresh!(delta: delta_of(removed: %w[urn:d:s:4]))

      assert_nil row_shas.first(rowid: removed.id), "a delta removal drops the row's sha"
      doc.update(withdrawn: true)
      refresh!

      assert_empty row_shas.where(source_id: @source.id), "a withdrawn document takes every sha with it"
      assert_identical_to_a_fresh_rebuild
    end

    # -- char postings at the delta grain (the incrementality review) -------
    # The per-source postings aggregate is decomposable: a delta subtracts
    # the changed rows' OLD contribution and adds the upserted rows' new
    # one — never a whole-source catalog scan. The old contribution is
    # exact where the row-sha sidecar vouches the catalog still holds the
    # indexed text (withdrawals, unchanged re-entries), and for a REVISED
    # row where the source is Han-pure (passage_chars holds its old Han
    # set, which is then its whole posted set). Anywhere else the grain is
    # unsound and the source's postings are flagged STALE for the
    # maintenance rail — never recomputed inline.

    def postings_rows(db = @fulltext) = table_rows(db, :char_postings)

    def stale_postings?(slug = "s")
      Nabu::Store::StaleAggregates.stale?(@fulltext, aggregate: "char_postings", scope: slug)
    end

    def assert_postings_match_a_fresh_rebuild
      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh)
        assert_equal postings_rows(fresh), postings_rows, "char_postings must be row-identical to a full recompute"
      ensure
        fresh.disconnect
      end
    end

    def refute_source_scan(&)
      observing(:source_char_postings) do |calls|
        yield
        assert_empty calls, "the delta never scans the whole source for its postings"
      end
    end

    def test_a_delta_of_adds_and_withdrawals_moves_postings_exactly
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "λογοσ αει", sequence: 0, sha: sha_hex("1"))
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "μηνιν", sequence: 1, sha: sha_hex("2"))
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "λογοσ", sequence: 0, sha: sha_hex("l"))
      rebuild!

      make_passage(doc, urn: "urn:d:s:3", text_normalized: "ναυσ λογοσ", sequence: 2, sha: sha_hex("3"))
      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(withdrawn: true)
      refute_source_scan { refresh!(delta: delta_of(upserted: %w[urn:d:s:3], removed: %w[urn:d:s:2])) }

      refute stale_postings?, "adds and withdrawals are always sound"
      assert_postings_match_a_fresh_rebuild
    end

    def test_a_revision_in_a_han_pure_source_decrements_from_passage_chars
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "天地玄黃", sequence: 0, language: "lzh", sha: sha_hex("1"))
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "宇宙洪荒 abc", sequence: 1, language: "lzh",
                        sha: sha_hex("2"))
      make_passage(doc, urn: "urn:d:s:3", text_normalized: "plain ascii", sequence: 2, sha: sha_hex("3"))
      rebuild!

      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(text_normalized: "日月盈昃", content_sha256: sha_hex("2b"))
      Nabu::Store::Passage.first(urn: "urn:d:s:3").update(text_normalized: "now 天", content_sha256: sha_hex("3b"))
      refute_source_scan { refresh!(delta: delta_of(upserted: %w[urn:d:s:2 urn:d:s:3])) }

      refute stale_postings?, "a Han-pure source's revisions decrement exactly from passage_chars"
      assert_postings_match_a_fresh_rebuild
    end

    def test_a_revision_in_a_mixed_source_flags_the_postings_stale_without_a_scan
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "λογοσ 天", sequence: 0, sha: sha_hex("1"))
      make_passage(doc, urn: "urn:d:s:2", text_normalized: "μηνιν", sequence: 1, sha: sha_hex("2"))
      rebuild!
      before = postings_rows

      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(text_normalized: "ναυσ", content_sha256: sha_hex("2b"))
      refute_source_scan { refresh!(delta: delta_of(upserted: %w[urn:d:s:2])) }

      assert stale_postings?, "the old Greek of a revised row is unknowable — flagged, not guessed"
      assert_equal before, postings_rows, "the stale source's postings are left as they stood"
      Nabu::Store::Indexer.recompute_char_postings!(catalog: @catalog, fulltext: @fulltext, slug: "s")

      refute stale_postings?
      assert_postings_match_a_fresh_rebuild
    end

    def test_a_stale_source_stays_stale_through_later_deltas_until_recomputed
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "λογοσ", sequence: 0, sha: sha_hex("1"))
      rebuild!
      Nabu::Store::StaleAggregates.mark!(@fulltext, aggregate: "char_postings", scope: "s", reason: "planted")

      make_passage(doc, urn: "urn:d:s:2", text_normalized: "ναυσ", sequence: 1, sha: sha_hex("2"))
      refresh!(delta: delta_of(upserted: %w[urn:d:s:2]))

      assert stale_postings?, "a delta never applies its arithmetic on a stale base"
      refresh! # the whole-slice rewrite re-derives the source's postings outright

      refute stale_postings?, "a full-slice refresh clears the flag"
      assert_postings_match_a_fresh_rebuild
    end

    def test_a_full_rebuild_clears_every_stale_flag
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "λογοσ", sequence: 0)
      rebuild!
      Nabu::Store::StaleAggregates.mark!(@fulltext, aggregate: "char_postings", scope: "s", reason: "planted")
      rebuild!

      refute stale_postings?
    end

    # -- the heal's lemma census, bounded to the healed source --------------
    # A healing refresh used to re-census lemma_frequencies over the WHOLE
    # corpus (the crashed run's before-snapshot was lost). Now the run's
    # transaction shape decides: an atomic run's crash rolled back whole,
    # so the heal's own before/after delta is exact; a bulk run journals
    # the source's whole contribution as a baseline before its first
    # write, and its heal applies baseline → the source's current
    # contribution. Either way only the healed source's rows are read.

    def crash_after(name)
      mod = Nabu::Store::Indexer
      original = mod.method(name)
      mod.define_singleton_method(name) do |*args, **kw, &blk|
        original.call(*args, **kw, &blk)
        raise "crash after #{name}"
      end
      yield
    ensure
      mod.define_singleton_method(name, original)
    end

    def census_fixture
      doc = make_document(urn: "urn:d:s")
      %w[alpha beta].each_with_index do |word, index|
        make_passage(doc, urn: "urn:d:s:#{index + 1}", text_normalized: word, sequence: index,
                          sha: sha_hex(word), annotations: token_annotations([word, word]))
      end
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "gamma", sequence: 0, sha: sha_hex("g"),
                        annotations: token_annotations(%w[gamma gamma]))
      rebuild!
      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(
        text_normalized: "revised", content_sha256: sha_hex("revised"),
        annotations_json: JSON.generate(token_annotations(%w[revised revised]))
      )
      make_passage(doc, urn: "urn:d:s:3", text_normalized: "delta", sequence: 2, sha: sha_hex("delta"),
                        annotations: token_annotations(%w[delta delta]))
    end

    # The heal's census reads: no corpus re-census, and every snapshot
    # stays inside the healed source's passage ids.
    def assert_census_bounded_to_the_source(&)
      source_ids = @catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                                      .where(Sequel[:documents][:source_id] => @source.id)
                                      .select_map(Sequel[:passages][:id]).to_set
      snapshot_ids = Set.new
      freq = Nabu::Store::LemmaFrequencies
      original_rebuild = freq.method(:rebuild!)
      original_snapshot = freq.method(:snapshot)
      rebuilds = 0
      freq.define_singleton_method(:rebuild!) do |*args|
        rebuilds += 1
        original_rebuild.call(*args)
      end
      freq.define_singleton_method(:snapshot) do |fulltext, ids:|
        snapshot_ids.merge(ids.to_a)
        original_snapshot.call(fulltext, ids: ids)
      end
      begin
        yield
      ensure
        freq.define_singleton_method(:rebuild!, original_rebuild)
        freq.define_singleton_method(:snapshot, original_snapshot)
      end
      assert_equal 0, rebuilds, "the heal never re-censuses the corpus"
      assert_operator snapshot_ids, :subset?, source_ids, "every census read stays in the healed source"
    end

    def test_a_crashed_bulk_run_heals_its_census_from_the_source_baseline
      census_fixture
      crash_after(:insert_passage_batches) do
        assert_raises(RuntimeError) { refresh!(bulk_threshold: 1) }
      end
      assert Nabu::Store::Indexer.slice_pending?(@fulltext, "s")

      assert_census_bounded_to_the_source { refresh! }
      refute Nabu::Store::StaleAggregates.stale?(@fulltext, aggregate: "lemma_census", scope: "corpus")
      assert_identical_to_a_fresh_rebuild
      assert_equal 0, @fulltext[Nabu::Store::Indexer::CENSUS_BASELINES_TABLE].count, "the baseline is spent"
    end

    def test_a_crashed_atomic_run_heals_its_census_by_the_delta_alone
      census_fixture
      crash_after(:insert_passage_batches) do
        assert_raises(RuntimeError) { refresh! }
      end
      assert Nabu::Store::Indexer.slice_pending?(@fulltext, "s")

      assert_census_bounded_to_the_source { refresh! }
      refute Nabu::Store::StaleAggregates.stale?(@fulltext, aggregate: "lemma_census", scope: "corpus")
      assert_identical_to_a_fresh_rebuild
    end

    def test_a_pending_marker_of_unknown_shape_flags_the_census_for_the_rail
      census_fixture
      Nabu::Store::Indexer.mark_slice_pending!(@fulltext, "s") # minted before shapes were recorded

      assert_census_bounded_to_the_source { refresh! }
      assert Nabu::Store::StaleAggregates.stale?(@fulltext, aggregate: "lemma_census", scope: "corpus"),
             "a crash of unknown shape may have drifted the census — flagged, not re-censused inline"
    end

    # -- above-budget rewrites become shadow builds (the incrementality review)
    # In-place fts churn is what the engine is pathological at: tombstones
    # plus re-inserts leave merge debt it repays inside arbitrary later
    # statements. Past IN_PLACE_ROW_BUDGET rows, a lane's new content is
    # built as an APPEND-ONLY shadow and swapped in whole — the old
    # structure is dropped, never churned. Below it, in place as before.

    # Two sources, both indexed; "s" then mutates (add + revise + withdraw).
    def shadow_fixture(also: nil)
      doc = make_document(urn: "urn:d:s")
      %w[alpha beta gamma].each_with_index do |word, index|
        make_passage(doc, urn: "urn:d:s:#{index + 1}", text_normalized: word, sequence: index,
                          sha: sha_hex(word), annotations: token_annotations([word, word]))
      end
      lit = make_document(urn: "urn:d:lit", source: literary_source)
      make_passage(lit, urn: "urn:d:lit:1", text_normalized: "στρατηγοσ 棄", sequence: 0, sha: sha_hex("σ"))
      make_passage(lit, urn: "urn:d:lit:2", text_normalized: "ναυσ", sequence: 1, sha: sha_hex("ν"))
      [@fulltext, also].compact.each do |fulltext|
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fulltext, fuzzy_slugs: %w[s lit])
      end
      doc
    end

    def mutate_shadow_fixture(doc)
      make_passage(doc, urn: "urn:d:s:4", text_normalized: "delta 王", sequence: 3, sha: sha_hex("delta"),
                        annotations: token_annotations(%w[delta delta]))
      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(text_normalized: "revised", content_sha256: sha_hex("r"))
      Nabu::Store::Passage.first(urn: "urn:d:s:3").update(withdrawn: true)
    end

    # The slice key set of "s" is 4 rows after the mutation.
    def test_a_rewrite_at_the_budget_stays_in_place
      doc = shadow_fixture
      mutate_shadow_fixture(doc)
      # The discriminator: a tampered row of ANOTHER source. In place, the
      # refresh never touches it; a shadow re-derives every indexed row.
      tampered = passage_id_of("urn:d:lit:2")
      fts.where(rowid: tampered).delete
      spy = BulkSpy.new
      refresh!(row_budget: 4, fuzzy_slugs: %w[s lit], progress: spy)

      refute_includes fts_rowids(@fulltext), tampered, "at the budget the write stays in place"
      refute(spy.stages.any? { |line| line.include?("shadow") }, "no shadow is announced (#{spy.stages.inspect})")
    end

    def test_a_rewrite_over_the_budget_builds_a_shadow_identical_to_the_in_place_run
      in_place = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        doc = shadow_fixture(also: in_place)
        mutate_shadow_fixture(doc)
        Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: in_place, slug: "s",
                                             fuzzy_slugs: %w[s lit])
        spy = BulkSpy.new
        refresh!(row_budget: 3, fuzzy_slugs: %w[s lit], progress: spy)

        assert(spy.stages.any? { |line| line.include?("shadow build") },
               "the shadow is announced (#{spy.stages.inspect})")
        assert_equal fts_rowids(in_place), fts_rowids(@fulltext), "passages_fts: the identical rowid set"
        %i[passage_lemmas lemma_frequencies fts_row_shas char_postings passage_chars
           passages_trigram passages_trigram_scope].each do |table|
          assert_equal table_rows(in_place, table), table_rows(@fulltext, table),
                       "#{table} must be row-identical to the in-place run"
        end
        assert_equal %w[urn:d:s:2], match_urns("revised"), "the swapped-in table answers MATCH"
        assert_empty match_urns("gamma"), "the withdrawn row is absent from the shadow"
        refute @fulltext.table_exists?(Nabu::Store::Indexer::SHADOW_TABLE), "the shadow name is gone after the swap"
        assert_equal 0, Nabu::Store::FtsStructure.gauges(@fulltext, :passages_fts)[:tombstone_pages],
                     "an append-only build carries zero tombstones"
      ensure
        in_place.disconnect
      end
    end

    def test_a_shadow_build_rederives_every_indexed_row_of_other_sources
      doc = shadow_fixture
      mutate_shadow_fixture(doc)
      tampered = passage_id_of("urn:d:lit:2")
      fts.where(rowid: tampered).delete
      refresh!(row_budget: 0)

      assert_includes fts_rowids(@fulltext), tampered,
                      "the shadow indexes every sidecar-recorded row, not just the refreshed source's"
      assert_identical_to_a_fresh_rebuild
    end

    def test_a_killed_shadow_builds_orphan_is_dropped_and_the_old_table_keeps_serving
      shadow_fixture
      @fulltext.run(Nabu::Store::Indexer::CREATE_TABLE.sub("passages_fts", "passages_fts_shadow"))

      assert_equal %w[urn:d:lit:1 urn:d:lit:2 urn:d:s:1 urn:d:s:2 urn:d:s:3], fts_urns,
                   "the serving table is untouched by an orphan beside it"
      refresh!

      refute @fulltext.table_exists?(Nabu::Store::Indexer::SHADOW_TABLE), "the next refresh drops the orphan"
    end

    def test_the_shadow_needs_a_complete_sidecar_and_says_so_otherwise
      doc = shadow_fixture
      mutate_shadow_fixture(doc)
      row_shas.where(source_id: literary_source.id).delete # a slice indexed before the sidecar existed
      spy = BulkSpy.new
      refresh!(row_budget: 0, progress: spy)

      assert(spy.stages.any? { |line| line.include?("sidecar incomplete") },
             "the fallback is announced (#{spy.stages.inspect})")
      assert_equal %w[urn:d:lit:1 urn:d:lit:2], urns_of(fts_rowids(@fulltext)).grep(/lit/),
                   "the other source keeps its rows — a shadow would have lost them"
    end

    def test_an_over_budget_trigram_lane_is_rebuilt_whole
      doc = shadow_fixture
      mutate_shadow_fixture(doc)
      spy = BulkSpy.new
      refresh!(row_budget: 3, fuzzy_slugs: %w[s lit], progress: spy)

      assert(spy.stages.any? { |line| line.include?("trigram lane: shadow build") },
             "the trigram lane's whole rebuild is announced (#{spy.stages.inspect})")
      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      begin
        Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fresh, fuzzy_slugs: %w[s lit])
        %i[passages_trigram passages_trigram_scope].each do |table|
          assert_equal table_rows(fresh, table), table_rows(@fulltext, table), "#{table} matches a fresh build"
        end
      ensure
        fresh.disconnect
      end
    end

    # -- the wave refresh: one shadow pass for many deferred sources --------
    # A >budget slice pays a full-corpus shadow pass; N deferred sources
    # refreshed one by one pay N corpus passes. refresh_sources! plans the
    # whole wave first and, when the wave's write volume is over budget,
    # builds ONE shadow holding every wave member's live rows plus the
    # recorded rows of everyone else, swaps it once, and then runs each
    # member's non-fts stages in place.

    # Both sources indexed, then both grow in the catalog without an index
    # step (the deferred-sync shape): s by two rows, lit by one.
    def wave_fixture
      doc = shadow_fixture
      mutate_shadow_fixture(doc)
      lit = Nabu::Store::Document.first(urn: "urn:d:lit")
      make_passage(lit, urn: "urn:d:lit:3", text_normalized: "τριηρησ", sequence: 2, sha: sha_hex("τ"))
      doc
    end

    def with_ledger
      dir = Dir.mktmpdir("nabu-wave")
      ledger = Nabu::Store::Ledger.open!(File.join(dir, "history.sqlite3"))
      yield ledger
    ensure
      ledger&.disconnect
      FileUtils.rm_rf(dir) if dir
    end

    def refresh_wave!(slugs, **)
      Nabu::Store::Indexer.refresh_sources!(catalog: @catalog, fulltext: @fulltext, slugs: slugs, **)
    end

    def shadow_stage_rows(ledger)
      ledger[Nabu::Store::StageTimings::TABLE].where(stage: "fts_shadow").all
    end

    def test_a_wave_of_over_budget_sources_pays_exactly_one_shadow_pass
      wave_fixture
      with_ledger do |ledger|
        spy = BulkSpy.new([])
        counts = refresh_wave!(%w[s lit], row_budget: 2, ledger: ledger, progress: spy)

        assert_equal({ "s" => 3, "lit" => 3 }, counts, "each member reports its own live count")
        assert_equal 1, shadow_stage_rows(ledger).size, "ONE fts_shadow stage for the whole wave"
        assert_equal 1, spy.stages.count { |line| line.include?("passages_fts shadow build") }, spy.stages.inspect
        assert_equal %w[lit s], ledger[Nabu::Store::StageTimings::TABLE].where(stage: "index_slice")
                                                                        .select_map(:scope).sort,
                     "the non-fts stages still record per source"
      end
      assert_equal %w[urn:d:s:4], match_urns("delta"), "the first member is searchable"
      assert_equal %w[urn:d:lit:3], match_urns("τριηρησ"), "the second member is searchable"
      refute Nabu::Store::Indexer.slice_pending?(@fulltext, "s")
      refute Nabu::Store::Indexer.slice_pending?(@fulltext, "lit")
      assert_identical_to_a_fresh_rebuild
    end

    def test_a_wave_whose_union_is_over_budget_takes_the_one_shadow_path
      wave_fixture
      with_ledger do |ledger|
        # s writes 4 slice keys, lit 3: each under the 5-row budget, 7 together over it.
        refresh_wave!(%w[s lit], row_budget: 5, ledger: ledger)

        assert_equal 1, shadow_stage_rows(ledger).size, "the union crossed the budget — one shadow"
      end
      assert_identical_to_a_fresh_rebuild
    end

    def test_a_wave_under_budget_stays_in_place
      wave_fixture
      tampered = passage_id_of("urn:d:s:1")
      with_ledger do |ledger|
        refresh_wave!(%w[s lit], row_budget: 7, ledger: ledger)

        assert_empty shadow_stage_rows(ledger), "7 rows at the 7-row budget stay in place"
      end
      assert_equal %w[urn:d:lit:3], match_urns("τριηρησ")
      assert_includes fts_rowids(@fulltext), tampered
    end

    def test_a_one_slug_wave_is_the_plain_refresh
      wave_fixture
      with_ledger do |ledger|
        counts = refresh_wave!(%w[s], row_budget: 2, ledger: ledger)

        assert_equal({ "s" => 3 }, counts)
        assert_equal ["s"], shadow_stage_rows(ledger).map { |row| row[:scope] },
                     "a single slug keeps the per-source shadow, scoped to its slug"
      end
    end

    def test_a_wave_keeps_recorded_rows_of_sources_outside_it
      wave_fixture
      third = Nabu::Store::Source.create(slug: "x", name: "X", adapter_class: "TestAdapter", license_class: "open")
      xdoc = make_document(urn: "urn:d:x", source: third)
      make_passage(xdoc, urn: "urn:d:x:1", text_normalized: "ξενοσ", sequence: 0, sha: sha_hex("ξ"))
      refresh!(slug: "x")
      refresh_wave!(%w[s lit], row_budget: 2)

      assert_equal %w[urn:d:x:1], match_urns("ξενοσ"), "a non-member's recorded rows survive the swap"
      assert_identical_to_a_fresh_rebuild
    end

    def test_a_wave_falls_back_per_source_when_an_outside_sidecar_is_incomplete
      wave_fixture
      third = Nabu::Store::Source.create(slug: "x", name: "X", adapter_class: "TestAdapter", license_class: "open")
      xdoc = make_document(urn: "urn:d:x", source: third)
      make_passage(xdoc, urn: "urn:d:x:1", text_normalized: "ξενοσ", sequence: 0, sha: sha_hex("ξ"))
      refresh!(slug: "x")
      row_shas.where(source_id: third.id).delete # a slice indexed before the sidecar existed
      spy = BulkSpy.new([])
      with_ledger do |ledger|
        refresh_wave!(%w[s lit], row_budget: 2, ledger: ledger, progress: spy)

        assert_empty shadow_stage_rows(ledger), "no shadow could name x's membership"
      end
      assert(spy.stages.any? { |line| line.include?("wave") && line.include?("sidecar incomplete") },
             "the wave announces its fallback (#{spy.stages.inspect})")
      assert_equal %w[urn:d:x:1], match_urns("ξενοσ"), "x keeps its rows"
      assert_equal %w[urn:d:lit:3], match_urns("τριηρησ")
      assert_equal %w[urn:d:s:4], match_urns("delta")
    end

    def test_a_death_after_the_wave_swap_leaves_every_member_pending
      wave_fixture
      # The second member's refresh dies at entry — after the wave's swap
      # (Minitest 6 ships no stub: the original is restored in ensure).
      real = Nabu::Store::Indexer.method(:refresh_source!)
      calls = 0
      Nabu::Store::Indexer.define_singleton_method(:refresh_source!) do |**kwargs|
        calls += 1
        raise Nabu::Error, "simulated death" if calls == 2

        real.call(**kwargs)
      end
      begin
        assert_raises(Nabu::Error) { refresh_wave!(%w[s lit], row_budget: 2) }
      ensure
        Nabu::Store::Indexer.define_singleton_method(:refresh_source!, real)
      end

      assert_equal %w[urn:d:lit:3], match_urns("τριηρησ"),
                   "the swapped index is AHEAD for the member that never ran — never behind"
      assert Nabu::Store::Indexer.slice_pending?(@fulltext, "lit"), "the unrun member reads pending"
      refresh_wave!(%w[s lit], row_budget: 2)
      assert_identical_to_a_fresh_rebuild
    end

    def test_a_wave_member_already_pending_heals_inside_the_wave
      wave_fixture
      Nabu::Store::Indexer.mark_slice_pending!(@fulltext, "lit", shape: "atomic")
      refresh_wave!(%w[s lit], row_budget: 2)

      refute Nabu::Store::Indexer.slice_pending?(@fulltext, "lit")
      assert_identical_to_a_fresh_rebuild
    end
  end
end
