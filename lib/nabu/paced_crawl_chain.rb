# frozen_string_literal: true

require_relative "paced_crawl"

module Nabu
  module PacedCrawl
    # The shared multi-slice runner (architecture §19): a standing-slice
    # phase fires THIS instead of an ad-hoc loop of syncs, so the
    # per-iteration assertion is mechanical, never prose. Every slice must
    # progress (yield or frontier movement — the engine already RAISES on a
    # frozen frontier); zero-yield slices are budgeted by the spec's
    # declared stop_after_zero_slices (a refusal desert wider than the
    # budget stops the chain loudly for a human read, instead of burning
    # hours ledgering refusals); the cone's honest end stops it cleanly.
    class Chain
      # reports: every slice's Report, in order. stop_reason: nil on a
      # completed chain, the loud sentence otherwise.
      Summary = Data.define(:reports, :stop_reason) do
        def stalled? = !stop_reason.nil?
        def completed? = stop_reason.nil?
      end

      def initialize(engine:, slices:, log: $stderr)
        @engine = engine
        @slices = Integer(slices)
        raise ArgumentError, "slices must be positive" unless @slices.positive?

        @log = log
      end

      def run!
        reports = []
        zero_streak = 0
        @slices.times do |index|
          report = @engine.slice!
          reports << report
          emit(index, report)
          break if report.classification == :cone_exhausted

          zero_streak = report.zero_yield? ? zero_streak + 1 : 0
          next if zero_streak < budget

          reason = "#{zero_streak} consecutive zero-yield slice(s) — the declared budget " \
                   "(stop_after_zero_slices: #{budget}); read the last report before chaining further"
          @log.puts("CHAIN STOPPED: #{reason}")
          return Summary.new(reports: reports, stop_reason: reason)
        end
        Summary.new(reports: reports, stop_reason: nil)
      end

      private

      def budget
        @engine.spec.schedule.stop_after_zero_slices
      end

      def emit(index, report)
        @log.puts("— slice #{index + 1}/#{@slices} —")
        report.lines.each { |line| @log.puts(line) }
      end
    end
  end
end
