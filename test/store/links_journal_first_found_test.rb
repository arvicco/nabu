# frozen_string_literal: true

require "test_helper"

# LinksJournal.write_edges_first_found! — the postings engine's bulk
# committer — must leave EXACTLY what write_edge!(first_in_run: true) once
# per entry, in order, leaves: same rows, same directions, same scores, same
# tally (kept included).
class LinksJournalFirstFoundTest < Minitest::Test
  J = Nabu::Store::LinksJournal

  def journal
    J.migrate!(J.connect("sqlite::memory:"))
  end

  # A prior run's edges, then this run's own earlier chunk — the two kinds
  # of held pair the writer must tell apart.
  def seed(db)
    prior = J.record_run!(db, producer: "parallels", scope: "other", params: {}, code_version: "x")
    J.write_edge!(db, from_urn: "u:b", to_urn: "u:a", kind: "parallel", score: 9.0, run_id: prior)
    J.write_edge!(db, from_urn: "u:x", to_urn: "u:y", kind: "formula", score: 1.0, run_id: prior)
    run = J.record_run!(db, producer: "parallels", scope: "mine", params: {}, code_version: "x")
    J.write_edge!(db, from_urn: "u:c", to_urn: "u:d", kind: "parallel", score: 2.0, run_id: run, chunk: 1,
                      first_in_run: true)
    run
  end

  EDGES = [
    ["u:a", "u:b", 0.5, nil], # held by the prior run (reverse direction) → refreshed
    ["u:b", "u:a", 0.7, nil], # now this run's → kept
    ["u:d", "u:c", 3.0, nil], # this run's earlier chunk → kept
    ["u:e", "u:f", 1.5, nil], # new → inserted
    ["u:f", "u:e", 1.9, nil], # reverse of a pending insert → kept (first found wins)
    ["u:x", "u:y", 4.0, nil], # same urns, another kind's edge → new parallel edge
    ["u:g", "u:e", 0.3, nil]
  ].freeze

  def state(db)
    db[:links].order(:kind, :from_urn, :to_urn).select_map(%i[from_urn to_urn kind score run_id chunk])
  end

  def test_bulk_equals_the_sequential_first_in_run_writes
    serial = journal
    run = seed(serial)
    tally = Hash.new(0)
    EDGES.each do |from, to, score, detail|
      tally[J.write_edge!(serial, from_urn: from, to_urn: to, kind: "parallel", score: score, detail: detail,
                                  run_id: run, chunk: 2, first_in_run: true)] += 1
    end

    bulk = journal
    run_b = seed(bulk)
    counts = J.write_edges_first_found!(bulk, EDGES, kind: "parallel", run_id: run_b, chunk: 2)
    assert_equal({ inserted: tally[:inserted], refreshed: tally[:refreshed], kept: tally[:kept] }, counts)
    assert_equal({ inserted: 3, refreshed: 1, kept: 3 }, counts)
    assert_equal state(serial), state(bulk)
    assert_equal [%w[u:b u:a]], bulk[:links].where(kind: "parallel", score: 0.5).select_map(%i[from_urn to_urn]),
                 "a refreshed pair keeps its discovery direction"
  end

  def test_empty_is_a_no_op
    assert_equal({ inserted: 0, refreshed: 0, kept: 0 },
                 J.write_edges_first_found!(journal, [], kind: "parallel", run_id: 1))
  end
end
