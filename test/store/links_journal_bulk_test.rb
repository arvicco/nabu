# frozen_string_literal: true

require "test_helper"

module Store
  # LinksJournal.write_edges! (store/links_journal_bulk.rb): the bulk edge
  # writer the place mine writes through, pinned to write_edge!'s exact
  # per-edge semantics.
  class LinksJournalBulkTest < Minitest::Test
    def setup
      @db = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    end

    def teardown
      @db.disconnect
    end

    def record_run
      Nabu::Store::LinksJournal.record_run!(@db, producer: "parallels", scope: "urn:h", params: {},
                                                 code_version: "test/1")
    end

    # The bulk writer's contract is EXACT equivalence with calling
    # write_edge! once per edge in order: same rows (ids included — the
    # insertion order is the call order), same detail where a pair is hit
    # twice (the later call's wins), same inserted/refreshed tally — across
    # in-batch duplicates, an in-batch reversed pair, and pairs a prior run
    # already holds in either direction (or both).
    def test_write_edges_is_equivalent_to_sequential_write_edge
      edges = [
        ["p:1", "t:A", nil, "a1"],   # pre-existing, same direction
        ["p:2", "t:B", nil, "b1"],   # pre-existing, reverse direction
        ["p:3", "t:C", nil, "c1"],   # pre-existing in BOTH directions
        ["p:4", "t:D", nil, "d1"],   # fresh
        ["p:4", "t:E", 0.5, "e1"],   # fresh
        ["p:4", "t:D", nil, "d2"],   # in-batch duplicate → refresh, later detail wins
        ["t:E", "p:4", nil, "e2"],   # in-batch reversed pair → refresh in place
        ["p:1", "t:A", nil, "a2"],   # pre-existing hit twice
        ["p:5", "t:A", nil, "f1"]    # fresh
      ]
      seq_db = seeded_journal
      seq_run = Nabu::Store::LinksJournal.record_run!(seq_db, producer: "place-mine", scope: "s",
                                                              params: {}, code_version: "t")
      seq_counts = Hash.new(0)
      edges.each do |from, to, score, detail|
        seq_counts[Nabu::Store::LinksJournal.write_edge!(seq_db, from_urn: from, to_urn: to, kind: "place-candidate",
                                                                 score: score, run_id: seq_run, detail: detail)] += 1
      end

      bulk_db = seeded_journal
      bulk_run = Nabu::Store::LinksJournal.record_run!(bulk_db, producer: "place-mine", scope: "s",
                                                                params: {}, code_version: "t")
      counts = Nabu::Store::LinksJournal.write_edges!(bulk_db, edges, kind: "place-candidate", run_id: bulk_run)

      assert_equal({ inserted: seq_counts[:inserted], refreshed: seq_counts[:refreshed] }, counts)
      assert_equal edge_rows(seq_db), edge_rows(bulk_db)
      assert_equal 3, counts[:inserted]
    ensure
      [seq_db, bulk_db].compact.each(&:disconnect)
    end

    def test_write_edges_on_an_empty_list_writes_nothing
      run = record_run
      assert_equal({ inserted: 0, refreshed: 0 },
                   Nabu::Store::LinksJournal.write_edges!(@db, [], kind: "parallel", run_id: run))
      assert_equal 0, @db[:links].count
    end

    def seeded_journal
      db = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
      prior = Nabu::Store::LinksJournal.record_run!(db, producer: "other", scope: "o", params: {}, code_version: "t")
      [%w[p:1 t:A], %w[t:B p:2], %w[p:3 t:C], %w[t:C p:3], %w[p:9 t:Z]].each do |from, to|
        Nabu::Store::LinksJournal.write_edge!(db, from_urn: from, to_urn: to, kind: "place-candidate",
                                                  score: nil, run_id: prior, detail: "prior")
      end
      db
    end

    def edge_rows(db)
      db[:links].order(:id).select(:id, :from_urn, :to_urn, :kind, :score, :detail, :run_id, :chunk).all
    end
  end
end
