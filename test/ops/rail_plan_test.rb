# frozen_string_literal: true

require "test_helper"
require "nabu/ops/rail_plan"
require "tmpdir"

# `rake rail:plan` (the 2026-11-13 chain over-run class: a crawl chain
# hand-assembled from a board table over-ran a source's intended cadence).
# The plan is generated from the code's own declarations — each adapter's
# PacedCrawl::Schedule — and the ledger's measured slice times, as
# parallel lanes (one per source; slices sequential within a lane), the
# declared slices_per_phase a CAP, never a quota.
class RailPlanTest < Minitest::Test
  PC = Nabu::PacedCrawl

  def self.spec(name, cap)
    PC::Spec.new(name: name, ledger_file: ".#{name}.json", classes: { denied: "denied" }, delay: 0, slice: 1,
                 schedule: PC::Schedule.new(cadence: :per_phase, slices_per_phase: cap, stop_after_zero_slices: 3))
  end

  # The adapter's paced-lane seam (#paced_crawls), over every declared
  # Spec: real engines, so the plan reads the real on-disk ledger shape.
  module PacedLanes
    def paced_crawls(workdir, progress: nil)
      specs = self.class.constants(false).map { |name| self.class.const_get(name, false) }.grep(PC::Spec)
      specs.to_h do |spec|
        [spec.name, PC::Engine.new(spec: spec, dir: workdir, progress: progress, universe: -> { [] },
                                   held: ->(_) { false }, fetch_one: ->(_) { raise "no network" })]
      end
    end
  end

  def write_last_slice(canonical, slug, file, last_slice)
    FileUtils.mkdir_p(File.join(canonical, slug))
    File.write(File.join(canonical, slug, file), JSON.generate("denied" => [], "last_slice" => last_slice))
  end

  # A lane declared through a Spec constant (the common shape).
  class AlphaAdapter
    include PacedLanes

    LANE = RailPlanTest.spec("alpha", 3)
  end

  # A bare Schedule constant beside a Spec that shares it (the per-object
  # lane shape): one declaration, counted once.
  class BetaAdapter
    include PacedLanes

    SCHEDULE = PC::Schedule.new(cadence: :per_phase, slices_per_phase: 3, stop_after_zero_slices: 3)
    LANE = PC::Spec.new(name: "beta", ledger_file: ".beta.json", classes: { denied: "denied" }, delay: 0,
                        slice: 1, schedule: SCHEDULE)
  end

  class GammaAdapter
    include PacedLanes

    LANE = RailPlanTest.spec("gamma", 1)
  end

  # Declares a schedule but has never been measured.
  class DeltaAdapter
    include PacedLanes

    LANE = RailPlanTest.spec("delta", 6)
  end

  # Two lanes with different caps: the stricter cap governs (one sync
  # step runs every lane).
  class EpsilonAdapter
    BOOKS = RailPlanTest.spec("books", 4)
    PAGES = RailPlanTest.spec("pages", 2)
  end

  # A lane parked by declaration (the ratified suspension posture).
  class ZetaAdapter
    include PacedLanes

    LANE = PC::Spec.new(name: "zeta", ledger_file: ".zeta.json", classes: { denied: "denied" }, delay: 0, slice: 1,
                        schedule: PC::Schedule.new(cadence: :per_phase, slices_per_phase: 3, stop_after_zero_slices: 3,
                                                   suspended: "await upstream OCR serving"))
  end

  # Not on the rail at all.
  class PlainAdapter
    NAME = "plain"
  end

  def entry(slug, klass)
    Nabu::SourceRegistry::Entry.new(slug: slug, adapter_class_name: klass.name, wired: true, sync_policy: "manual")
  end

  def setup
    @ledger = Nabu::Store::Ledger.migrate!(Sequel.sqlite)
    @registry = Nabu::SourceRegistry.new([
                                           entry("alpha", AlphaAdapter), entry("beta", BetaAdapter),
                                           entry("plain", PlainAdapter), entry("gamma", GammaAdapter),
                                           entry("delta", DeltaAdapter)
                                         ])
    @clock = Time.utc(2026, 11, 1)
  end

  def teardown = @ledger.disconnect

  def record(slug, stage, seconds)
    @clock += 60
    Nabu::Store::StageTimings.record!(@ledger, kind: "sync", scope: slug, stage: stage, seconds: seconds, at: @clock)
  end

  # alpha: 20m per slice; beta: 25m; gamma: 5m; delta: never measured.
  def measure_all
    record("alpha", "fetch", 900)
    record("alpha", "load", 300)
    record("beta", "fetch", 1200)
    record("beta", "load", 300)
    record("gamma", "fetch", 200)
    record("gamma", "load", 100)
  end

  def plan(budget_minutes: nil, registry: @registry)
    Nabu::Ops::RailPlan.new(registry: registry, ledger: @ledger, budget_minutes: budget_minutes).plan
  end

  def test_the_roster_is_read_from_the_declarations
    lanes = plan
    assert_equal %w[alpha beta gamma delta], lanes.lanes.map(&:slug) + lanes.unmeasured.map(&:slug),
                 "every schedule-declaring adapter, registration order; the plain adapter is not on the rail"
    assert_equal [3, 3, 1, 6], lanes.all_sources.map(&:cap)
  end

  def test_the_stricter_of_several_declared_caps_governs
    registry = Nabu::SourceRegistry.new([entry("epsilon", EpsilonAdapter)])
    assert_equal [2], plan(registry: registry).all_sources.map(&:cap)
  end

  def test_the_slice_time_is_the_newest_complete_sync_step
    record("alpha", "fetch", 600)
    record("alpha", "load", 200)
    record("alpha", "index_slice", 100)
    record("alpha", "load", 999) # a later parse-only sync: not part of the step
    record("alpha", "fetch", 700) # a step still in flight (no load yet): not complete
    lane = plan.lanes.find { |l| l.slug == "alpha" }
    assert_in_delta 900.0, lane.slice_seconds, 0.001
  end

  def test_a_source_without_a_complete_step_is_unmeasured
    record("alpha", "fetch", 600) # never reached its load
    result = plan
    assert_includes result.unmeasured.map(&:slug), "alpha"
    refute_includes result.lanes.map(&:slug), "alpha"
  end

  def test_the_budget_fills_each_lane_to_the_wall_time_within_its_cap
    measure_all
    result = plan(budget_minutes: 60)
    assert_equal({ "alpha" => 3, "beta" => 2, "gamma" => 1 }, result.lanes.to_h { |l| [l.slug, l.slices] },
                 "alpha 3x20m fits; beta 2x25m (a third would overrun); gamma capped at 1 though 5m slices")
    assert_equal ["delta"], result.unmeasured.map(&:slug), "unmeasured: excluded from the budget math, listed"
    assert_in_delta 3600.0, result.wall_seconds, 0.001, "wall time = the longest lane, never the sum"
  end

  def test_a_lane_whose_one_slice_exceeds_the_budget_plans_none
    measure_all
    result = plan(budget_minutes: 10)
    assert_equal({ "alpha" => 0, "beta" => 0, "gamma" => 1 }, result.lanes.to_h { |l| [l.slug, l.slices] })
    refute_match(/lane alpha step/, Nabu::Ops::RailPlan.render(result))
  end

  def test_without_a_budget_the_caps_alone_size_the_plan
    measure_all
    result = plan
    assert_nil result.budget_seconds
    assert_equal({ "alpha" => 3, "beta" => 3, "gamma" => 1, "delta" => 6 },
                 result.all_sources.to_h { |l| [l.slug, l.slices] },
                 "no budget: every declared source at its cap, measured or not")
    assert_in_delta 4500.0, result.wall_seconds, 0.001, "the measured lanes' wall: beta 3x25m"
  end

  def test_the_step_lines_keep_the_documented_shape
    measure_all
    out = Nabu::Ops::RailPlan.render(plan(budget_minutes: 60))
    steps = out.lines.map(&:chomp).grep(/\Alane /)
    assert_equal ['lane alpha step 1: bundle exec rake "rail:step[alpha]"',
                  'lane alpha step 2: bundle exec rake "rail:step[alpha]"',
                  'lane alpha step 3: bundle exec rake "rail:step[alpha]"',
                  'lane beta step 1: bundle exec rake "rail:step[beta]"',
                  'lane beta step 2: bundle exec rake "rail:step[beta]"',
                  'lane gamma step 1: bundle exec rake "rail:step[gamma]"'], steps,
                 "every step is the yield-guarded sync (rail:step), never a bare bin/nabu sync"
    steps.each { |line| assert_match Nabu::Ops::RailPlan::STEP_LINE, line }
  end

  # The per-lane serial chain, ready to run: steps joined by && so a step
  # that exits nonzero — rail:step's zero-yield / exhausted stop — ends
  # the lane (the P177 lanes ran three identical zero-added syncs each).
  def test_each_lane_renders_as_an_and_chain_that_a_zero_yield_step_breaks
    measure_all
    out = Nabu::Ops::RailPlan.render(plan(budget_minutes: 60))
    chains = out.lines.map(&:chomp).grep(/\Achain /)
    step = ->(slug) { %(bundle exec rake "rail:step[#{slug}]") }
    assert_equal ["chain alpha: #{([step['alpha']] * 3).join(' && ')}",
                  "chain beta: #{([step['beta']] * 2).join(' && ')}",
                  "chain gamma: #{step['gamma']}"], chains
    chains.each { |line| assert_match Nabu::Ops::RailPlan::CHAIN_LINE, line }
  end

  # A source whose crawl ledger already records the cone's end is skipped
  # whole — no step would yield — and named, never silently dropped.
  def test_a_source_the_crawl_ledger_marks_exhausted_is_skipped
    measure_all
    Dir.mktmpdir("nabu-rail-plan") do |canonical|
      write_last_slice(canonical, "alpha", ".alpha.json", "classification" => "cone_exhausted",
                                                          "remaining" => { "before" => 0, "after" => 0 })
      write_last_slice(canonical, "beta", ".beta.json", "classification" => "yield",
                                                        "remaining" => { "before" => 9, "after" => 0 })
      write_last_slice(canonical, "gamma", ".gamma.json", "classification" => "yield",
                                                          "remaining" => { "before" => 9, "after" => 4 })
      result = Nabu::Ops::RailPlan.new(registry: @registry, ledger: @ledger, budget_minutes: 60,
                                       canonical_dir: canonical).plan
      assert_equal %w[alpha beta], result.exhausted.map(&:slug),
                   "cone_exhausted, or a last slice that left nothing selectable"
      assert_equal %w[gamma], result.lanes.map(&:slug)
      out = Nabu::Ops::RailPlan.render(result)
      assert_match(/^exhausted \(the crawl ledger marks the cone done — skipped\): alpha, beta$/, out)
      refute_match(/^lane (alpha|beta) /, out)
      refute_match(/^chain (alpha|beta)/, out)
    end
  end

  def test_a_suspended_source_is_skipped_with_its_reason
    registry = Nabu::SourceRegistry.new([entry("alpha", AlphaAdapter), entry("zeta", ZetaAdapter)])
    measure_all
    result = plan(registry: registry)
    assert_equal [["zeta", "await upstream OCR serving"]], result.suspended
    refute_includes result.all_sources.map(&:slug), "zeta", "a suspended source plans no step"
    out = Nabu::Ops::RailPlan.render(result)
    assert_match(/^suspended \(declared in code — skipped\): zeta \(await upstream OCR serving\)$/, out)
    refute_match(/rail:step\[zeta\]/, out)
  end

  def test_the_suspension_map_names_every_schedule_declaring_source
    registry = Nabu::SourceRegistry.new([entry("alpha", AlphaAdapter), entry("zeta", ZetaAdapter),
                                         entry("plain", PlainAdapter)])
    assert_equal({ "alpha" => nil, "zeta" => "await upstream OCR serving" },
                 Nabu::Ops::RailPlan.suspensions(registry))
  end

  def test_a_suspension_must_name_its_reason
    assert_raises(ArgumentError) do
      PC::Schedule.new(cadence: :per_phase, slices_per_phase: 1, stop_after_zero_slices: 1, suspended: " ")
    end
    refute_predicate PC::Schedule.new(cadence: :per_phase, slices_per_phase: 1, stop_after_zero_slices: 1),
                     :suspended?
  end

  def test_ndl_kotenseki_declares_the_ratified_suspension
    registry = Nabu::SourceRegistry.new([entry("ndl-kotenseki", Nabu::Adapters::NdlKotenseki)])
    assert_equal({ "ndl-kotenseki" => "await upstream OCR serving" }, Nabu::Ops::RailPlan.suspensions(registry))
  end

  def test_a_source_never_crawled_is_not_exhausted
    Dir.mktmpdir("nabu-rail-plan") do |canonical|
      result = Nabu::Ops::RailPlan.new(registry: @registry, ledger: @ledger, canonical_dir: canonical).plan
      assert_empty result.exhausted, "no ledger file = no exhaustion claim"
    end
  end

  def test_the_table_names_cap_slice_time_plan_and_lane_wall
    measure_all
    out = Nabu::Ops::RailPlan.render(plan(budget_minutes: 60))
    assert_match(/budget 1h/, out)
    assert_match(/^alpha\s+3\s+20m\s+3\s+1h$/, out)
    assert_match(/^beta\s+3\s+25m\s+2\s+50m$/, out)
    assert_match(/^delta\s+6\s+unmeasured\s+-\s+-$/, out)
    assert_match(/unmeasured \(excluded from the budget math\): delta/, out)
    assert_match(/plan wall time \(parallel lanes\): 1h/, out)
  end

  def test_the_no_budget_view_says_so_and_plans_unmeasured_sources_at_their_cap
    out = Nabu::Ops::RailPlan.render(plan)
    assert_match(/no budget — the declared caps alone size the plan/, out)
    assert_match(/^lane delta step 6: bundle exec rake "rail:step\[delta\]"$/, out)
  end

  def test_a_negative_or_zero_budget_is_refused
    assert_raises(ArgumentError) { plan(budget_minutes: 0) }
  end

  def test_a_nil_ledger_reads_every_source_unmeasured
    result = Nabu::Ops::RailPlan.new(registry: @registry, ledger: nil, budget_minutes: 30).plan
    assert_empty result.lanes
    assert_equal %w[alpha beta gamma delta], result.unmeasured.map(&:slug)
  end
end
