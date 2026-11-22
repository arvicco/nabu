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
    record("pap", "reflex_closure", 10)
    record("corpus", "reflex_closure", 9_999) # the retired corpus-wide closure — never planned
    record("pap", "fetch", 9_999) # not an index stage — never planned

    plan = Preflight.plan(@ledger, slug: "pap")

    assert_equal([["pap", "index_slice", 120.0], ["pap", "postings_swaps", 30.0], ["pap", "reflex_closure", 10.0]],
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

  # -- the predicted shadow build (delta-engaged is not delta-priced) -------
  # The refresh's slices are the delta; a shadow build past the in-place
  # budget is the whole index. The gate prices the forecast shadow as its
  # own stage so the watcher's deadline covers slices + shadow together,
  # and refuses up front when the deadline cannot.

  def shadow(scope: "corpus", slugs: %w[ndl wellcome], rows: 95_000_000)
    Nabu::Store::Indexer::ShadowForecast.new(scope: scope, slugs: slugs, rows: rows)
  end

  def record_rows(scope, stage, seconds, rows)
    Nabu::Store::StageTimings.record!(@ledger, kind: "sync", scope: scope, stage: stage, seconds: seconds,
                                               rows: rows)
  end

  def history_path = File.join(@dir, "history.sqlite3")

  def gate(slugs: %w[ndl wellcome], shadows: [shadow], accept_long: false, deadline: nil)
    out = StringIO.new
    priced = Preflight.gate!(history_path: history_path, slugs: slugs, accept_long: accept_long, out: out,
                             shadows: shadows, deadline_minutes: deadline)
    [priced, out.string]
  end

  # The incident's ledger: the slices price ~13m; the last wave's shadow
  # build took an hour. Before the forecast, the deadline saw only the 13m.
  def plant_the_incident_ledger
    record("ndl", "index_slice", 748)
    record("wellcome", "index_slice", 35)
    record("corpus", "fts_shadow", 3_600)
  end

  def test_an_unledgered_shadow_left_the_deadline_blind_and_the_forecast_prices_it
    plant_the_incident_ledger
    slices = Nabu::IndexWatcher.ledger_estimate(@ledger, kind: "sync", scopes: %w[ndl wellcome corpus],
                                                         stages: Nabu::IndexWatcher::REFRESH_STAGES)
    blind = Nabu::IndexWatcher.deadline_for(estimate: slices)

    assert_operator blind, :<, 3_600, "the slice-only deadline dies inside the hour-long shadow (the incident)"
    priced, out = gate(accept_long: true)
    deadline = Nabu::IndexWatcher.deadline_for(estimate: slices + priced.sum(&:seconds))

    assert_equal([["corpus", "fts_shadow", 3_600.0]], priced.map { |row| [row.scope, row.stage, row.seconds] })
    assert_operator deadline, :>=, (748 + 35 + 3_600) * Nabu::IndexWatcher::DEADLINE_FACTOR
    assert_match(/fts_shadow \(corpus — ndl \+ wellcome\).*~95,000,000 rows.*60m00s/, out)
  end

  def test_the_shadow_price_scales_with_the_recorded_row_count
    record_rows("ndl", "fts_shadow", 1_800, 50_000_000) # any scope: the cost is the shadow's size

    priced, = gate(accept_long: true)

    assert_in_delta 3_420.0, priced.first.seconds
    assert priced.first.ledgered
    assert_match(/last run 30m00s over 50,000,000 rows; scaled for 95,000,000/, priced.first.basis)
  end

  def test_an_unpriced_shadow_takes_the_conservative_floor_from_its_size
    priced, = gate(accept_long: true, shadows: [shadow(rows: 1_500_000)])

    assert_in_delta 1_500_000.0 / Preflight::SHADOW_FLOOR_ROWS_PER_SECOND, priced.first.seconds
    refute priced.first.ledgered
  end

  def test_an_unpriced_shadow_refuses_without_accept_long
    error = assert_raises(Preflight::Refused) { gate(shadows: [shadow(rows: 1_500_000)]) }

    assert_match(/passages_fts shadow build — stage fts_shadow \(corpus — ndl \+ wellcome\)/, error.message)
    assert_match(/UNPRICED/, error.message)
    assert_match(/no ledger row prices it yet/, error.message)
    assert_match(/Proceed with --deadline 15 \(/, error.message, "the floor's 100s total arms at the 15m floor")
    assert_match(/--deadline 0 --accept-long/, error.message)
  end

  def test_an_unpriced_shadow_proceeds_on_the_suggested_explicit_deadline
    priced, = gate(shadows: [shadow(rows: 1_500_000)], deadline: 15)

    assert_equal 1, priced.size
  end

  def test_a_priced_shadow_past_the_budget_refuses_naming_the_stage_and_the_flags
    plant_the_incident_ledger

    error = assert_raises(Preflight::Refused) { gate }
    assert_match(/stage fts_shadow/, error.message)
    assert_match(/priced ~60m00s/, error.message)
    assert_match(/predicted total with the slices ~73m03s/, error.message)
    assert_match(/past the 15m00s inline budget/, error.message)
    assert_match(/--deadline 183 --accept-long/, error.message, "2.5x the priced total, rounded up")
    assert_match(/no explicit deadline under 92 is accepted — 1.25x/, error.message, "the margined minimum")
    assert_match(/--deadline 0 --accept-long/, error.message)
  end

  def test_an_explicit_deadline_that_cannot_cover_the_priced_total_refuses_even_with_accept_long
    plant_the_incident_ledger

    error = assert_raises(Preflight::Refused) { gate(accept_long: true, deadline: 60) }
    assert_match(/--deadline 60 cannot cover it/, error.message)
  end

  # The margined boundary (COVER_MARGIN): a deadline above the priced
  # total but under 1.25x of it is no cover — the 75m-vs-73m33s kill.
  # Here the total is 73m03s, so the minimum is ceil(91.3) = 92 minutes.
  def test_a_deadline_above_the_total_but_under_the_cover_margin_is_refused
    plant_the_incident_ledger

    error = assert_raises(Preflight::Refused) { gate(accept_long: true, deadline: 75) }
    assert_match(/--deadline 75 cannot cover it \(under the 92-minute minimum, 1.25x the priced total/, error.message)
    assert_raises(Preflight::Refused) { gate(accept_long: true, deadline: 91) }
    assert_equal 1, gate(accept_long: true, deadline: 92).first.size, "the margined minimum itself covers"
  end

  def test_a_covering_deadline_or_zero_proceeds_with_accept_long
    plant_the_incident_ledger

    assert_equal 1, gate(accept_long: true, deadline: 200).first.size
    assert_equal 1, gate(accept_long: true, deadline: 0).first.size
  end

  def test_a_small_priced_shadow_inside_the_budget_passes_without_flags
    record("ndl", "index_slice", 60)
    record("corpus", "fts_shadow", 120)

    assert_equal 1, gate.first.size
    assert_equal 1, gate(deadline: 10).first.size, "a covering explicit deadline needs no --accept-long"
  end

  def test_no_forecast_leaves_the_gate_as_it_was
    record("ndl", "index_slice", 60)

    priced, out = gate(shadows: [])
    assert_empty priced
    refute_match(/fts_shadow/, out)
  end
end
