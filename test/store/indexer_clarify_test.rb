# frozen_string_literal: true

require "test_helper"

# The clarify lane of the fulltext index (nabu_clarify's precompiled
# backing): one entry per live document title, source, dictionary headword,
# and gazetteer place, with its names (primary + aliases) folded for a
# B-tree prefix lane, an FTS5 token lane, and an FTS5 trigram lane. Built
# by the reference rebuild, refreshed per source at sync, re-derivable
# standalone (the stage reconcile + `rake index:clarify`).
module Store
  class IndexerClarifyTest < Minitest::Test
    include StoreTestDB

    Indexer = Nabu::Store::Indexer

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @perseus = Nabu::Store::Source.create(slug: "perseus", name: "Perseus Digital Library",
                                            adapter_class: "TestAdapter", license_class: "open")
      @private = Nabu::Store::Source.create(slug: "adhoc", name: "Ad hoc", adapter_class: "TestAdapter",
                                            license_class: "research_private")
    end

    def teardown
      @fulltext.disconnect
    end

    def document(urn, title:, source: @perseus, withdrawn: false)
      doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: title, language: "grc",
                                         content_sha256: "x", revision: 1, withdrawn: withdrawn)
      Nabu::Store::Passage.create(document_id: doc.id, urn: "#{urn}:1.1", sequence: 0, language: "grc",
                                  text: "μῆνιν ἄειδε", text_normalized: "μηνιν αειδε",
                                  annotations_json: "{}", content_sha256: "x", revision: 1)
      doc
    end

    def seed
      document("urn:cts:greekLit:tlg0012.tlg001.perseus-grc2", title: "Ἰλιάς")
      document("urn:cts:greekLit:tlg0012.tlg002.perseus-grc2", title: "Odyssey")
      document("urn:cts:greekLit:tlg0012.tlg003.gone", title: "Withdrawn Hymn", withdrawn: true)
      document("urn:nabu:adhoc:notes", title: "Private notes", source: @private)
      shelf = @catalog[:dictionaries].insert(source_id: @perseus.id, slug: "lsj", title: "LSJ", language: "grc")
      @catalog[:dictionary_entries].insert(dictionary_id: shelf, urn: "urn:nabu:dict:lsj:logos",
                                           entry_id: "logos", key_raw: "λόγος", headword: "λόγος",
                                           headword_folded: "λογοσ", body: "word", content_sha256: "x")
      @catalog[:place_index].insert(gazetteer: "pleiades", place_id: "462281", title: "Lilybaeum",
                                    place_types_json: "[]", time_periods_json: "[]", position: 0)
      @catalog[:place_index_names].insert(gazetteer: "pleiades", place_id: "462281", name_key: "marsala")
    end

    def entries = @fulltext[Indexer::CLARIFY_TABLE]

    def snapshot
      entries.order(:type, :key).select_map(%i[type key name source license_class])
    end

    def test_the_reference_rebuild_derives_every_typed_entry
      seed
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

      rows = entries.to_hash(:key)
      iliad = rows.fetch("urn:cts:greekLit:tlg0012.tlg001.perseus-grc2")
      assert_equal %w[document Ἰλιάς perseus open grc],
                   iliad.values_at(:type, :name, :source, :license_class, :language)
      assert_equal ["source", "Perseus Digital Library"],
                   rows.fetch("perseus").values_at(:type, :name)
      assert_equal %w[lemma λόγος perseus], rows.fetch("urn:nabu:dict:lsj:logos").values_at(:type, :name, :source)
      assert_equal %w[place Lilybaeum pleiades], rows.fetch("pleiades:462281").values_at(:type, :name, :source)
      refute rows.key?("urn:cts:greekLit:tlg0012.tlg003.gone"), "withdrawn documents never enter"
      assert_equal "research_private", rows.fetch("urn:nabu:adhoc:notes")[:license_class],
                   "restricted entries are stored WITH their class — the reader gates them"
    end

    def test_names_are_folded_with_primaries_and_aliases_marked
      seed
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      names = @fulltext[Indexer::CLARIFY_NAMES_TABLE]
      iliad = entries.where(key: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2").get(:id)
      assert_equal([["ιλιασ", true]],
                   names.where(entry_id: iliad).select_map(%i[folded is_primary]).map do |f, p|
                     [f, [true, 1].include?(p)]
                   end)
      perseus = entries.where(key: "perseus").get(:id)
      assert_equal({ "perseus digital library" => true, "perseus" => false },
                   names.where(entry_id: perseus).select_map(%i[folded is_primary])
                        .to_h { |f, p| [f, [true, 1].include?(p)] })
      place = entries.where(key: "pleiades:462281").get(:id)
      assert_includes names.where(entry_id: place).select_map(:folded), "marsala", "gazetteer name keys are aliases"
      assert_equal "ιλιασ", Indexer.clarify_fold("  Ἰλιάς "), "the one fold both sides share"
    end

    def test_refresh_source_rederives_the_slice_row_identically
      seed
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      document("urn:cts:greekLit:tlg0012.tlg004.new", title: "Batrachomyomachia")
      @catalog[:documents].where(urn: "urn:cts:greekLit:tlg0012.tlg002.perseus-grc2").update(withdrawn: true)
      Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "perseus")
      refreshed = snapshot

      fresh = Nabu::Store.connect_fulltext("sqlite::memory:")
      Indexer.rebuild!(catalog: @catalog, fulltext: fresh)
      assert_equal fresh[Indexer::CLARIFY_TABLE].order(:type, :key).select_map(%i[type key name source license_class]),
                   refreshed, "the sync-time slice equals a from-scratch derivation"
      assert_includes refreshed.map { |row| row[1] }, "urn:cts:greekLit:tlg0012.tlg004.new"
    ensure
      fresh&.disconnect
    end

    def test_refresh_source_leaves_a_pre_lane_index_alone
      seed
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      Indexer.drop_clarify!(@fulltext)
      assert Indexer.incremental_ready?(@fulltext), "the lane is not an incremental prerequisite"
      Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "perseus")
      refute @fulltext.table_exists?(Indexer::CLARIFY_TABLE),
             "a sync never bootstraps the corpus-wide lane — the reconcile/rake path does"
    end

    def test_the_stage_reconciles_standalone_and_the_rake_path_stamps_it
      seed
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      Indexer.drop_clarify!(@fulltext)
      @fulltext[:stage_stamps].where(stage: "clarify").delete
      assert_includes Indexer.stale_stages(@fulltext), "clarify"

      redone, refusal, = Indexer.reconcile_stages!(catalog: @catalog, fulltext: @fulltext)
      assert_nil refusal
      assert_equal ["clarify"], redone
      assert_operator entries.count, :>, 0

      Indexer.drop_clarify!(@fulltext)
      summary = Indexer.rebuild_clarify!(catalog: @catalog, fulltext: @fulltext, stamp: true)
      assert_equal entries.count, summary.fetch(:entries)
      assert_empty Indexer.stale_stages(@fulltext)
      refute_nil @fulltext[Indexer::CLARIFY_META_TABLE].get(:built_at)
    end
  end
end
