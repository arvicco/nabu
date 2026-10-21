# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Store::MinedLinks — the mined-layers store's gateway (the cost
# law; architecture §15). Its write path is #mine! (provenance dropped
# first, the producer's writes, provenance + self-check verdict) and
# #migrate! (the one-time move out of db/links.sqlite3: counts verified,
# idempotent, crash-resumable); everything else reads.
module Store
  class MinedLinksTest < Minitest::Test
    J = Nabu::Store::LinksJournal
    M = Nabu::Store::MinedLinks

    def setup
      @dir = Dir.mktmpdir("nabu-mined-links")
      @path = File.join(@dir, "local", "mined-links.sqlite3")
      @journal_path = File.join(@dir, "db", "links.sqlite3")
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    INPUTS = { "producer_code" => "c1", "params" => { "lang" => "lat" }, "members" => { "a" => "x" } }.freeze

    # One parallels mine of +pairs+ ([from, to] urns) into the store.
    def mine(pairs, inputs: INPUTS, stamp: "s1", scope: "alpha", catalog: { "a" => "i1" }, chunks: false)
      M.mine!(@path, producer: "parallels", scope: scope, stamp: stamp, inputs: inputs, catalog: catalog) do |db|
        J.supersede!(db, producer: "parallels", scope: scope)
        run = J.record_run!(db, producer: "parallels", scope: scope, params: { lang: "lat" },
                                code_version: "parallels-batch/2", status: "running", chunk_size: chunks ? 1 : nil)
        pairs.each do |from, to|
          J.write_edge!(db, from_urn: from, to_urn: to, kind: "parallel", score: 0.5, run_id: run)
        end
        J.finish_run!(db, run)
      end
    end

    def with_store
      db = M.open_readonly(@path)
      yield db
    ensure
      db&.disconnect
    end

    # -- the mine write path ---------------------------------------------------

    def test_a_mine_records_its_layer_provenance
      result = mine([%w[u:1 u:2], %w[u:1 u:3]])
      layer = result.layer
      assert_equal :first, result.verdict
      assert_equal ["parallels", "alpha", "alpha", 2, "mine", "parallels-batch/2", "s1"],
                   [layer.producer, layer.scope, layer.run_scope, layer.edges, layer.origin, layer.code_version,
                    layer.stamp]
      assert_equal INPUTS, layer.inputs
      assert_equal({ "a" => "i1" }, layer.catalog, "the members' ingest identities ride the provenance")
      with_store do |db|
        run = db[:link_runs].first
        assert_equal run[:finished_at].to_i, layer.mined_at.to_i, "mined_at is the run's finish time"
        assert_equal [layer], M.layers(db)
      end
    end

    def test_the_self_check_verifies_an_unchanged_re_mine
      mine([%w[u:1 u:2]])
      result = mine([%w[u:1 u:2]])
      assert_equal :verified, result.verdict
      with_store { |db| assert_equal 1, db[:links].count, "the re-mine supersedes, never duplicates" }
    end

    def test_the_self_check_catches_drift_under_an_unchanged_stamp
      mine([%w[u:1 u:2]])
      result = mine([%w[u:1 u:2], %w[u:1 u:9]])
      assert_equal :drift, result.verdict, "same stamp, different edges: the stamp misses an input"
      assert_equal 1, result.before_edges
    end

    def test_a_code_only_re_mine_is_reproduced_or_changed
      mine([%w[u:1 u:2]])
      moved = INPUTS.merge("producer_code" => "c2")
      assert_equal :reproduced, mine([%w[u:1 u:2]], inputs: moved, stamp: "s2").verdict
      changed = mine([%w[u:1 u:3]], inputs: moved.merge("producer_code" => "c3"), stamp: "s3")
      assert_equal [:changed, ["producer_code"]], [changed.verdict, changed.blame]
    end

    def test_a_re_mine_with_moved_inputs_names_them
      mine([%w[u:1 u:2]])
      result = mine([%w[u:1 u:2]], inputs: INPUTS.merge("members" => { "a" => "y" }), stamp: "s2")
      assert_equal [:remined, ["members"]], [result.verdict, result.blame]
    end

    def test_provenance_falls_first_so_a_failed_mine_vouches_for_nothing
      mine([%w[u:1 u:2]])
      assert_raises(Nabu::Error) do
        M.mine!(@path, producer: "parallels", scope: "alpha", stamp: "s1", inputs: INPUTS, catalog: nil) do |_db|
          raise Nabu::Error, "boom"
        end
      end
      with_store { |db| assert_empty M.layers(db), "no provenance row survives a failed mine" }
    end

    def test_an_unfinished_chunked_run_records_no_layer
      error = assert_raises(Nabu::Error) do
        M.mine!(@path, producer: "parallels", scope: "alpha", stamp: "s1", inputs: INPUTS, catalog: nil) do |db|
          J.record_run!(db, producer: "parallels", scope: "alpha", params: {}, code_version: "v",
                            status: "running", chunk_size: 5)
        end
      end
      assert_match(/unfinished chunked run — rerun to resume/, error.message)
      with_store { |db| assert_empty M.layers(db) }
    end

    # The shelf write-gateway discipline: the writable opener is not part
    # of the module's public surface — #mine! and #migrate! are the doors.
    def test_the_writable_opener_is_private
      refute_respond_to M, :open!
      assert_respond_to M, :mine!
      assert_respond_to M, :migrate!
      assert_nil M.open_readonly(@path), "an absent store is an honest nil"
      assert_empty M.layers_at(@path)
    end

    def test_sample_edges_spreads_over_the_layer
      mine((1..50).map { |i| ["u:#{i}", "v:#{i}"] })
      with_store do |db|
        sample = M.sample_edges(db, M.layers(db).first.run_ids, size: 10)
        assert_equal 10, sample.size
        assert_equal sample.uniq, sample
        assert_includes sample, %w[u:1 v:1], "the sample starts at the layer's first edge"
      end
    end

    # -- the one-time migration ------------------------------------------------

    # A pre-split journal: a chunked parallels run (2 edges, 2 chunk rows,
    # stamped), a plain parallels run (1 edge, unstamped) and a cheap
    # formulas run (1 edge) that must stay.
    def seed_journal
      journal = J.open!(@journal_path)
      latin = J.record_run!(journal, producer: "parallels", scope: "perseus-latin", params: { lang: "lat" },
                                     code_version: "p/2", status: "running", chunk_size: 1)
      2.times do |i|
        J.write_edge!(journal, from_urn: "l:#{i}", to_urn: "l:x", kind: "parallel", score: 0.25, run_id: latin,
                               chunk: i + 1)
        J.record_chunk!(journal, run_id: latin, chunk: i + 1, first_urn: "l:#{i}", last_urn: "l:#{i}", anchors: 1,
                                 candidates: 3, edges_inserted: 1, edges_refreshed: 0, seconds: 0.1)
      end
      J.finish_run!(journal, latin)
      J.write_scope_stamp!(journal, producer: "parallels", scope: "perseus-latin", stamp: "stamp-latin",
                                    inputs: { "producer_code" => "c" }, run_ids: [latin])
      matt = J.record_run!(journal, producer: "parallels", scope: "urn:m", params: {}, code_version: "p/2")
      J.write_edge!(journal, from_urn: "m:1", to_urn: "m:2", kind: "parallel", score: 0.5, run_id: matt)
      formulas = J.record_run!(journal, producer: "formulas", scope: "aspr", params: {}, code_version: "f/1")
      J.write_edge!(journal, from_urn: "a:1", to_urn: "a:2", kind: "formula", score: 1.0, detail: "g",
                             run_id: formulas)
      J.write_scope_stamp!(journal, producer: "formulas", scope: "aspr", stamp: "stamp-aspr",
                                    inputs: {}, run_ids: [formulas])
      journal.disconnect
    end

    def migrate(**) = M.migrate!(@path, journal_path: @journal_path, producers: %w[parallels], **)

    def test_migration_moves_heavy_runs_with_their_stamp_provenance
      seed_journal
      report = migrate
      assert_equal ["parallels perseus-latin", "parallels urn:m"], report.moved
      assert_equal [2, 3, 0, 0, 3],
                   [report.runs, report.journal_edges_before, report.journal_edges_after,
                    report.mined_edges_before, report.mined_edges_after]
      with_store do |db|
        latin, matt = M.layers(db)
        assert_equal ["perseus-latin", 2, "migrated", "stamp-latin", { "producer_code" => "c" }],
                     [latin.scope, latin.edges, latin.origin, latin.stamp, latin.inputs]
        assert_nil latin.catalog, "no catalog vouching asked: the identity stays unrecorded"
        assert_equal ["urn:m", 1, nil], [matt.scope, matt.edges, matt.stamp]
        run = db[:link_runs].where(scope: "perseus-latin").first
        assert_equal ["complete", 2, 1], [run[:status], run[:chunks_done], run[:chunk_size]]
        assert_equal 2, db[:link_run_chunks].where(run_id: run[:id]).count, "chunk rows move with their run"
        assert_equal [[0.25, 1], [0.25, 2]],
                     db[:links].where(run_id: run[:id]).order(:chunk).select_map(%i[score chunk])
      end
      journal = J.open_readonly(@journal_path)
      assert_equal %w[formulas], journal[:link_runs].select_map(:producer), "the cheap run stays"
      assert_equal 1, journal[:links].count
      assert_equal [%w[formulas aspr]], journal[:link_scope_stamps].select_map(%i[producer scope])
      assert_empty journal[:link_run_chunks].all
      journal.disconnect
    end

    def test_migration_is_idempotent
      seed_journal
      migrate
      again = migrate
      assert_equal [0, [], 3], [again.runs, again.moved, again.mined_edges_after]
    end

    def test_a_migration_resumed_after_the_copy_only_drops_the_journal_copy
      seed_journal
      # The crash: copies verified and committed, the journal delete never ran.
      original = M.method(:drop_journal_runs!)
      M.singleton_class.send(:define_method, :drop_journal_runs!) { |*| raise Interrupt }
      assert_raises(Interrupt) { migrate }
      M.singleton_class.send(:define_method, :drop_journal_runs!, original)
      M.singleton_class.send(:private, :drop_journal_runs!)

      report = migrate
      assert_empty report.moved
      assert_equal ["parallels perseus-latin", "parallels urn:m"], report.kept
      assert_equal [3, 0, 3, 3], [report.journal_edges_before, report.journal_edges_after,
                                  report.mined_edges_before, report.mined_edges_after]
    end

    def test_a_dry_run_counts_and_writes_nothing
      seed_journal
      report = migrate(dry_run: true)
      assert_equal [true, 2, 3, 3], [report.dry_run, report.runs, report.journal_edges_before,
                                     report.journal_edges_after]
      refute_path_exists @path
    end

    def test_migration_records_a_vouched_catalog_identity
      seed_journal
      asked = []
      vouch = lambda do |producer, scope, stamp|
        asked << [producer, scope, stamp]
        stamp == "stamp-latin" ? { "a" => "i1" } : nil
      end
      migrate(catalog_for: vouch)
      assert_equal [["parallels", "perseus-latin", "stamp-latin"], ["parallels", "urn:m", nil]], asked
      with_store { |db| assert_equal [{ "a" => "i1" }, nil], M.layers(db).map(&:catalog) }
    end

    def test_a_journal_without_heavy_runs_migrates_nothing
      report = migrate
      assert_equal [0, [], 0], [report.runs, report.moved, report.mined_edges_after]
      refute_path_exists @path, "nothing to move — no store is created"
    end
  end
end
