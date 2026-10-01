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

    def postings = @fulltext[Nabu::Store::Indexer::CHAR_POSTINGS_TABLE]

    def fts = @fulltext[:passages_fts]

    def lemmas = @fulltext[Nabu::Store::Indexer::LEMMA_TABLE]

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

    # P93-1 (№R-16): a fresh build mints a CONTENTLESS table — the folded
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
                 "contentless — the text is never stored a second time (the №R-16 point)"
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

    # -- the contentless shape (P93-1, №R-16) --------------------------------
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

    # P105-5d (Q87): the fts+lemma slice walked cbeta's 8.75M passages for
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

      assert_equal "gold", lemmas.where(urn: "urn:d:gold:1").get(:tier),
                   "a source absent from the map stays gold, untouched"
      avis = lemmas.where(urn: "urn:d:cle:1", lemma_folded: "auis").all
      assert_equal 1, avis.size, "one row per (passage, folded key), not per token"
      assert_equal "aves, avif", avis.first.fetch(:surface_forms),
                   "distinct surface forms aggregate on the one row"
      assert_equal %w[equivalence equivalence],
                   lemmas.where(urn: "urn:d:cle:1").select_map(:tier),
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

    # -- the CJK bigram lane (P93-3, №R-39 b) --------------------------------
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
                   "the №R-39 case: the pair sits mid-run and must match"
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

    def test_cjk_refresh_updates_the_slice_and_honors_config_drift
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "六龍", sequence: 0, language: "lzh")
      cjk_rebuild!

      make_passage(doc, urn: "urn:d:s:2", text_normalized: "飛天", sequence: 1, language: "lzh")
      refresh!(cjk_slugs: ["s"])
      assert_equal %w[urn:d:s:1 urn:d:s:2],
                   urns_of(cjk.select_map(Sequel.lit("rowid"))), "the flagged source's slice refreshes"

      refresh!(cjk_slugs: [])
      assert_equal 0, cjk.count, "a de-flagged source loses its rows at refresh"
      assert_equal 0, cjk_scope.count, "…and its scope row, so coverage reads honestly"
    end

    def test_cjk_refresh_adds_a_newly_flagged_sources_slice
      doc = make_document(urn: "urn:d:s")
      make_passage(doc, urn: "urn:d:s:1", text_normalized: "六龍", sequence: 0, language: "lzh")
      rebuild! # no cjk slugs — empty lane

      refresh!(cjk_slugs: ["s"])
      assert_equal [passage_id("urn:d:s:1")], cjk.select_map(Sequel.lit("rowid"))
      assert_equal %w[s], cjk_scope.select_map(:slug)
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

    # -- the bulk slice mode (P111-1, Q111) ----------------------------------
    # A content-bearing re-parse of a big source rewrites millions of fts
    # rows; under the default merge config the automerge/deletemerge
    # machinery fires DURING the delete storm and the batched inserts (the
    # kanripo 6h18m shape). At/above bulk_threshold the slice defers every
    # merge (automerge 0, crisismerge high, deletemerge 0), ensure-restores
    # the defaults, then consolidates in an announced bounded merge loop.
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
      # written (one of the source's rows missing).
      slice_rows.where(slug: "s").update(finished_at: nil)
      doomed = @catalog[:passages].where(urn: "urn:d:s:2").get(:id)
      @fulltext[:passages_fts].where(rowid: doomed).delete

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
    def raising_char_postings
      mod = Nabu::Store::Indexer
      original = mod.method(:write_char_postings)
      mod.define_singleton_method(:write_char_postings) { |*, **| raise "boom" }
      yield
    ensure
      mod.define_singleton_method(:write_char_postings, original)
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

    # -- the delta grain (P112-1, Q112) --------------------------------------
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
      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(
        text_normalized: "revised 国",
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
        assert_equal cjk_rowids(fresh), cjk_rowids(@fulltext),
                     "the cjk lane must hold the identical rowid set at the delta grain"
        %i[passage_lemmas passages_trigram passages_trigram_scope lemma_frequencies
           char_postings passage_chars reflex_roots reflex_root_stats].each do |table|
          assert_equal table_rows(fresh, table), table_rows(@fulltext, table),
                       "#{table} must be row-identical to a from-scratch rebuild"
        end
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
      Nabu::Store::Passage.first(urn: "urn:d:s:2").update(text_normalized: "revised")

      refresh!(delta: delta_of(upserted: %w[urn:d:s:2]))

      assert_includes fts_rowids(@fulltext), tampered,
                      "a pending slice heals in full — the delta's baseline is lost"
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
  end
end
