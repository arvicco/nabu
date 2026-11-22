# frozen_string_literal: true

require "test_helper"
require "stringio"

module Ops
  # Nabu::Ops::GatePipeline (`rake gate`): the canonical phase-gate order
  # as ONE command, each step its own subprocess with its real exit code
  # honored, stopping at the first red step. Every step here is a stubbed
  # runner — the suite never runs the real gate (it would run itself).
  class GatePipelineTest < Minitest::Test
    G = Nabu::Ops::GatePipeline

    # A clock that advances 1.5 s per reading: each step "takes" 1.5 s.
    def ticking_clock
      now = 0.0
      -> { now += 1.5 }
    end

    def pipeline(statuses, steps: G::STEPS)
      ran = []
      runner = lambda do |step|
        ran << step
        statuses.fetch(step, 0)
      end
      out = StringIO.new
      report = G.new(runner: runner, steps: steps, out: out, clock: ticking_clock).run
      [report, ran, out.string]
    end

    def test_the_canonical_order
      assert_equal %w[site:refresh skills:scaffold test lint boards:check site:check], G::STEPS
    end

    def test_an_all_green_run_executes_every_step_in_order
      report, ran, out = pipeline({})
      assert_predicate report, :green?
      assert_equal G::STEPS, ran
      assert_equal G::STEPS, report.completed
      assert_nil report.failed_step
      G::STEPS.each { |step| assert_match(/^gate: .*\b#{Regexp.escape(step)} ok \(1\.5s\)$/, out) }
      assert_match(/all 6 steps green/, out)
    end

    def test_it_stops_at_the_first_red_step_naming_it_and_its_exit_code
      report, ran, out = pipeline({ "test" => 3, "boards:check" => 1 })
      refute_predicate report, :green?
      assert_equal "test", report.failed_step
      assert_equal 3, report.exit_status
      assert_equal %w[site:refresh skills:scaffold test], ran
      assert_equal %w[site:refresh skills:scaffold], report.completed
      assert_match(/test FAILED exit 3 \(1\.5s\)/, out)
      assert_match(/not run: lint, boards:check, site:check/, out)
      refute_match(/all .* green/, out)
    end

    def test_a_red_first_step_runs_nothing_else
      report, ran, = pipeline({ "site:refresh" => 2 })
      assert_equal ["site:refresh"], ran
      assert_equal "site:refresh", report.failed_step
      assert_empty report.completed
    end

    def test_a_red_last_step_lists_nothing_unrun
      _, ran, out = pipeline({ "site:check" => 1 })
      assert_equal G::STEPS, ran
      assert_match(/site:check FAILED exit 1/, out)
      refute_match(/not run/, out)
    end

    def test_each_step_line_is_written_as_it_completes
      lines = []
      out = StringIO.new
      runner = lambda do |step|
        lines << out.string.lines.size # lines already written when this step starts
        step == "lint" ? 1 : 0
      end
      G.new(runner: runner, steps: %w[a b lint], out: out, clock: ticking_clock).run
      assert_equal [0, 1, 2], lines
    end

    def test_the_rake_runner_returns_zero_on_success_and_the_real_status_on_failure
      argvs = []
      ok = ->(*argv, &_block) { argvs << argv }
      assert_equal 0, G.rake_runner(rakefile: "/r/Rakefile", out: StringIO.new, shell: ok).call("lint")
      assert_equal ["-f", "/r/Rakefile", "lint"], argvs.first.last(3)

      failing = lambda do |*_argv, &_block|
        raise Nabu::Shell::Error.new("command failed (exit 4)", status: 4, stderr: "")
      end
      assert_equal 4, G.rake_runner(rakefile: "/r/Rakefile", out: StringIO.new, shell: failing).call("test")
    end

    def test_the_rake_runner_streams_the_step_output_through
      chatty = lambda do |*_argv, &block|
        block.call("line one\n")
        block.call("line two\n")
      end
      out = StringIO.new
      G.rake_runner(rakefile: "/r/Rakefile", out: out, shell: chatty).call("test")
      assert_equal "line one\nline two\n", out.string
    end

    def test_an_unspawnable_or_signalled_step_is_red_never_green
      dead = lambda do |*_argv, &_block|
        raise Nabu::Shell::Error.new("command not found: rake", status: nil, stderr: "")
      end
      refute_equal 0, G.rake_runner(rakefile: "/r/Rakefile", out: StringIO.new, shell: dead).call("test")
    end
  end
end
