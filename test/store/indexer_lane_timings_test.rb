# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The index core's tail lanes in the stage ledger: the slice refresh
# (Indexer.refresh_source!) ledgers each lane that did work — clarify,
# translations, token glosses, annotations, gloss lines — under kind
# "sync", scope the source, rows = the count the lane returned; a
# hands-off lane (a source outside its registry) records nothing. The
# reference rebuild (Indexer.rebuild!) profiles the same five lanes as
# corpus sub-stages. A bulk slice's final WAL reclaim is ledgered too.
# Recording only: every lane's rows and the announced stage lines are the
# same with and without a ledger. Real fixtures through the real Loader.
module Store
  class IndexerLaneTimingsTest < Minitest::Test
    include StoreTestDB

    Indexer = Nabu::Store::Indexer
    Timings = Nabu::Store::StageTimings

    # coptic-scriptorium carries the translations + annotations layers;
    # bhsa the token glosses (glosses + gloss lines).
    SOURCES = {
      "coptic-scriptorium" => Nabu::Adapters::CopticScriptorium,
      "bhsa" => Nabu::Adapters::Bhsa
    }.freeze
    LANE_STAGES = %w[clarify_slice translations_slice glosses_slice annotations_slice gloss_lines_slice].freeze

    def setup
      @dir = Dir.mktmpdir("nabu-lane-timings")
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      SOURCES.each do |slug, adapter|
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: adapter.name,
                                            license_class: "open")
        Nabu::Store::Loader.new(db: @catalog, source: source)
                           .load_from(adapter.new, workdir: Nabu::TestSupport.fixtures(slug), full: true)
      end
      # A source in no lane registry: every registry lane is hands-off.
      other = Nabu::Store::Source.create(slug: "plain", name: "P", adapter_class: "TestAdapter",
                                         license_class: "open")
      doc = Nabu::Store::Document.create(source_id: other.id, urn: "urn:x:1", title: "t", language: "grc",
                                         content_sha256: "x", revision: 1)
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:x:1:1", sequence: 0, language: "grc",
                                  text: "λόγος", text_normalized: "λογοσ", content_sha256: "x", revision: 1)
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def teardown
      @fulltext.disconnect
      @ledger&.disconnect
      FileUtils.rm_rf(@dir)
    end

    def ledger
      @ledger ||= Nabu::Store::Ledger.open!(File.join(@dir, "history.sqlite3"))
    end

    def lane_rows(slug)
      ledger[Timings::TABLE].where(kind: "sync", scope: slug, stage: LANE_STAGES).order(:id)
                            .select_map(%i[stage rows])
    end

    def refresh!(slug, **)
      Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: slug, **)
    end

    def scope_count(table, slug, column = :passages)
      @fulltext[table].where(slug: slug).get(column)
    end

    def test_each_lane_that_did_work_records_its_returned_count
      refresh!("coptic-scriptorium", ledger: ledger)
      refresh!("bhsa", ledger: ledger)

      coptic = lane_rows("coptic-scriptorium").to_h
      assert_equal %w[annotations_slice clarify_slice translations_slice], coptic.keys.sort,
                   "coptic-scriptorium carries translations + annotations, no token glosses"
      assert_equal scope_count(Nabu::Store::TranslationIndex::SCOPE_TABLE, "coptic-scriptorium"),
                   coptic["translations_slice"]
      assert_equal scope_count(Nabu::Store::AnnotationIndex::SCOPE_TABLE, "coptic-scriptorium"),
                   coptic["annotations_slice"]
      assert_equal @fulltext[Indexer::CLARIFY_TABLE].where(source: "coptic-scriptorium").count,
                   coptic["clarify_slice"]

      bhsa = lane_rows("bhsa").to_h
      assert_equal %w[clarify_slice gloss_lines_slice glosses_slice], bhsa.keys.sort
      assert_equal scope_count(Nabu::Store::GlossIndex::SCOPE_TABLE, "bhsa", :words), bhsa["glosses_slice"]
      assert_equal scope_count(Nabu::Store::GlossLineIndex::SCOPE_TABLE, "bhsa"), bhsa["gloss_lines_slice"]
      assert(bhsa.values.all?(&:positive?), "every recorded lane did real work: #{bhsa}")
    end

    def test_a_hands_off_lane_records_nothing
      refresh!("plain", ledger: ledger)

      assert_equal %w[clarify_slice], lane_rows("plain").map(&:first),
                   "only the clarify lane serves every source; the registry lanes returned nil"
    end

    # Recording only: the lanes' rows and the announced stage lines are
    # identical with and without a ledger (the lane stages announce nothing).
    def test_the_recorder_leaves_the_lanes_and_the_announcements_unchanged
      runs = [nil, ledger].map do |mode|
        @fulltext.disconnect
        @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
        Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
        stages = []
        progress = Nabu::ProgressReporter.new(on_stage: ->(label, _eta) { stages << label })
        %w[coptic-scriptorium bhsa plain].each { |slug| refresh!(slug, ledger: mode, progress: progress) }
        [lane_state, stages.grep_v(/merge|fts write path/)]
      end

      assert_equal runs.first, runs.last
    end

    def test_the_reference_rebuild_profiles_the_five_tail_lanes
      profile = Nabu::RebuildProfile.new
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, profile: profile)

      assert_empty %i[clarify translations glosses annotations gloss_lines] - profile.corpus_stages,
                   "each tail lane is its own measured corpus stage"
    end

    def test_the_index_eta_umbrella_sums_every_timed_index_sub_stage
      source = File.read(File.expand_path("../../lib/nabu/store/indexer.rb", __dir__))
      timed = source.scan(/timed\(profile, :(\w+)\)/).flatten

      assert_equal timed.sort, Nabu::Rebuild::INDEX_ETA_STAGES.sort,
                   "the fulltext-index estimate must price every sub-stage rebuild! times"
    end

    def test_a_bulk_slice_records_its_final_wal_checkpoint
      file_fulltext = Nabu::Store.connect_fulltext(File.join(@dir, "fulltext.sqlite3"))
      Indexer.rebuild!(catalog: @catalog, fulltext: file_fulltext)
      Indexer.refresh_source!(catalog: @catalog, fulltext: file_fulltext, slug: "bhsa", ledger: ledger,
                              bulk_threshold: 1)

      row = Timings.last(ledger, kind: "sync", scope: "bhsa", stage: "wal_checkpoint")
      refute_nil row, "the bulk run's WAL reclaim lands in the ledger"
      assert_operator row[:rows], :>=, 0, "rows = the frames the TRUNCATE checkpoint moved"
      refresh_plain = Indexer.refresh_source!(catalog: @catalog, fulltext: file_fulltext, slug: "plain",
                                              ledger: ledger)
      assert_operator refresh_plain, :>, 0
      assert_nil Timings.last(ledger, kind: "sync", scope: "plain", stage: "wal_checkpoint"),
                 "a non-bulk slice has no final reclaim to record"
    ensure
      file_fulltext&.disconnect
    end

    private

    # Every tail lane's rows, id-independent (the clarify ids are minted).
    def lane_state
      {
        clarify: @fulltext[Indexer::CLARIFY_TABLE].select_order_map(%i[type key name source]),
        translations: @fulltext[Nabu::Store::TranslationIndex::TABLE].select_order_map(:rowid),
        glosses: @fulltext[Nabu::Store::GlossIndex::SCOPE_TABLE].select_order_map(%i[slug words tokens]),
        annotations: @fulltext[Nabu::Store::AnnotationIndex::TABLE].select_order_map(:rowid),
        gloss_lines: @fulltext[Nabu::Store::GlossLineIndex::TABLE].select_order_map(:rowid)
      }
    end
  end
end
