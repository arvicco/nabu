# frozen_string_literal: true

require "rbconfig"
require_relative "../errors"
require_relative "../shell"

module Nabu
  module Ops
    # `rake gate` — the phase gate as ONE command, in the canonical order:
    # the site refresh first (so every later check judges the state being
    # published), the skill-pack scaffold, the suite, lint, the board
    # checks, and the site drift check last.
    #
    # Each step runs as its OWN subprocess (`rake -f <Rakefile> <step>`
    # through Nabu::Shell.stream): its output streams through live and its
    # REAL exit status decides — never a pipe, never a swallowed status
    # (a piped gate once reported a red suite green). The first red step
    # stops the run, named with its exit code and the steps left unrun.
    # One line per step as it completes, flushed at once, with its elapsed
    # seconds, so progress reads during a long run.
    class GatePipeline
      STEPS = %w[site:refresh skills:scaffold test lint boards:check site:check].freeze

      Report = Data.define(:completed, :failed_step, :exit_status) do
        def green? = failed_step.nil?
      end

      # The default step runner: +step+ as a child rake process over
      # +rakefile+, its merged output forwarded to +out+ line by line.
      # Returns the child's exit status (0 = green). A child that cannot
      # be spawned or dies without a status (a signal) is red, never green.
      # +shell+ is the Shell.stream seam tests stub.
      def self.rake_runner(rakefile:, out: $stdout, shell: Nabu::Shell.method(:stream))
        rake = Gem.bin_path("rake", "rake")
        lambda do |step|
          shell.call(RbConfig.ruby, rake, "-f", rakefile, step) do |line|
            out.print(line)
            out.flush
          end
          0
        rescue Nabu::Shell::Error => e
          e.status || 1
        end
      end

      def initialize(runner:, steps: STEPS, out: $stdout,
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @runner = runner
        @steps = steps
        @out = out
        @clock = clock
      end

      def run
        started = @clock.call
        completed = []
        @steps.each_with_index do |step, index|
          status, seconds = timed { @runner.call(step) }
          if status.zero?
            completed << step
            say "#{tag(index)} #{step} ok (#{seconds}s)"
            next
          end

          rest = @steps.drop(index + 1)
          say "#{tag(index)} #{step} FAILED exit #{status} (#{seconds}s) — stopping" \
              "#{"; not run: #{rest.join(', ')}" unless rest.empty?}"
          return Report.new(completed: completed, failed_step: step, exit_status: status)
        end
        say "gate: all #{@steps.size} steps green (#{(@clock.call - started).round(1)}s total)"
        Report.new(completed: completed, failed_step: nil, exit_status: 0)
      end

      private

      def timed
        before = @clock.call
        value = yield
        [value, (@clock.call - before).round(1)]
      end

      def tag(index) = "gate: [#{index + 1}/#{@steps.size}]"

      def say(line)
        @out.puts(line)
        @out.flush
      end
    end
  end
end
