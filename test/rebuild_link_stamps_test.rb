# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The links stage under per-scope stamps (Nabu::LinkStamps), end to end
# through both rebuild flavors: a clean recorded scope is CARRIED (its run
# and edges survive untouched), any input perturbation re-mines it, every
# Nth stage is a self-check that re-mines everything and compares, and a
# stamp that lies is caught as drift — loudly, in the result.
class RebuildLinkStampsTest < Minitest::Test
  # One refrain ("sing goddess") across three passages: a formulas scope
  # over the source mints a two-edge star.
  ILIAD = "Iliad\nsing goddess the wrath\nsing goddess of achilles\nsing goddess again\n"
  ODYSSEY = "Odyssey\ntell me muse\n"
  SCOPE = { producer: "formulas", scope: "corpus", params: { "gram_size" => 2, "min_count" => 2 } }.freeze

  def setup
    @root = Dir.mktmpdir("nabu-link-stamps-rebuild")
    @canonical = File.join(@root, "canonical")
    @sources_path = File.join(@root, "sources.yml")
    File.write(@sources_path, <<~YAML)
      corpus:
        adapter: TestAdapter
        wired: true
      other:
        adapter: TestAdapter
        wired: true
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)
    write_canonical("other", "two.txt" => ODYSSEY)
    Nabu::LinkScopes.record!(config.link_scopes_path, **SCOPE)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # -- the carry ---------------------------------------------------------------

  def test_a_clean_scope_is_carried_by_the_next_rebuild
    first = rebuilder.run
    assert_equal "full", first.links.mode
    assert_equal ["formulas corpus"], first.links.mined
    run_before = journal_runs
    edges_before = journal_edges

    second = rebuilder.run
    assert_equal "stamped", second.links.mode
    assert_equal ["formulas corpus"], second.links.carried
    assert_empty second.links.mined
    assert_equal run_before, journal_runs, "the carried run row is the same row — no re-mine"
    assert_equal edges_before, journal_edges
    assert_equal 2, edges_before.size
  end

  def test_a_params_change_re_mines_the_scope
    rebuilder.run
    Nabu::LinkScopes.record!(config.link_scopes_path, **SCOPE, params: { "gram_size" => 2, "min_count" => 3 })
    result = rebuilder.run
    assert_equal ["formulas corpus"], result.links.mined
    assert_match(/params/, result.links.reasons.fetch("formulas corpus"))
  end

  def test_a_member_content_change_re_mines_the_scope
    rebuilder.run
    write_canonical("corpus", "one.txt" => "#{ILIAD}sing goddess once more\n")
    result = rebuilder.run
    assert_equal ["formulas corpus"], result.links.mined
    assert_match(/members/, result.links.reasons.fetch("formulas corpus"))
    assert_equal 3, journal_edges.size, "the fresh mine sees the new locus"
  end

  def test_a_producer_code_change_re_mines_the_scope
    rebuilder.run
    target = File.join(Nabu::LinkStamps::LIB_DIR, "batch_formulas.rb")
    original = Nabu::LinkStamps.method(:code_file_digest)
    replacing(Nabu::LinkStamps, :code_file_digest, ->(path) { path == target ? "changed" : original.call(path) }) do
      result = rebuilder.run
      assert_equal ["formulas corpus"], result.links.mined
      assert_match(/producer_code/, result.links.reasons.fetch("formulas corpus"))
    end
  end

  # The code-change recheck: a scope re-mined ONLY because its producer
  # code moved has its old edges digested before they are dropped and
  # compared with the fresh mine — a pure-performance rewrite proves
  # itself on the first live stage after it lands ("reproduced"); a
  # behaviour change is reported as "changed" (informational, never
  # drift: a code change may legitimately move output).
  def test_a_code_only_re_mine_that_reproduces_its_edges_is_reported_reproduced
    rebuilder.run
    with_changed_code("batch_formulas.rb") do
      result = rebuilder.run
      assert_equal ["formulas corpus"], result.links.reproduced
      assert_empty result.links.changed
      assert_empty result.links.drift
      assert_match(/code-change re-mine.*reproduced 1 exactly/, result.links.summary)
    end
  end

  def test_a_code_only_re_mine_with_different_output_is_reported_changed_not_drift
    rebuilder.run
    original = Nabu::Store::LinksJournal.method(:write_edge!)
    altered = ->(db, **kw) { original.call(db, **kw, detail: "#{kw[:detail]}+") }
    with_changed_code("batch_formulas.rb") do
      replacing(Nabu::Store::LinksJournal, :write_edge!, altered) do
        result = rebuilder.run
        assert_empty result.links.reproduced
        assert_equal 1, result.links.changed.size
        assert_match(/\Aformulas corpus: 2 edges before the code change, 2 after — content differs/,
                     result.links.changed.first)
        assert_empty result.links.drift, "a code change may move output: reported, never drift"
        assert_match(/changed 1/, result.links.summary)
      end
    end
  end

  def test_a_re_mine_with_moved_inputs_beyond_code_is_not_rechecked
    rebuilder.run
    write_canonical("corpus", "one.txt" => "#{ILIAD}sing goddess once more\n")
    with_changed_code("batch_formulas.rb") do
      result = rebuilder.run
      assert_equal ["formulas corpus"], result.links.mined
      assert_empty result.links.reproduced, "members moved too: a difference would prove nothing"
      assert_empty result.links.changed
    end
  end

  def test_a_content_neutral_rebuild_of_an_unrelated_source_still_carries
    rebuilder.run
    write_canonical("other", "two.txt" => "Odyssey\ntell me muse of the man\n")
    result = rebuilder.run
    assert_equal ["formulas corpus"], result.links.carried,
                 "formulas is scope-local: another source's change is not its input"
  end

  # -- the self-check -------------------------------------------------------------

  def test_every_nth_links_stage_is_a_self_check_with_no_drift
    rebuilder.run # full: nothing stamped yet
    modes = Array.new(Nabu::LinkStamps::SELF_CHECK_EVERY) { rebuilder.run.links }
    assert_equal (["stamped"] * (Nabu::LinkStamps::SELF_CHECK_EVERY - 1)) + ["self-check"], modes.map(&:mode)
    check = modes.last
    assert_equal ["formulas corpus"], check.mined, "the self-check re-mines regardless of the stamp"
    assert_equal ["formulas corpus"], check.verified
    assert_empty check.drift
    assert_match(/self-check/, check.summary)
    assert_equal "stamped", rebuilder.run.links.mode, "the cadence restarts after the check"
  end

  def test_full_links_forces_the_self_check_now
    rebuilder.run
    result = rebuilder(full_links: true).run
    assert_equal "self-check", result.links.mode
    assert_equal ["formulas corpus"], result.links.verified
    assert_empty result.links.drift
  end

  def test_drift_detection_fires_on_a_corrupted_stamp
    rebuilder.run
    # The corruption: a stamp BLIND to member content (as if an input were
    # missing from the identity). The canonical text changes, the blind
    # stamp still matches, so the stale two-edge star is carried — the lie.
    blind = ->(_db, slugs) { slugs.sort.to_h { |slug| [slug, "blind"] } }
    replacing(Nabu::Store::SourceContentIdentity, :for_slugs, blind) do
      rebuilder.run # re-stamps under the blind identity (the stamped inputs moved once)
      write_canonical("corpus", "one.txt" => "#{ILIAD}sing goddess once more\n")
      lie = rebuilder.run
      assert_equal ["formulas corpus"], lie.links.carried, "the corrupted stamp carries stale edges"
      assert_equal 2, journal_edges.size

      check = nil
      _out, err = capture_io { check = rebuilder(full_links: true).run }
      assert_match(/links SELF-CHECK DRIFT: formulas corpus/, err, "drift is announced at once, loudly")
      assert_equal 1, check.links.drift.size
      assert_match(/\Aformulas corpus: 2 edges stamped, 3 freshly mined/, check.links.drift.first)
      assert_match(/DRIFT/, check.links.summary)
    end
    assert_equal 3, journal_edges.size, "the fresh mine is kept: the journal ends correct"
    with_journal do |journal|
      row = journal[:link_stage_runs].order(:id).last
      assert_equal ["self-check", 1], row.values_at(:mode, :drifted)
    end
  end

  # -- the cost law: heavy scopes are not the stage's work ---------------------------

  HEAVY = { producer: "parallels", scope: "corpus", params: { "min_score" => 0.05 } }.freeze

  def test_a_recorded_heavy_scope_is_never_mined_by_rebuild
    Nabu::LinkScopes.record!(config.link_scopes_path, **HEAVY)
    result = rebuilder.run
    assert_equal ["formulas corpus"], result.links.mined, "only the cheap lane is the stage's work"
    refute_includes result.links.reasons.keys, "parallels corpus"
    refute_path_exists config.mined_links_path, "rebuild never creates or writes the mined store"
    assert_match(/mined layers: none present · not yet mined: parallels corpus/, result.links.summary)
    assert_equal([%w[formulas corpus]], journal_runs.map { |_id, producer, scope| [producer, scope] })
  end

  # A heavy run still waiting in the journal (pre-migration) under a
  # DIRTY stamp: the stage neither re-mines it, nor drops it, nor
  # re-stamps it — it leaves the dirt calculus entirely.
  def test_a_heavy_scopes_dirty_stamp_triggers_no_work
    rebuilder.run
    Nabu::LinkScopes.record!(config.link_scopes_path, **HEAVY)
    before = with_journal do |journal|
      run = Nabu::Store::LinksJournal.record_run!(journal, producer: "parallels", scope: "corpus", params: {},
                                                           code_version: "p/old")
      Nabu::Store::LinksJournal.write_edge!(journal, from_urn: "urn:x:1", to_urn: "urn:x:2", kind: "parallel",
                                                     score: 0.5, run_id: run)
      Nabu::Store::LinksJournal.write_scope_stamp!(journal, producer: "parallels", scope: "corpus",
                                                            stamp: "stale-and-dirty", inputs: {}, run_ids: [run])
      snapshot(journal)
    end

    [rebuilder.run, rebuilder(full_links: true).run, incremental(full_links: true).run].each do |result|
      refute_includes result.links.mined, "parallels corpus"
      assert_match(%r{1 heavy run\(s\) still in db/links\.sqlite3 \(nabu links migrate-mined\)}, result.links.summary)
      assert_equal before, with_journal { |journal| snapshot(journal) }, "the heavy run, edge and stamp are untouched"
    end
    refute_path_exists config.mined_links_path
  end

  def test_a_mined_layer_is_reported_never_touched
    Nabu::LinkScopes.record!(config.link_scopes_path, **HEAVY)
    Nabu::Store::MinedLinks.mine!(config.mined_links_path, producer: "parallels", scope: "corpus", stamp: nil,
                                                           inputs: nil, catalog: nil) do |db|
      run = Nabu::Store::LinksJournal.record_run!(db, producer: "parallels", scope: "corpus", params: {},
                                                      code_version: "p/2")
      Nabu::Store::LinksJournal.write_edge!(db, from_urn: "urn:x:1", to_urn: "urn:x:2", kind: "parallel",
                                                score: 0.5, run_id: run)
      Nabu::Store::LinksJournal.finish_run!(db, run)
    end
    layer_before = Nabu::Store::MinedLinks.layers_at(config.mined_links_path)
    result = rebuilder(full_links: true).run
    assert_match(/mined layers: 1 present, oldest #{Time.now.strftime('%Y-%m-%d')}\z/, result.links.summary)
    assert_equal layer_before, Nabu::Store::MinedLinks.layers_at(config.mined_links_path)
  end

  # -- the incremental flavor -------------------------------------------------------

  def test_a_dirty_incremental_carries_a_scope_whose_members_are_clean
    rebuilder.run
    write_canonical("other", "two.txt" => "Odyssey\ntell me muse of the man\n")
    result = incremental.run
    assert_equal %w[other], result.outcomes.map(&:slug)
    assert_equal ["formulas corpus"], result.links.carried
  end

  def test_full_links_runs_the_links_stage_even_on_a_clean_incremental
    rebuilder.run
    result = incremental(full_links: true).run
    assert_empty result.outcomes
    assert_equal "self-check", result.links.mode
  end

  private

  def config
    Nabu::Config.new(canonical_dir: @canonical, db_dir: File.join(@root, "db"), sources_path: @sources_path,
                     config_path: File.join(@root, "config", "nabu.yml"))
  end

  def registry = Nabu::SourceRegistry.load(@sources_path)

  def rebuilder(full_links: false)
    Nabu::Rebuild.new(config: config, registry: registry, full_links: full_links)
  end

  def incremental(full_links: false)
    Nabu::IncrementalRebuild.new(config: config, registry: registry, full_links: full_links)
  end

  def write_canonical(slug, files)
    dir = File.join(@canonical, slug)
    FileUtils.rm_rf(dir)
    FileUtils.mkdir_p(dir)
    files.each { |name, content| File.write(File.join(dir, name), content) }
  end

  def with_journal
    journal = Nabu::Store::LinksJournal.open!(config.links_path)
    yield journal
  ensure
    journal&.disconnect
  end

  def snapshot(journal)
    [journal[:link_runs].where(producer: "parallels").all, journal[:links].where(kind: "parallel").all,
     journal[:link_scope_stamps].where(producer: "parallels").all]
  end

  def journal_runs = with_journal { |journal| journal[:link_runs].select_map(%i[id producer scope]) }

  def journal_edges
    with_journal { |journal| journal[:links].order(:from_urn, :to_urn).select_map(%i[from_urn to_urn detail]) }
  end

  def with_changed_code(rel, &)
    target = File.join(Nabu::LinkStamps::LIB_DIR, rel)
    original = Nabu::LinkStamps.method(:code_file_digest)
    replacing(Nabu::LinkStamps, :code_file_digest, ->(path) { path == target ? "changed" : original.call(path) }, &)
  end

  def replacing(owner, name, body)
    original = owner.method(name)
    owner.singleton_class.define_method(name, &body)
    yield
  ensure
    owner.singleton_class.define_method(name, original)
  end
end
