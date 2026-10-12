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

    # -- detail: per-edge evidence (P16-2, migration 002) -----------------------

    def test_write_edge_persists_detail_and_a_refresh_updates_it
      run_a = record_run(scope: "urn:a")
      run_b = record_run(scope: "urn:a")
      Nabu::Store::LinksJournal.write_edge!(
        @db, from_urn: "urn:a:1", to_urn: "urn:b:1", kind: "formula",
             score: 3.0, detail: "saga hwaet ic hatte", run_id: run_a
      )
      assert_equal "saga hwaet ic hatte", @db[:links].first[:detail]

      Nabu::Store::LinksJournal.write_edge!(
        @db, from_urn: "urn:a:1", to_urn: "urn:b:1", kind: "formula",
             score: 4.0, detail: "saga hwaet ic hatte nu", run_id: run_b
      )
      assert_equal 1, @db[:links].count
      assert_equal "saga hwaet ic hatte nu", @db[:links].first[:detail],
                   "a refresh re-asserts the current evidence"
    end

    def test_detail_defaults_to_nil_for_parallel_edges
      write_edge(from: "urn:a:1", to: "urn:b:1", run_id: record_run)
      assert_nil @db[:links].first[:detail]
    end

    # Migration 002 is forward-only and applies IN PLACE to a live journal:
    # a file created at schema version 1 with edges in it gains the detail
    # column on the next write-path open, losing nothing.
    def test_detail_migration_applies_forward_to_an_existing_journal_without_data_loss
      require "sequel/extensions/migration"
      Dir.mktmpdir("nabu-links") do |dir|
        path = File.join(dir, "links.sqlite3")
        v1 = Nabu::Store::LinksJournal.connect(path)
        Sequel::Migrator.run(v1, Nabu::Store::LinksJournal::MIGRATIONS_DIR, target: 1)
        run_id = v1[:link_runs].insert(producer: "parallels", scope: "urn:h",
                                       params_json: "{}", code_version: "t/1", created_at: Time.now)
        v1[:links].insert(from_urn: "urn:a:1", to_urn: "urn:b:1", kind: "parallel",
                          score: 1.5, run_id: run_id, created_at: Time.now)
        refute_includes v1[:links].columns, :detail, "version 1 predates the column"
        v1.disconnect

        db = Nabu::Store::LinksJournal.open!(path)
        assert_includes db[:links].columns, :detail
        edge = db[:links].first
        assert_equal %w[urn:a:1 urn:b:1], [edge[:from_urn], edge[:to_urn]], "the v1 edge survives"
        assert_in_delta 1.5, edge[:score]
        assert_nil edge[:detail], "pre-migration edges read nil detail"
        assert_equal 1, db[:link_runs].count, "run provenance survives"
        db.disconnect
      end
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

    # -- chunked runs: the resumable cursor (P122-2, migration 003) --------------

    def chunked_run(scope: "urn:h")
      Nabu::Store::LinksJournal.record_run!(@db, producer: "parallels", scope: scope, params: { "gram_size" => 3 },
                                                 code_version: "test/1", status: "running", chunk_size: 2)
    end

    def record_chunk(run_id, chunk:, first:, last:, anchors: 2)
      Nabu::Store::LinksJournal.record_chunk!(@db, run_id: run_id, chunk: chunk, first_urn: first,
                                                   last_urn: last, anchors: anchors, candidates: 7,
                                                   edges_inserted: 3, edges_refreshed: 1, seconds: 0.5)
    end

    def test_a_chunk_row_advances_the_run_cursor
      run_id = chunked_run
      record_chunk(run_id, chunk: 1, first: "urn:h:1", last: "urn:h:2")
      record_chunk(run_id, chunk: 2, first: "urn:h:3", last: "urn:h:4", anchors: 2)
      run = @db[:link_runs].first(id: run_id)
      assert_equal ["running", 2, "urn:h:4", 2, 4], run.values_at(:status, :chunk_size, :cursor_urn,
                                                                  :chunks_done, :anchors_done)
      chunk = @db[:link_run_chunks].first(run_id: run_id, chunk: 2)
      assert_equal ["urn:h:3", "urn:h:4", 2, 7, 3, 1],
                   chunk.values_at(:first_urn, :last_urn, :anchors, :candidates, :edges_inserted, :edges_refreshed)
    end

    def test_a_chunk_is_recorded_once_per_run
      run_id = chunked_run
      record_chunk(run_id, chunk: 1, first: "urn:h:1", last: "urn:h:2")
      assert_raises(Sequel::UniqueConstraintViolation) do
        record_chunk(run_id, chunk: 1, first: "urn:h:1", last: "urn:h:2")
      end
    end

    def test_unfinished_run_finds_the_running_row_until_it_is_finished
      run_id = chunked_run
      assert_equal run_id, Nabu::Store::LinksJournal.unfinished_run(@db, producer: "parallels", scope: "urn:h")[:id]
      assert_nil Nabu::Store::LinksJournal.unfinished_run(@db, producer: "parallels", scope: "urn:other")
      Nabu::Store::LinksJournal.finish_run!(@db, run_id)
      assert_equal "complete", @db[:link_runs].first(id: run_id)[:status]
      refute_nil @db[:link_runs].first(id: run_id)[:finished_at]
      assert_nil Nabu::Store::LinksJournal.unfinished_run(@db, producer: "parallels", scope: "urn:h")
    end

    def test_legacy_runs_carry_no_status_and_are_never_unfinished
      record_run
      assert_nil @db[:link_runs].first[:status], "the other producers' runs are untouched by migration 003"
      assert_nil Nabu::Store::LinksJournal.unfinished_run(@db, producer: "parallels", scope: "urn:h")
    end

    def test_edges_carry_their_chunk
      run_id = chunked_run
      Nabu::Store::LinksJournal.write_edge!(@db, from_urn: "urn:a:1", to_urn: "urn:b:1", kind: "parallel",
                                                 score: 1.0, run_id: run_id, chunk: 3)
      assert_equal 3, @db[:links].first[:chunk]
      assert_nil(@db[:links].tap { write_edge(from: "urn:c:1", to: "urn:d:1", run_id: run_id) }
                            .first(from_urn: "urn:c:1")[:chunk])
    end

    # first_in_run: a pair this very run already wrote stays as found — a
    # resumed run's later chunk re-probing the reverse direction neither
    # duplicates nor re-scores it (the in-memory within-run dedupe, made
    # durable across a kill).
    def test_first_in_run_keeps_the_runs_own_edge_untouched
      run_id = chunked_run
      Nabu::Store::LinksJournal.write_edge!(@db, from_urn: "urn:a:1", to_urn: "urn:b:1", kind: "parallel",
                                                 score: 1.0, run_id: run_id, chunk: 1)
      outcome = Nabu::Store::LinksJournal.write_edge!(@db, from_urn: "urn:b:1", to_urn: "urn:a:1", kind: "parallel",
                                                           score: 9.0, run_id: run_id, chunk: 2,
                                                           first_in_run: true)
      assert_equal :kept, outcome
      edge = @db[:links].first
      assert_equal [1, "urn:a:1"], [edge[:chunk], edge[:from_urn]]
      assert_in_delta 1.0, edge[:score]
    end

    def test_first_in_run_still_refreshes_another_runs_edge
      other = record_run(scope: "urn:other")
      write_edge(from: "urn:a:1", to: "urn:b:1", run_id: other)
      run_id = chunked_run
      outcome = Nabu::Store::LinksJournal.write_edge!(@db, from_urn: "urn:b:1", to_urn: "urn:a:1", kind: "parallel",
                                                           score: 2.0, run_id: run_id, chunk: 1,
                                                           first_in_run: true)
      assert_equal :refreshed, outcome
      assert_equal [run_id, 1], @db[:links].first.values_at(:run_id, :chunk)
    end

    def test_supersede_and_wipe_clear_the_chunk_rows_too
      run_id = chunked_run
      record_chunk(run_id, chunk: 1, first: "urn:h:1", last: "urn:h:2")
      Nabu::Store::LinksJournal.supersede!(@db, producer: "parallels", scope: "urn:h")
      assert_equal 0, @db[:link_run_chunks].count
      record_chunk(chunked_run, chunk: 1, first: "urn:h:1", last: "urn:h:2")
      Nabu::Store::LinksJournal.wipe!(@db)
      assert_equal [0, 0, 0], [@db[:links].count, @db[:link_runs].count, @db[:link_run_chunks].count]
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
