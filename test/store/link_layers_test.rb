# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Store::LinkLayers — the READ side of the links split: one
# read-only handle over db/links.sqlite3 and local/mined-links.sqlite3,
# so every reader sees one edge set. Absent stores are honest states.
module Store
  class LinkLayersTest < Minitest::Test
    J = Nabu::Store::LinksJournal

    def setup
      @dir = Dir.mktmpdir("nabu-link-layers")
      @links = File.join(@dir, "links.sqlite3")
      @mined = File.join(@dir, "mined-links.sqlite3")
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def seed_journal
      journal = J.open!(@links)
      run = J.record_run!(journal, producer: "formulas", scope: "aspr", params: {}, code_version: "f/1")
      J.write_edge!(journal, from_urn: "u:1", to_urn: "u:2", kind: "formula", score: 1.0, detail: "g", run_id: run)
      journal.disconnect
    end

    def seed_mined
      Nabu::Store::MinedLinks.mine!(@mined, producer: "parallels", scope: "lat", stamp: nil, inputs: nil,
                                            catalog: nil) do |db|
        run = J.record_run!(db, producer: "parallels", scope: "lat", params: {}, code_version: "p/2")
        J.write_edge!(db, from_urn: "u:1", to_urn: "u:3", kind: "parallel", score: 0.5, run_id: run)
        J.write_edge!(db, from_urn: "u:4", to_urn: "u:1", kind: "parallel", score: 0.4, run_id: run)
        J.finish_run!(db, run)
      end
    end

    def open = Nabu::Store::LinkLayers.open_paths(links_path: @links, mined_path: @mined)

    def test_no_store_is_nil
      assert_nil open
    end

    def test_only_the_journal_is_the_plain_journal
      seed_journal
      db = open
      assert_equal 1, db[:links].count
      refute(db.schema(:links).any? { |name, _| name == :mined_at }, "no mined store, no mined_at column")
    ensure
      db&.disconnect
    end

    def test_only_the_mined_store_reads_alone_with_negated_ids
      seed_mined
      db = open
      edges = db[:links].order(:to_urn).all
      assert_equal([-1, -1], edges.map { |edge| edge[:run_id] })
      assert(edges.all? { |edge| edge[:id].negative? && edge[:mined_at] })
      assert_equal "parallels", db[:link_runs].where(id: -1).get(:producer)
    ensure
      db&.disconnect
    end

    def test_both_stores_read_as_one_edge_set
      seed_journal
      seed_mined
      db = open
      assert_equal({ "formula" => 1, "parallel" => 2 }, J.kind_counts(db, "u:1"), "the show footer's count spans both")
      outgoing = db[:links].where(from_urn: "u:1").order(:kind).all
      assert_equal([["formula", 1, false], ["parallel", -1, true]],
                   outgoing.map { |edge| [edge[:kind], edge[:run_id], !edge[:mined_at].nil?] })
      mined = outgoing.last
      assert_equal Time.now.year, Nabu::Store::LinkLayers.mined_time(mined[:mined_at]).year
      runs = db[:link_runs].order(:id).select_map(%i[id producer])
      assert_equal [[-1, "parallels"], [1, "formulas"]], runs, "run ids never collide across the union"
      assert_raises(Sequel::DatabaseError, "the union is read-only, the attached store included") do
        db.run("INSERT INTO mined.link_runs (producer, scope, params_json, code_version, created_at) " \
               "VALUES ('x', 'y', '{}', 'z', '2026-01-01')")
      end
    ensure
      db&.disconnect
    end

    # UNION ALL views take the reader's WHERE into each arm: a per-urn
    # probe stays an indexed search in BOTH stores (never a scan).
    def test_per_urn_probes_stay_indexed_in_both_stores
      seed_journal
      seed_mined
      db = open
      plan = db.fetch("EXPLAIN QUERY PLAN SELECT * FROM links WHERE from_urn = ?", "u:1").map { |row| row[:detail] }
      assert(plan.any? { |line| line.match?(/SEARCH main\.links USING .*INDEX/) }, plan.join(" | "))
      assert(plan.any? { |line| line.match?(/SEARCH (l|mined\.links) USING .*INDEX/) }, plan.join(" | "))
    ensure
      db&.disconnect
    end

    def test_the_query_reader_carries_the_layer_date
      seed_journal
      seed_mined
      catalog = Nabu::Store.connect("sqlite::memory:")
      Nabu::Store.migrate!(catalog)
      db = open
      result = Nabu::Query::Links.new(catalog: catalog, journal: db).run("u:1")
      parallel = result.groups.fetch("parallel")
      assert(parallel.all? { |edge| edge.mined_at.is_a?(Time) })
      assert_nil result.groups.fetch("formula").first.mined_at
      mined_run, cheap_run = result.runs
      assert_equal ["mined layer run 1", true], [mined_run.label, mined_run.mined?]
      assert_equal ["run 1", false], [cheap_run.label, cheap_run.mined?]
    ensure
      db&.disconnect
      catalog&.disconnect
    end
  end
end
