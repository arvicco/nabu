# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "nabu/paced_crawl"
require "nabu/paced_crawl_chain"

# Nabu::PacedCrawl::Chain — the shared multi-slice runner: every slice must
# progress (yield or frontier movement), consecutive zero-yield slices are
# budgeted by the spec's schedule, and the cone's honest end stops the chain
# cleanly. The chain is what a standing-slice phase fires instead of an
# ad-hoc loop of syncs.
class PacedCrawlChainTest < Minitest::Test
  P = Nabu::PacedCrawl

  def spec(slice: 2, stop_after: 2)
    P::Spec.new(
      name: "books", ledger_file: ".chain-test.json",
      classes: { denied: "denied", empty: "empty", timeout: "timeout-stuck" },
      delay: 0, slice: slice,
      schedule: P::Schedule.new(cadence: :per_phase, slices_per_phase: 3,
                                stop_after_zero_slices: stop_after)
    )
  end

  # ids answering :ok land in +held+; ids in +refused+ answer :denied.
  # ids in +halt+ answer a clean stop.
  def engine(dir, universe:, refused: [], halt: [], slice: 2, stop_after: 2)
    held = {}
    P::Engine.new(
      spec: spec(slice: slice, stop_after: stop_after), dir: dir,
      universe: -> { universe },
      held: ->(id) { held.key?(id) },
      fetch_one: lambda do |id|
        if halt.include?(id)
          P::Outcome.halt(reason: "quota floor reached", evidence: { http_status: 200, remaining: 0 })
        elsif refused.include?(id)
          P::Outcome.new(status: :denied, evidence: { http_status: 403, body_head: "no" })
        else
          held[id] = true
          P::Outcome.new(status: :ok, evidence: { http_status: 200, body_head: "" })
        end
      end,
      sleeper: ->(_) {}
    )
  end

  def run_chain(eng, slices:, log: StringIO.new)
    P::Chain.new(engine: eng, slices: slices, log: log).run!
  end

  def test_a_yielding_chain_runs_every_slice_and_reports_them
    Dir.mktmpdir do |dir|
      summary = run_chain(engine(dir, universe: %w[a b c d e f]), slices: 3)
      assert_equal 3, summary.reports.size
      assert_equal 6, summary.reports.sum(&:ok)
      refute summary.stalled?
      assert_predicate summary, :completed?
    end
  end

  def test_the_chain_stops_cleanly_at_cone_exhaustion
    Dir.mktmpdir do |dir|
      summary = run_chain(engine(dir, universe: %w[a b]), slices: 5)
      assert_equal 2, summary.reports.size # slice 2 reports cone-exhausted
      refute summary.stalled?
      assert_equal :cone_exhausted, summary.reports.last.classification
    end
  end

  def test_consecutive_zero_yield_slices_stop_the_chain_at_the_budget
    Dir.mktmpdir do |dir|
      # a..f all refused: every slice is zero-yield; budget 2 stops after 2.
      summary = run_chain(engine(dir, universe: %w[a b c d e f], refused: %w[a b c d e f],
                                      stop_after: 2), slices: 5)
      assert_equal 2, summary.reports.size
      assert_predicate summary, :stalled?
      assert_match(/2 consecutive zero-yield/, summary.stop_reason)
    end
  end

  def test_a_yielding_slice_resets_the_zero_budget
    Dir.mktmpdir do |dir|
      # slice 1: a,b refused (zero). slice 2: c,d ok (yield). slice 3: e,f
      # refused (zero again) — never two consecutive, so no stall.
      summary = run_chain(engine(dir, universe: %w[a b c d e f], refused: %w[a b e f],
                                      stop_after: 2), slices: 3)
      assert_equal 3, summary.reports.size
      refute summary.stalled?
    end
  end

  def test_a_clean_stop_slice_stops_the_chain_naming_it
    Dir.mktmpdir do |dir|
      log = StringIO.new
      # slice 1 yields a,b; slice 2 yields c then halts at d — the chain
      # stops there, even though the zero budget is far from spent.
      summary = run_chain(engine(dir, universe: %w[a b c d e f], halt: %w[d], stop_after: 5), slices: 5, log: log)
      assert_equal 2, summary.reports.size
      assert_predicate summary, :stalled?
      assert_equal :clean_stop, summary.reports.last.classification
      assert_match(/clean stop at d: quota floor reached/, summary.stop_reason)
      assert_match(/CHAIN STOPPED: clean stop/, log.string)
    end
  end

  def test_the_chain_logs_every_report_line
    Dir.mktmpdir do |dir|
      log = StringIO.new
      run_chain(engine(dir, universe: %w[a b]), slices: 1, log: log)
      assert_match(/slice \+2 ok/, log.string)
      assert_match(/reconciles/, log.string)
    end
  end
end
