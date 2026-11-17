# frozen_string_literal: true

require "test_helper"
require "nabu/ops/rail_step"

# `rake "rail:step[SLUG]"` — one rail-plan step: the source's sync wrapped
# in the per-iteration yield assertion. The P177 rail ran three identical
# zero-added sync steps per lane because a bare `bin/nabu sync` chain has
# no notion of yield; the step reads every paced lane's offline diagnosis
# before and after the sync and STOPS the lane (a nonzero exit, so an
# `&&` chain breaks) when the step held nothing new or the cone is done.
class RailStepTest < Minitest::Test
  Diagnosis = Struct.new(:held_count, :remaining_count)

  # An engine double: each #diagnose answers the next queued state.
  class FakeEngine
    def initialize(*states) = @states = states.map { |held, remaining| Diagnosis.new(held, remaining) }
    def diagnose = @states.size > 1 ? @states.shift : @states.first
  end

  def step(engines)
    synced = 0
    verdict = Nabu::Ops::RailStep.new(slug: "alpha", engines: engines, sync: -> { synced += 1 }).run!
    [verdict, synced]
  end

  def test_a_yielding_step_continues_the_lane
    verdict, synced = step("pages" => FakeEngine.new([10, 50], [14, 46]))
    assert_equal 1, synced, "the sync runs exactly once"
    assert_equal :yield, verdict.status
    refute_predicate verdict, :stop?
    assert_equal 4, verdict.added
    assert_match(/\Arail:step alpha: \+4 held \(10 → 14\), 46 remaining — the lane continues\z/, verdict.line)
  end

  def test_a_zero_yield_step_stops_the_lane
    verdict, = step("pages" => FakeEngine.new([10, 50], [10, 50]))
    assert_equal :zero_yield, verdict.status
    assert_predicate verdict, :stop?
    assert_match(/\Arail:step alpha: ZERO YIELD — held unchanged at 10 \(50 remaining\); the lane stops here/,
                 verdict.line)
  end

  def test_yield_is_summed_across_every_paced_lane_of_the_source
    verdict, = step("a" => FakeEngine.new([5, 5], [5, 5]), "b" => FakeEngine.new([1, 3], [2, 2]))
    assert_equal :yield, verdict.status, "one lane landing a payload is yield for the sync step"
    assert_equal 1, verdict.added
  end

  def test_an_exhausted_cone_stops_the_lane_even_after_a_yield
    verdict, = step("pages" => FakeEngine.new([10, 2], [12, 0]))
    assert_equal :exhausted, verdict.status
    assert_predicate verdict, :stop?, "nothing is left to select: a further step can only be zero-yield"
    assert_match(/cone exhausted — \+2 held \(10 → 12\), nothing left to select; the lane stops here/, verdict.line)
  end

  def test_a_source_with_no_paced_lane_is_refused
    assert_raises(ArgumentError) { step({}) }
  end
end
