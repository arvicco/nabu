# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::IndexPreflight — the proportionality law's tool-side gate: a
# command about to run index work prints its stage plan with the ledger's
# times BEFORE touching the db, and refuses a predicted inline run past
# the budget unless the owner passes --accept-long.
class IndexPreflightTest < Minitest::Test
  Preflight = Nabu::IndexPreflight

  def setup
    @dir = Dir.mktmpdir("nabu-preflight")
    @ledger = Nabu::Store::Ledger.open!(File.join(@dir, "history.sqlite3"))
  end

  def teardown
    @ledger.disconnect
    FileUtils.rm_rf(@dir)
  end

  def record(scope, stage, seconds)
    Nabu::Store::StageTimings.record!(@ledger, kind: "sync", scope: scope, stage: stage, seconds: seconds)
  end

  def test_the_plan_reads_each_index_stages_latest_ledger_time
    record("pap", "index_slice", 900)
    record("pap", "index_slice", 120)
    record("pap", "postings_swaps", 30)
    record("corpus", "reflex_closure", 10)
    record("pap", "fetch", 9_999) # not an index stage — never planned

    plan = Preflight.plan(@ledger, slug: "pap")

    assert_equal([["pap", "index_slice", 120.0], ["pap", "postings_swaps", 30.0], ["corpus", "reflex_closure", 10.0]],
                 plan.stages.map { |row| [row.scope, row.stage, row.seconds] })
    assert_in_delta 160.0, plan.total
  end

  def test_a_source_without_history_plans_nothing
    plan = Preflight.plan(@ledger, slug: "fresh")

    assert_empty plan.stages
    assert_nil plan.total
    assert_empty Preflight.lines(plan)
  end

  def test_the_plan_lines_name_every_stage_and_the_total
    record("pap", "index_slice", 1_200)
    record("pap", "fts_merge", 300)
    lines = Preflight.lines(Preflight.plan(@ledger, slug: "pap"))

    assert_match(/index preflight: pap — predicted inline index work ~25m/, lines.first)
    assert(lines.any? { |line| line.include?("index_slice") && line.include?("20m") })
    assert(lines.any? { |line| line.include?("fts_merge") && line.include?("5m") })
  end

  def test_a_run_past_the_budget_is_refused_without_accept_long
    record("pap", "index_slice", 16 * 60)
    plan = Preflight.plan(@ledger, slug: "pap")

    error = assert_raises(Preflight::Refused) { Preflight.check!(plan, accept_long: false) }
    assert_match(/exceeds the 15m00s inline budget/, error.message)
    assert_match(/--accept-long/, error.message)
    assert_match(/between phases/, error.message)
  end

  def test_accept_long_lets_the_long_run_through
    record("pap", "index_slice", 16 * 60)

    assert_nil Preflight.check!(Preflight.plan(@ledger, slug: "pap"), accept_long: true)
  end

  def test_a_run_inside_the_budget_passes
    record("pap", "index_slice", 14 * 60)

    assert_nil Preflight.check!(Preflight.plan(@ledger, slug: "pap"), accept_long: false)
  end

  def test_a_nil_ledger_plans_nothing
    assert_empty Preflight.plan(nil, slug: "pap").stages
  end
end
