# frozen_string_literal: true

require "test_helper"

# The annotations lane of the fulltext index (Store::AnnotationIndex): one
# contentless FTS5 row per live passage whose ANNOTATIONS carry a declared
# searchable layer (Nabu::AnnotationKeys), keyed by the catalog passage
# id, folded with the passage's OWN language. Built from the real cantus
# and korpus16 fixtures loaded through the real Loader.
module Store
  class AnnotationIndexTest < Minitest::Test
    include StoreTestDB

    Index = Nabu::Store::AnnotationIndex
    Indexer = Nabu::Store::Indexer
    Keys = Nabu::AnnotationKeys

    # Cantus 455843: the manuscript writes "presul idem kathedr…", Cantus'
    # standardized text "praesul idem cathedr…".
    PRESUL = "urn:nabu:cantus:455843:1"
    # Dalmatin's Bible, folio I,56a — the "Sobbota ali prasnik." gloss.
    BIBLE_PAGE = "urn:nabu:korpus16:58:200"

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      Nabu::TestSupport.load_annotation_corpus(@catalog)
      # An unregistered source with a "notes"-shaped key: never indexed.
      other = Nabu::Store::Source.create(slug: "perseus", name: "P", adapter_class: "TestAdapter",
                                         license_class: "open")
      doc = Nabu::Store::Document.create(source_id: other.id, urn: "urn:x:1", title: "t", language: "lat",
                                         content_sha256: "x", revision: 1)
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:x:1:1", sequence: 0, language: "lat",
                                  text: "arma", text_normalized: "arma", content_sha256: "x", revision: 1,
                                  annotations_json: '{"notes":["praesul prasnik"]}')
    end

    def teardown
      @fulltext.disconnect
    end

    def expected_ids(slug = nil)
      slugs = slug ? [slug] : Keys.slugs
      rows = @catalog[:passages].join(:documents, id: :document_id).join(:sources, id: :source_id)
                                .where(Sequel[:sources][:slug] => slugs, Sequel[:passages][:withdrawn] => false,
                                       Sequel[:documents][:withdrawn] => false)
                                .select(Sequel[:passages][:id], Sequel[:passages][:annotations_json],
                                        Sequel[:sources][:slug])
                                .all
      rows.reject { |row| Keys.layers(row[:annotations_json], Keys.specs_for(row[:slug])).empty? }
          .map { |row| row[:id] }.sort
    end

    def indexed_ids = @fulltext[Index::TABLE].select_order_map(:rowid)

    def scope = @fulltext[Index::SCOPE_TABLE].order(:slug).select_map(%i[slug passages])

    def match_ids(expression)
      @fulltext[Index::TABLE].where(Sequel.lit("passages_annotations MATCH ?", expression)).select_order_map(:rowid)
    end

    def passage_id(urn) = @catalog[:passages].where(urn: urn).get(:id)

    def test_rebuild_indexes_every_layer_bearing_live_passage_and_records_its_scope
      result = Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal expected_ids, indexed_ids
      assert_equal expected_ids.size, result.fetch(:passages)
      assert_equal 2, result.fetch(:sources)
      assert_equal [["cantus", expected_ids("cantus").size], ["korpus16", expected_ids("korpus16").size]], scope
      assert_operator expected_ids("cantus").size, :>, 20, "fixture reality: most chants carry a standardized text"
      assert_equal [passage_id(BIBLE_PAGE)], expected_ids("korpus16"), "the notes ride the Bible page alone"
    end

    # The use case: the standardized spelling finds the manuscript passage
    # the main index (which holds only the manuscript's "presul") misses.
    def test_the_standardized_spelling_finds_the_manuscript_passage
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal "manuscript", JSON.parse(@catalog[:passages].where(urn: PRESUL).get(:annotations_json))["text_form"]
      refute_includes @catalog[:passages].where(urn: PRESUL).get(:text_normalized), "praesul"
      assert_equal [passage_id(PRESUL)], match_ids('"praesul"')
      assert_includes match_ids('"pretiosa"'), passage_id("urn:nabu:cantus:455847:1")
    end

    # The fold law: the layer folds by the PASSAGE language, so Latin's
    # j→i rule meets the index — "jam" (standardized) is stored as "iam".
    def test_layers_fold_with_the_passage_language
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      jam = passage_id("urn:nabu:cantus:455850:1")
      assert_includes match_ids('"iam"'), jam
      refute_includes match_ids('"jam"'), jam, "the generic fold would have kept j"
    end

    def test_korpus16_margin_notes_are_searchable
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal [passage_id(BIBLE_PAGE)], match_ids('"sobbota ali prasnik"')
      assert_equal [passage_id(BIBLE_PAGE)], match_ids('"kadilu"')
    end

    def test_language_and_source_sentinels_filter_inside_the_match
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      cantus = Indexer.source_token("cantus")
      korpus = Indexer.source_token("korpus16")
      refute_empty match_ids(%("praesul" AND source : ("#{cantus}")))
      assert_empty match_ids(%("praesul" AND source : ("#{korpus}")))
      refute_empty match_ids(%("kadilu" AND language : ("#{Indexer.language_token('sl')}")))
      assert_empty match_ids(%("kadilu" AND language : ("#{Indexer.language_token('lat')}")))
    end

    def test_unregistered_sources_and_placeholders_are_never_indexed
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      refute_includes indexed_ids, passage_id("urn:x:1:1")
      refute_includes scope.map(&:first), "perseus"
      assert_empty match_ids('"lacuna"')
    end

    def test_withdrawn_passages_stay_out
      id = passage_id(PRESUL)
      @catalog[:passages].where(id: id).update(withdrawn: true)
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      refute_includes indexed_ids, id
      assert_empty match_ids('"praesul"')
    end

    def test_rebuild_is_idempotent
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      first = [indexed_ids, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal first, [indexed_ids, scope]
    end

    def test_a_source_refresh_reaches_the_rebuild_state_and_is_idempotent
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      id = passage_id(PRESUL)
      @catalog[:passages].where(id: id).update(withdrawn: true)

      2.times { Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "cantus") }
      refreshed = [indexed_ids, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal [indexed_ids, scope], refreshed, "row identity: refresh == from-scratch rebuild"
      refute_includes match_ids('"praesul"'), id
    end

    def test_a_source_refresh_at_the_delta_grain_matches_the_rebuild
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      id = passage_id(PRESUL)
      @catalog[:passages].where(id: id).update(annotations_json: '{"standardized":"Tamdiu quippe antistes"}')
      delta = Nabu::Store::IndexDelta.new
      delta.upsert(id, PRESUL)

      Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "cantus", delta: delta)

      assert_includes match_ids('"antistes"'), id
      refute_includes match_ids('"praesul"'), id
      refreshed = [indexed_ids, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      assert_equal [indexed_ids, scope], refreshed
    end

    def test_refresh_never_bootstraps_an_absent_lane
      assert_nil Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "cantus")
      refute @fulltext.table_exists?(Index::TABLE)
    end

    def test_a_source_dropped_from_the_registry_loses_its_rows_and_scope_at_refresh
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "korpus16", registry_slugs: ["cantus"])

      assert_empty indexed_ids & expected_ids("korpus16")
      assert_equal ["cantus"], scope.map(&:first)
    end

    # -- the targeted builder: ONE source, no rebuild --

    def test_build_source_creates_the_lane_and_derives_one_slice
      count = Index.build_source!(catalog: @catalog, fulltext: @fulltext, slug: "korpus16")

      assert_equal 1, count
      assert_equal expected_ids("korpus16"), indexed_ids
      assert_equal [["korpus16", 1]], scope

      Index.build_source!(catalog: @catalog, fulltext: @fulltext, slug: "cantus")
      Index.build_source!(catalog: @catalog, fulltext: @fulltext, slug: "cantus")
      built = [indexed_ids, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      assert_equal [indexed_ids, scope], built, "two targeted builds == the whole-registry build"
    end

    def test_build_source_refuses_an_unregistered_source
      error = assert_raises(ArgumentError) do
        Index.build_source!(catalog: @catalog, fulltext: @fulltext, slug: "perseus")
      end
      assert_match(/not declared in Nabu::AnnotationKeys/, error.message)
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
      @catalog[:passages].where(id: passage_id(PRESUL)).update(withdrawn: true)

      Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "cantus")

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
