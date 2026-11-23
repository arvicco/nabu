# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::SourceAggregates (migration 054): the O(1) per-source
  # accounting. The counts ride the SourceStats maintainer's per-document
  # delta (same transaction), the fts_behind flag rides the Loader's
  # index-visible outcomes (same transaction), and the index refresh call
  # sites clear it. The load-bearing guards here: incremental == wholesale
  # == recounted truth (the sampled drift cross-check), idempotency, and
  # the rolled-back document leaving no mark.
  class SourceAggregatesTest < Minitest::Test
    include StoreTestDB

    AGG = Nabu::Store::SourceAggregates

    def setup
      @db = store_test_db
      @source = make_source("texts")
    end

    # -- helpers -------------------------------------------------------------

    def make_source(slug)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "nc")
    end

    def loader(source = @source, **)
      Nabu::Store::Loader.new(db: @db, source: source, **)
    end

    def passage(urn, seq, text: "words")
      Nabu::Passage.new(urn: urn, sequence: seq, language: "grc", text: text, text_normalized: text)
    end

    def document(urn, count, text: "words", metadata: {})
      doc = Nabu::Document.new(urn: urn, title: urn, language: "grc", canonical_path: "#{urn}.xml",
                               metadata: metadata)
      count.times { |i| doc << passage("#{urn}:#{i + 1}", i, text: "#{text} #{i}") }
      doc
    end

    def row(source = @source) = AGG.fetch(@db, source.id)

    def counts(source = @source) = [row(source).documents_count, row(source).passages_count]

    def raw_rows
      @db[AGG::TABLE].order(:source_id).select_map(%i[source_id documents_count passages_count fts_member_count
                                                      fts_behind last_index_refresh_at updated_at])
    end

    # incremental vs wholesale vs truth, at every waypoint.
    def assert_exact!(context)
      incremental = @db[AGG::TABLE].order(:source_id).select_map(%i[source_id documents_count passages_count])
      Nabu::Store::SourceStats.derive!(@db, note: "test wholesale")
      wholesale = @db[AGG::TABLE].order(:source_id).select_map(%i[source_id documents_count passages_count])
      assert_equal wholesale, incremental, "incremental vs wholesale drift #{context}"
      assert_empty AGG.drift(@db, Nabu::Store::Source.select_map(:id)), "truth drift #{context}"
    end

    # -- counts --------------------------------------------------------------

    def test_loads_maintain_counts_incrementally_and_match_wholesale_and_truth
      loader.load([document("u:a", 2), document("u:b", 3)])
      assert_equal [2, 5], counts
      assert_exact!("after insert")

      loader.load([document("u:a", 1, text: "revised")]) # revise a, sweep-withdraw b
      assert_equal [1, 1], counts
      assert_exact!("after revise + sweep")

      loader.load([document("u:a", 1, text: "revised"), document("u:b", 3)]) # restore b
      assert_equal [2, 4], counts
      assert_exact!("after restore")
    end

    def test_batch_mode_keeps_the_same_counts
      batch = loader(tx_batch: 2)
      batch.load([document("u:a", 2), document("u:b", 3), document("u:c", 1)])
      batch.load([document("u:a", 4, text: "new"), document("u:c", 1)])
      assert_equal [2, 5], counts
      assert_exact!("after the batch-mode braid")
    end

    def test_idempotent_reload_leaves_the_rows_untouched
      docs = [document("u:a", 2), document("u:b", 1)]
      loader.load(docs)
      AGG.index_refreshed!(@db, slug: @source.slug, members: 3)
      before = raw_rows

      report = loader.load(docs)

      assert_equal 2, report.skipped
      assert_equal before, raw_rows, "an all-skip reload writes nothing — no count move, no behind flag"
    end

    # -- fts_behind ----------------------------------------------------------

    def test_index_visible_load_marks_behind_and_a_refresh_clears_it
      loader.load([document("u:a", 2)])
      assert row.fts_behind, "a landed insert flags the slice behind in its own transaction"
      assert_nil row.fts_member_count

      AGG.index_refreshed!(@db, slug: @source.slug, members: 2)
      refute row.fts_behind
      assert_equal 2, row.fts_member_count
      refute_nil row.last_index_refresh_at

      loader.load([document("u:a", 2, text: "revised")])
      assert row.fts_behind, "a content revision flags it again"

      AGG.index_refreshed!(@db, slug: @source.slug, members: 2)
      loader.load([])
      assert row.fts_behind, "a full load's sweep withdrawal flags it"
    end

    def test_metadata_only_reconcile_does_not_mark_behind
      loader.load([document("u:a", 1)])
      AGG.index_refreshed!(@db, slug: @source.slug, members: 1)

      report = loader.load([document("u:a", 1, metadata: { "bu" => "x" })])

      assert_equal 1, report.updated
      assert_equal 0, report.revised
      refute row.fts_behind, "metadata moves nothing the index serves"
    end

    def test_a_rolled_back_document_leaves_no_mark
      other = make_source("other")
      loader(other).load([document("u:taken", 1)])
      AGG.index_refreshed!(@db, slug: @source.slug, members: 0)

      report = loader.load([document("u:taken", 1)]) # cross-source urn: constraint violation

      assert_equal 1, report.errored
      refute row.fts_behind, "the quarantined document's mark rolled back with it"

      loader.load([document("u:taken", 1), document("u:fresh", 1)], full: false)
      assert row.fts_behind, "the rollback re-armed the tracker: the next landed document marks"
    end

    def test_index_rebuilt_sets_membership_from_live_counts
      loader.load([document("u:a", 2)])
      loader(make_source("second")).load([document("u:z", 3)])

      AGG.index_rebuilt!(@db)

      membership = AGG.all(@db).values.sort_by(&:source_id).map { [_1.fts_member_count, _1.fts_behind] }
      assert_equal [[2, false], [3, false]], membership
      assert_equal({ documents_count: 2, passages_count: 5, fts_member_count: 5, behind_sources: 0 },
                   AGG.rollup(@db))
    end

    # -- the sampled drift cross-check ---------------------------------------

    def test_drift_cross_check_over_a_sample_of_sources
      sources = [@source] + %w[s2 s3 s4].map { make_source(_1) }
      sources.each_with_index do |source, i|
        loader(source).load((1..(i + 1)).map { |n| document("u:#{source.slug}:#{n}", n) })
      end
      sample = sources.map(&:id).sample(3, random: Random.new(7))
      assert_empty AGG.drift(@db, sample)

      victim = sample.first
      @db[AGG::TABLE].where(source_id: victim).update(passages_count: 999)
      drift = AGG.drift(@db, sample)
      truth = Nabu::Store::SourceStats.passage_truth(@db, victim)
      assert_equal [{ source_id: victim, column: :passages_count, stored: 999, truth: truth }], drift
    end

    # -- backfill ------------------------------------------------------------

    def test_backfill_recounts_and_reads_the_index_state
      loader.load([document("u:a", 2)])
      stale = make_source("stale")
      loader(stale).load([document("u:s", 1)])
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      Nabu::Store::Indexer.rebuild!(catalog: @db, fulltext: fulltext)
      loader(stale).load([document("u:s", 1), document("u:t", 4)]) # lands, never reindexed
      @db[AGG::TABLE].update(documents_count: 0, passages_count: 0, fts_member_count: nil, fts_behind: nil)

      assert_equal 2, AGG.backfill!(catalog: @db, fulltext: fulltext)

      fresh = row
      assert_equal [1, 2, 2, false], [fresh.documents_count, fresh.passages_count, fresh.fts_member_count,
                                      fresh.fts_behind]
      behind = row(stale)
      assert_equal [2, 5, true], [behind.documents_count, behind.passages_count, behind.fts_behind]
      assert_nil behind.fts_member_count, "a behind slice without a finish stamp has no honest membership"
    ensure
      fulltext&.disconnect
    end

    def test_backfill_without_an_index_file_marks_everything_with_passages_behind
      loader.load([document("u:a", 2)])
      AGG.backfill!(catalog: @db, fulltext: nil)
      assert_equal [0, true], [row.fts_member_count, row.fts_behind]
    end

    # -- migration + feature detection --------------------------------------

    def test_migration_copies_counts_from_source_stats
      db = Sequel.sqlite
      require "sequel/extensions/migration"
      Sequel::Migrator.run(db, Nabu::Store::MIGRATIONS_DIR, target: 53)
      source_id = db[:sources].insert(slug: "old", name: "Old", adapter_class: "T", license_class: "nc")
      db[:source_stats].insert(source_id: source_id, live_documents: 4, live_passages: 9,
                               updated_at: Time.now, note: "seed")

      Sequel::Migrator.run(db, Nabu::Store::MIGRATIONS_DIR)

      agg = AGG.fetch(db, source_id)
      assert_equal [4, 9], [agg.documents_count, agg.passages_count]
      assert_nil agg.fts_behind, "the fulltext columns stay honestly unknown until the backfill"
    ensure
      db&.disconnect
    end

    def test_loader_and_hooks_tolerate_a_catalog_without_the_table
      @db.drop_table(AGG::TABLE)
      assert_equal 1, loader.load([document("u:a", 1)]).added
      assert_nil AGG.index_refreshed!(@db, slug: @source.slug, members: 1)
      assert_nil AGG.index_rebuilt!(@db)
    end
  end
end
