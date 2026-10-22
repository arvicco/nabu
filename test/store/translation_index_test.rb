# frozen_string_literal: true

require "test_helper"

# The translations lane of the fulltext index (Store::TranslationIndex):
# one contentless FTS5 row per live passage whose ANNOTATIONS carry a
# registered translation layer (Nabu::TranslationKeys), keyed by the
# catalog passage id. Built from real fixtures loaded through the real
# Loader — the registry keys are exercised against actual adapter output.
module Store
  class TranslationIndexTest < Minitest::Test
    include StoreTestDB

    Index = Nabu::Store::TranslationIndex
    Indexer = Nabu::Store::Indexer

    SOURCES = {
      "coptic-scriptorium" => Nabu::Adapters::CopticScriptorium,
      "cdli" => Nabu::Adapters::Cdli,
      "hittite-glossed" => Nabu::Adapters::HittiteGlossed
    }.freeze

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @sources = SOURCES.to_h do |slug, adapter|
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: adapter.name,
                                            license_class: "open")
        Nabu::Store::Loader.new(db: @catalog, source: source)
                           .load_from(adapter.new, workdir: Nabu::TestSupport.fixtures(slug), full: true)
        [slug, source]
      end
      # An unregistered source with a "translation"-shaped key: never indexed.
      other = Nabu::Store::Source.create(slug: "perseus", name: "P", adapter_class: "TestAdapter",
                                         license_class: "open")
      doc = Nabu::Store::Document.create(source_id: other.id, urn: "urn:x:1", title: "t", language: "grc",
                                         content_sha256: "x", revision: 1)
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:x:1:1", sequence: 0, language: "grc",
                                  text: "λόγος", text_normalized: "λογοσ", content_sha256: "x", revision: 1,
                                  annotations_json: '{"translation":"two brothers"}')
    end

    def teardown
      @fulltext.disconnect
    end

    # Live passages per registered source that carry at least one layer —
    # the expected row population, computed from the catalog directly.
    def expected_ids(slug = nil)
      slugs = slug ? [slug] : SOURCES.keys
      @catalog[:passages].join(:documents, id: :document_id).join(:sources, id: :source_id)
                         .where(Sequel[:sources][:slug] => slugs, Sequel[:passages][:withdrawn] => false,
                                Sequel[:documents][:withdrawn] => false)
                         .select(Sequel[:passages][:id], Sequel[:passages][:annotations_json],
                                 Sequel[:sources][:slug])
                         .all
                         .reject do |row|
                           Nabu::TranslationKeys.layers(row[:annotations_json],
                                                        Nabu::TranslationKeys.specs_for(row[:slug])).empty?
                         end
                         .map { |row| row[:id] }.sort
    end

    def indexed_ids = @fulltext[Index::TABLE].select_order_map(:rowid)

    def scope = @fulltext[Index::SCOPE_TABLE].order(:slug).select_map(%i[slug passages])

    def match_ids(expression)
      @fulltext[Index::TABLE].where(Sequel.lit("passages_translations MATCH ?", expression))
                             .select_order_map(:rowid)
    end

    def passage_id(urn) = @catalog[:passages].where(urn: urn).get(:id)

    def test_rebuild_indexes_every_layer_bearing_live_passage_and_records_its_scope
      result = Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal expected_ids, indexed_ids
      assert_equal expected_ids.size, result.fetch(:passages)
      assert_equal SOURCES.keys.sort.map { |slug| [slug, expected_ids(slug).size] }, scope
      assert_operator expected_ids("coptic-scriptorium").size, :>, 100, "fixture reality: the coptic layer is dense"
    end

    def test_translation_text_is_searchable_and_keyed_to_the_original_passage
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal [passage_id("urn:nabu:coptic-scriptorium:ap.100.monbeg:1.1")],
                   match_ids('"brothers according to the flesh"')
      # German word glosses (hittite-glossed trans_de), diacritic-folded both sides.
      assert_includes match_ids('"wettergott"'), passage_id("urn:nabu:hittite-glossed:ibot.1.30+:l2")
      assert_includes match_ids('"konig"'), passage_id("urn:nabu:hittite-glossed:ibot.1.30+:l1")
      # The ATF tr.en lane (cdli).
      assert_includes match_ids('"merodach"'), passage_id("urn:nabu:cdli:p519727:a:2'")
      assert_empty match_ids('"μηνιν"'), "original-language text never enters the translations lane"
    end

    def test_language_and_source_sentinels_filter_inside_the_match
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      cdli = Indexer.source_token("cdli")
      coptic = Indexer.source_token("coptic-scriptorium")
      refute_empty match_ids(%("one" AND source : ("#{cdli}")))
      assert_empty match_ids(%("merodach" AND source : ("#{coptic}")))
      assert_empty match_ids(%("brothers" AND language : ("#{Indexer.language_token('akk')}")))
      refute_empty match_ids(%("brothers" AND language : ("#{Indexer.language_token('cop')}")))
    end

    def test_unregistered_sources_are_never_indexed
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      refute_includes indexed_ids, passage_id("urn:x:1:1")
      refute_includes scope.map(&:first), "perseus"
    end

    def test_withdrawn_passages_and_documents_stay_out
      id = passage_id("urn:nabu:coptic-scriptorium:ap.100.monbeg:1.1")
      @catalog[:passages].where(id: id).update(withdrawn: true)
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      refute_includes indexed_ids, id
      assert_empty match_ids('"brothers according to the flesh"')
    end

    def test_rebuild_is_idempotent
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      first = [indexed_ids, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal first, [indexed_ids, scope]
    end

    def test_a_source_refresh_reaches_the_rebuild_state_and_is_idempotent
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      id = passage_id("urn:nabu:coptic-scriptorium:ap.100.monbeg:1.1")
      @catalog[:passages].where(id: id).update(withdrawn: true)

      2.times { Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "coptic-scriptorium") }
      refreshed = [indexed_ids, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)

      assert_equal [indexed_ids, scope], refreshed, "row identity: refresh == from-scratch rebuild"
      refute_includes match_ids('"brothers"'), id
    end

    def test_a_source_refresh_at_the_delta_grain_matches_the_rebuild
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      id = passage_id("urn:nabu:coptic-scriptorium:ap.100.monbeg:1.2")
      @catalog[:passages].where(id: id)
                         .update(annotations_json: '{"translation":"One of them was a hermit."}')
      delta = Nabu::Store::IndexDelta.new
      delta.upsert(id, "urn:nabu:coptic-scriptorium:ap.100.monbeg:1.2")

      Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "coptic-scriptorium", delta: delta)

      assert_equal [id], match_ids('"hermit"')
      refute_includes match_ids('"ascetic"'), id
      refreshed = [indexed_ids, scope]
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      assert_equal [indexed_ids, scope], refreshed
    end

    def test_refresh_never_bootstraps_an_absent_lane
      assert_nil Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "cdli")
      refute @fulltext.table_exists?(Index::TABLE)
    end

    def test_refresh_of_an_unregistered_out_of_scope_source_is_a_no_op
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      before = [indexed_ids, scope]

      assert_nil Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "perseus")
      assert_equal before, [indexed_ids, scope]
    end

    def test_a_source_dropped_from_the_registry_loses_its_rows_and_scope_at_refresh
      Index.rebuild!(catalog: @catalog, fulltext: @fulltext)
      cdli_ids = expected_ids("cdli")

      Index.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "cdli", registry_slugs: [])

      assert_empty indexed_ids & cdli_ids
      refute_includes scope.map(&:first), "cdli"
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
      id = passage_id("urn:nabu:coptic-scriptorium:ap.100.monbeg:1.1")
      @catalog[:passages].where(id: id).update(withdrawn: true)

      Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "coptic-scriptorium")

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
