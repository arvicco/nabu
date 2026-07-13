# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Store
  # The links journal (P16-1): db/links.sqlite3, batch-mined edges that
  # survive `nabu rebuild`. Its own migration track (db/links_migrate + its
  # own schema_info — the ledger_migrate precedent), urn-keyed edges, and the
  # supersede/refresh write discipline that keeps at most one edge per
  # unordered pair per kind.
  class LinksJournalTest < Minitest::Test
    def setup
      @db = Nabu::Store::LinksJournal.connect("sqlite::memory:")
      Nabu::Store::LinksJournal.migrate!(@db)
    end

    def teardown
      @db.disconnect
    end

    def record_run(producer: "parallels", scope: "urn:h", params: { min_score: 0.05 })
      Nabu::Store::LinksJournal.record_run!(
        @db, producer: producer, scope: scope, params: params, code_version: "test/1"
      )
    end

    def write_edge(from:, to:, run_id:, kind: "parallel", score: 1.0)
      Nabu::Store::LinksJournal.write_edge!(
        @db, from_urn: from, to_urn: to, kind: kind, score: score, run_id: run_id
      )
    end

    # -- schema ---------------------------------------------------------------

    def test_migrations_create_both_tables
      %i[links link_runs].each do |table|
        assert @db.table_exists?(table), "expected journal table #{table} to exist"
      end
    end

    def test_edges_are_urn_keyed_with_run_provenance
      run_id = record_run
      write_edge(from: "urn:a:1", to: "urn:b:1", run_id: run_id, score: 2.5)
      edge = @db[:links].first
      assert_equal "urn:a:1", edge[:from_urn]
      assert_equal "urn:b:1", edge[:to_urn]
      assert_equal "parallel", edge[:kind]
      assert_in_delta 2.5, edge[:score]
      assert_equal run_id, edge[:run_id]
      run = @db[:link_runs].first(id: run_id)
      assert_equal "parallels", run[:producer]
      assert_equal({ "min_score" => 0.05 }, JSON.parse(run[:params_json]))
      assert_equal "test/1", run[:code_version]
    end

    def test_duplicate_pair_same_direction_is_rejected_by_the_unique_index
      run_id = record_run
      @db[:links].insert(from_urn: "urn:a:1", to_urn: "urn:b:1", kind: "parallel",
                         score: 1.0, run_id: run_id, created_at: Time.now)
      assert_raises(Sequel::UniqueConstraintViolation) do
        @db[:links].insert(from_urn: "urn:a:1", to_urn: "urn:b:1", kind: "parallel",
                           score: 2.0, run_id: run_id, created_at: Time.now)
      end
    end

    # -- write_edge!: one edge per unordered pair per kind ---------------------

    def test_write_edge_refreshes_the_same_direction_instead_of_duplicating
      run_a = record_run(scope: "urn:a")
      run_b = record_run(scope: "urn:wider")
      assert_equal :inserted, write_edge(from: "urn:a:1", to: "urn:b:1", run_id: run_a, score: 1.0)
      assert_equal :refreshed, write_edge(from: "urn:a:1", to: "urn:b:1", run_id: run_b, score: 3.0)
      assert_equal 1, @db[:links].count
      edge = @db[:links].first
      assert_in_delta 3.0, edge[:score]
      assert_equal run_b, edge[:run_id], "a refresh re-attributes the edge to the run that re-found it"
    end

    def test_write_edge_refreshes_the_reverse_direction_preserving_discovery_direction
      run_a = record_run(scope: "urn:a")
      run_b = record_run(scope: "urn:b")
      write_edge(from: "urn:a:1", to: "urn:b:1", run_id: run_a, score: 1.0)
      assert_equal :refreshed, write_edge(from: "urn:b:1", to: "urn:a:1", run_id: run_b, score: 2.0)
      assert_equal 1, @db[:links].count
      edge = @db[:links].first
      assert_equal "urn:a:1", edge[:from_urn], "the original discovery direction is preserved"
      assert_in_delta 2.0, edge[:score]
    end

    def test_same_pair_different_kind_is_a_separate_edge
      run_id = record_run
      write_edge(from: "urn:a:1", to: "urn:b:1", run_id: run_id, kind: "parallel")
      assert_equal :inserted, write_edge(from: "urn:a:1", to: "urn:b:1", run_id: run_id, kind: "formula")
      assert_equal 2, @db[:links].count
    end

    # -- supersede!: a rerun replaces its scope's edges -------------------------

    def test_supersede_removes_only_the_matching_producer_scope
      old_run = record_run(scope: "urn:h")
      other = record_run(scope: "urn:x")
      write_edge(from: "urn:h:1", to: "urn:q:1", run_id: old_run)
      write_edge(from: "urn:x:1", to: "urn:q:1", run_id: other)

      runs, edges = Nabu::Store::LinksJournal.supersede!(@db, producer: "parallels", scope: "urn:h")
      assert_equal [1, 1], [runs, edges]
      assert_equal 1, @db[:links].count, "the other scope's edges survive"
      assert_equal 1, @db[:link_runs].count
      assert_equal "urn:x", @db[:link_runs].first[:scope]
    end

    def test_supersede_on_a_fresh_journal_is_a_noop
      assert_equal [0, 0], Nabu::Store::LinksJournal.supersede!(@db, producer: "parallels", scope: "urn:h")
    end

    # -- kind_counts: the show footer's query ----------------------------------

    def test_kind_counts_sees_both_directions_grouped_by_kind
      run_id = record_run
      write_edge(from: "urn:a:1", to: "urn:b:1", run_id: run_id, kind: "parallel")
      write_edge(from: "urn:c:1", to: "urn:a:1", run_id: run_id, kind: "parallel")
      write_edge(from: "urn:a:1", to: "urn:d:1", run_id: run_id, kind: "formula")
      assert_equal({ "parallel" => 2, "formula" => 1 },
                   Nabu::Store::LinksJournal.kind_counts(@db, "urn:a:1"))
      assert_empty Nabu::Store::LinksJournal.kind_counts(@db, "urn:none")
    end

    # -- file lifecycle ---------------------------------------------------------

    def test_open_bang_creates_and_migrates_and_open_readonly_reads_it
      Dir.mktmpdir("nabu-links") do |dir|
        path = File.join(dir, "links.sqlite3")
        db = Nabu::Store::LinksJournal.open!(path)
        assert db.table_exists?(:links)
        db.disconnect
        ro = Nabu::Store::LinksJournal.open_readonly(path)
        assert_equal 0, ro[:links].count
        assert_raises(Sequel::DatabaseError) do
          ro[:links].insert(from_urn: "a", to_urn: "b", kind: "parallel",
                            run_id: 1, created_at: Time.now)
        end
        ro.disconnect
      end
    end

    def test_open_readonly_returns_nil_when_no_journal_exists
      Dir.mktmpdir("nabu-links") do |dir|
        assert_nil Nabu::Store::LinksJournal.open_readonly(File.join(dir, "links.sqlite3"))
      end
    end
  end
end
