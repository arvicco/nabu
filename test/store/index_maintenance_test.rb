# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Store
  # Nabu::Store::IndexMaintenance — the maintenance rail (the
  # incrementality review, R4): the ONE owner of corpus-scale index work.
  # It recomputes every stale-flagged aggregate, consolidates every fts
  # table's merge debt to the no-op probe, truncates the WAL, and reports
  # the structure gauges — announced, ledgered, and resumable: a killed run
  # leaves exactly the work it had not finished for the next run.
  class IndexMaintenanceTest < Minitest::Test
    include StoreTestDB

    Indexer = Nabu::Store::Indexer
    Stale = Nabu::Store::StaleAggregates
    Rail = Nabu::Store::IndexMaintenance

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @dir = Dir.mktmpdir("nabu-maintain")
      @ledger = Nabu::Store::Ledger.open!(File.join(@dir, "history.sqlite3"))
      @sources = %w[s lit].to_h do |slug|
        [slug, Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "open")]
      end
      @sources.each_value.with_index do |source, index|
        doc = Nabu::Store::Document.create(source_id: source.id, urn: "urn:d:#{source.slug}", title: "t",
                                           language: "grc", content_sha256: "x", revision: 1, withdrawn: false)
        Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:d:#{source.slug}:1", sequence: 0,
                                    language: "grc", text: "λογοσ #{index}", text_normalized: "λογοσ #{index}",
                                    content_sha256: "x", revision: 1, withdrawn: false, annotations_json: "{}")
      end
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def teardown
      @fulltext.disconnect
      @ledger.disconnect
      FileUtils.rm_rf(@dir)
    end

    def postings_of(slug) = @fulltext[Indexer::CHAR_POSTINGS_TABLE].where(source_id: @sources.fetch(slug).id)

    # Drift a source's postings and flag them, as an unsound delta would.
    def plant_stale_postings(slug)
      postings_of(slug).update(docs: 99)
      Stale.mark!(@fulltext, aggregate: Indexer::POSTINGS_AGGREGATE, scope: slug, reason: "planted")
    end

    # Planted merge debt: automerge off, one level-0 segment per committed
    # single-row insert — the shape positive merge commands consume.
    def plant_merge_debt(segments: 12)
      Indexer.apply_merge_settings(@fulltext, Indexer::TABLE, { "automerge" => 0 })
      segments.times do |i|
        @fulltext[Indexer::TABLE].insert(rowid: 1_000 + i, text_normalized: "debt #{i}",
                                         language: Indexer.language_token("grc"), source: Indexer.source_token("s"))
      end
    end

    def level_segments = Nabu::Store::FtsStructure.read(@fulltext, Indexer::TABLE).levels.map { |l| l[:segments].size }

    def run_rail(**) = Rail.run!(catalog: @catalog, fulltext: @fulltext, ledger: @ledger, **)

    def test_the_rail_recomputes_a_planted_stale_aggregate_and_clears_its_flag
      plant_stale_postings("s")
      report = run_rail

      assert_equal ["char_postings (s)"], report.recomputed
      refute Stale.stale?(@fulltext, aggregate: Indexer::POSTINGS_AGGREGATE, scope: "s")
      assert_equal [1], postings_of("s").exclude(char: "").select_map(:docs).uniq, "the recompute is exact"
    end

    def test_the_rail_consolidates_planted_merge_debt_to_the_no_op_probe
      plant_merge_debt
      assert_operator level_segments.max, :>=, Rail::DEBT_LEVEL_SEGMENTS, "the planted debt is real"

      report = run_rail

      assert_operator report.merge_chunks, :>=, 2, "at least one working chunk plus the no-op probe"
      assert_operator level_segments.max, :<, Rail::DEBT_LEVEL_SEGMENTS, "no level is left holding merge work"
      assert_nil Rail.debt_line(@fulltext, Indexer::TABLE)
    end

    def test_the_rail_truncates_the_wal_and_reports_the_gauges
      report = run_rail

      assert_equal 0, report.checkpoint[:busy]
      assert report.gauges_before.key?(Indexer::TABLE)
      assert report.gauges_after.key?(Indexer::TABLE)
    end

    def test_the_rail_ledgers_its_stages_under_its_own_kind
      plant_stale_postings("s")
      run_rail

      stages = @ledger[Nabu::Store::StageTimings::TABLE].where(kind: Rail::KIND).select_map(%i[scope stage])
      assert_includes stages, %w[s recompute_char_postings]
      assert_includes stages, %w[passages_fts fts_merge]
    end

    # Resumability: a run killed after its first recompute leaves only the
    # unfinished flag; the next run continues there instead of restarting.
    def test_a_killed_run_resumes_with_only_the_unfinished_work
      plant_stale_postings("s")
      plant_stale_postings("lit")
      calls = []
      original = Indexer.method(:recompute_char_postings!)
      Indexer.define_singleton_method(:recompute_char_postings!) do |**kw|
        calls << kw[:slug]
        raise "killed" if calls.size == 2

        original.call(**kw)
      end
      begin
        assert_raises(RuntimeError) { run_rail }
        assert_equal 1, Stale.all(@fulltext).size, "the finished recompute's flag is cleared, the other stands"
        calls.clear
        run_rail
      ensure
        Indexer.define_singleton_method(:recompute_char_postings!, original)
      end

      assert_equal 1, calls.size, "the second run redoes nothing the first finished"
      assert_empty Stale.all(@fulltext)
    end

    def test_a_census_recompute_also_settles_the_closure
      Stale.mark!(@fulltext, aggregate: Indexer::CENSUS_AGGREGATE, scope: "corpus", reason: "planted")
      Stale.mark!(@fulltext, aggregate: Nabu::Store::ReflexRootsIndexer::CLOSURE_AGGREGATE, scope: "corpus",
                             reason: "planted")
      report = run_rail

      assert_equal ["lemma_census (corpus)"], report.recomputed, "the corpus pass settles the closure flag too"
      assert_empty Stale.all(@fulltext)
    end

    def test_an_unknown_flag_is_reported_never_guessed
      Stale.mark!(@fulltext, aggregate: "mystery", scope: "corpus", reason: "planted")

      error = assert_raises(Nabu::Error) { run_rail }
      assert_match(/no recompute for stale aggregate "mystery"/, error.message)
    end
  end
end
