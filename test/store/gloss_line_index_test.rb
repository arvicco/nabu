# frozen_string_literal: true

require "test_helper"

# The gloss-lines lane of the fulltext index (Store::GlossLineIndex): one
# contentless FTS5 row per live passage whose tokens carry an upstream
# gloss (Query::TokenGlosses' sources, read through Nabu::GlossLines),
# keyed by the catalog passage id, the glosses in token order folded by
# the GLOSS language. Built from the four sources' real fixtures loaded
# through the real Loader.
module Store
  class GlossLineIndexTest < Minitest::Test
    include StoreTestDB

    Index = Nabu::Store::GlossLineIndex
    Indexer = Nabu::Store::Indexer
    GL = Nabu::GlossLines

    # BHSA Dan 2:4 (Aramaic): "and speak the Chaldean to the king in
    # Aramaic king to eternity live …".
    DAN_2_4 = "urn:nabu:bhsa:dan:2.4"
    DAN_2_7 = "urn:nabu:bhsa:dan:2.7"
    JONAH_2_7 = "urn:nabu:bhsa:jonah:2.7"
    JONAH_3_6 = "urn:nabu:bhsa:jonah:3.6"
    # achemenet (Akkadian, BabyLemmatizer English): a lease naming the king.
    LEASE = "urn:nabu:achemenet:p261571:1"
    # tlhdig (Hittite, German glosses): "König aus- fassen".
    KBO_24 = "urn:nabu:tlhdig:626:hfr:kbo.52.195+:24"

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      Nabu::TestSupport.load_gloss_corpus(@catalog)
      # An unregistered source whose tokens carry a "gloss" key (tla-hf's
      # grammatical labels are the live case): never indexed.
      other = Nabu::Store::Source.create(slug: "perseus", name: "P", adapter_class: "TestAdapter",
                                         license_class: "open")
      doc = Nabu::Store::Document.create(source_id: other.id, urn: "urn:x:1", title: "t", language: "grc",
                                         content_sha256: "x", revision: 1)
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:x:1:1", sequence: 0, language: "grc",
                                  text: "βασιλεύς", text_normalized: "βασιλευσ", content_sha256: "x", revision: 1,
                                  annotations_json: '{"tokens":[{"form":"βασιλεύς","gloss":"king"}]}')
    end

    def teardown
      @fulltext.disconnect
    end

    def expected_ids(slug = nil)
      slugs = slug ? [slug] : GL.slugs
      rows = @catalog[:passages].join(:documents, id: :document_id).join(:sources, id: :source_id)
                                .where(Sequel[:sources][:slug] => slugs, Sequel[:passages][:withdrawn] => false,
                                       Sequel[:documents][:withdrawn] => false)
                                .select(Sequel[:passages][:id], Sequel[:passages][:annotations_json],
                                        Sequel[:sources][:slug])
                                .all
      rows.reject { |row| GL.entries(row[:annotations_json], row[:slug]).empty? }.map { |row| row[:id] }.sort
    end

    def indexed_ids = @fulltext[Index::TABLE].select_order_map(:rowid)

    def scope = @fulltext[Index::SCOPE_TABLE].order(:slug).select_map(%i[slug passages])

    def match_ids(expression)
      @fulltext[Index::TABLE].where(Sequel.lit("passages_gloss_lines MATCH ?", expression)).select_order_map(:rowid)
    end

    def passage_id(urn) = @catalog[:passages].where(urn: urn).get(:id)

    def test_rebuild_indexes_every_gloss_bearing_live_passage_and_records_its_scope
      result = Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal expected_ids, indexed_ids
      assert_equal expected_ids.size, result.fetch(:passages)
      assert_equal 4, result.fetch(:sources)
      assert_equal(GL.slugs.sort.map { |slug| [slug, expected_ids(slug).size] }, scope)
      assert_operator expected_ids("bhsa").size, :>, 100, "fixture reality: every BHSA verse is glossed"
    end

    # The use case: a "king"-class content query reaches the passages
    # whose WORDS are glossed king, whatever their own language — Aramaic
    # and Hebrew (BHSA), Akkadian (achemenet).
    def test_king_reaches_passages_glossed_king_across_text_languages
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      kings = match_ids('"king"')
      [DAN_2_4, DAN_2_7, JONAH_3_6, LEASE].each { |urn| assert_includes kings, passage_id(urn), urn }
      refute_includes kings, passage_id(JONAH_2_7)
      refute_includes kings, passage_id("urn:x:1:1"), "an unregistered source never enters the lane"
      refute_includes match_ids('"konig"'), passage_id(DAN_2_4), "a gloss is not its passage's text"
    end

    # What the word-grain lane cannot answer: co-occurrence within ONE
    # passage, and a phrase running across adjacent tokens' glosses.
    def test_co_occurrence_and_cross_token_phrases_are_passage_grain
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal [passage_id(DAN_2_4)], match_ids('"king" "eternity"')
      to_the_king = match_ids('"to the king"')
      assert_includes to_the_king, passage_id(DAN_2_4), "to / the / king are three BHSA tokens"
      refute_includes to_the_king, passage_id(DAN_2_7)
    end

    def test_german_glosses_fold_both_sides
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_includes match_ids('"konig"'), passage_id(KBO_24)
      assert_includes match_ids(%("#{GL.query_forms('König').first}")), passage_id(KBO_24)
      aes = match_ids('"konig"*') & expected_ids("aes")
      refute_empty aes, "Königs (aes, Egyptian text) reaches a prefix query"
    end

    # The fold law at the row: each gloss folds by its declared GLOSS
    # language (achemenet: English), never the Akkadian passage's fold.
    def test_the_row_folds_by_the_gloss_language
      passage = @catalog[:passages].where(urn: LEASE).first
      row = Index.row({ passage_id: passage[:id], language: passage[:language],
                        annotations_json: passage[:annotations_json] }, "achemenet")

      entries = GL.entries(passage[:annotations_json], "achemenet")
      assert_equal GL.fold(GL.line(entries), "achemenet"), row.fetch(:gloss)
      assert_equal "akk", passage[:language]
      assert_equal Indexer.language_token("akk"), row.fetch(:language), "--lang filters the TEXT language"
    end

    def test_language_and_source_sentinels_filter_inside_the_match
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      bhsa = Indexer.source_token("bhsa")
      assert_equal match_ids('"king"') & expected_ids("bhsa"), match_ids(%("king" AND source : ("#{bhsa}")))
      arc = match_ids(%("king" AND language : ("#{Indexer.language_token('arc')}")))
      assert_includes arc, passage_id(DAN_2_4)
      refute_includes arc, passage_id(JONAH_3_6)
      assert_includes match_ids(%("king" AND language : ("#{Indexer.language_token('akk')}"))), passage_id(LEASE)
    end

    def test_withdrawn_passages_stay_out
      id = passage_id(DAN_2_4)
      @catalog[:passages].where(id: id).update(withdrawn: true)
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      refute_includes indexed_ids, id
      assert_empty match_ids('"king" "eternity"')
    end

    def test_rebuild_is_idempotent
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      first = [indexed_ids, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal first, [indexed_ids, scope]
    end

    def test_a_source_refresh_reaches_the_rebuild_state_and_is_idempotent
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      id = passage_id(DAN_2_4)
      @catalog[:passages].where(id: id).update(withdrawn: true)

      2.times { Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "bhsa") }
      refreshed = [indexed_ids, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal [indexed_ids, scope], refreshed, "row identity: refresh == from-scratch rebuild"
      refute_includes match_ids('"king"'), id
    end

    def test_a_source_refresh_at_the_delta_grain_matches_the_rebuild
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      id = passage_id(JONAH_2_7)
      @catalog[:passages].where(id: id).update(annotations_json: '{"tokens":[{"form":"x","gloss":"crown"}]}')
      delta = Nabu::Store::IndexDelta.new
      delta.upsert(id, JONAH_2_7)

      Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "bhsa", delta: delta)

      assert_equal [id], match_ids('"crown"')
      refute_includes match_ids('"eternity"'), id
      refreshed = [indexed_ids, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      assert_equal [indexed_ids, scope], refreshed
    end

    def test_refresh_never_bootstraps_an_absent_lane
      assert_nil Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "bhsa")
      refute @fulltext.table_exists?(Index::TABLE)
    end

    def test_refresh_of_an_unregistered_source_is_a_no_op
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      before = [indexed_ids, scope]

      assert_nil Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "perseus")
      assert_equal before, [indexed_ids, scope]
    end

    def test_a_source_dropped_from_the_registry_loses_its_rows_and_scope_at_refresh
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "tlhdig",
                            registry_slugs: GL.slugs - ["tlhdig"])

      assert_empty indexed_ids & expected_ids("tlhdig")
      refute_includes scope.map(&:first), "tlhdig"
    end

    # -- the targeted builder: ONE source, no rebuild --

    def test_build_source_creates_the_lane_and_derives_one_slice
      count = Index.build_source!(catalog: @catalog, fulltext: @fulltext, slug: "achemenet")

      assert_equal expected_ids("achemenet").size, count
      assert_equal expected_ids("achemenet"), indexed_ids
      assert_equal [["achemenet", count]], scope

      (GL.slugs - ["achemenet"]).each { |slug| Index.build_source!(catalog: @catalog, fulltext: @fulltext, slug: slug) }
      Index.build_source!(catalog: @catalog, fulltext: @fulltext, slug: "bhsa")
      built = [indexed_ids, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      assert_equal [indexed_ids, scope], built, "per-source targeted builds == the whole-registry build"
    end

    def test_build_source_refuses_an_unregistered_source
      error = assert_raises(ArgumentError) do
        Index.build_source!(catalog: @catalog, fulltext: @fulltext, slug: "perseus")
      end
      assert_match(/not declared in Nabu::Query::TokenGlosses/, error.message)
    end

    # -- the Indexer seams: reference rebuild, sync refresh, stage reconcile --

    def test_the_reference_rebuild_builds_and_stamps_the_lane
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal expected_ids, indexed_ids
      assert_equal Indexer::STAGE_VERSIONS.fetch(Index::STAGE),
                   @fulltext[:stage_stamps].where(stage: Index::STAGE).get(:version)
    end

    def test_the_sync_refresh_carries_the_lane_slice
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      @catalog[:passages].where(id: passage_id(DAN_2_4)).update(withdrawn: true)

      Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "bhsa")

      assert_equal expected_ids, indexed_ids
    end

    def test_a_stale_stage_is_rederived_standalone_by_the_reconcile
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      @fulltext.drop_table(Index::TABLE)
      @fulltext[:stage_stamps].where(stage: Index::STAGE).delete

      redone, refusal, = Indexer.reconcile_stages!(catalog: @catalog, fulltext: @fulltext)

      assert_nil refusal
      assert_equal [Index::STAGE], redone
      assert_equal expected_ids, indexed_ids
    end
  end
end
