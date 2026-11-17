# frozen_string_literal: true

module Nabu
  module Ops
    # One rail-plan step (`rake "rail:step[SLUG]"`, the command every
    # RailPlan lane line runs): the source's sync wrapped in the
    # per-iteration yield assertion. A bare `bin/nabu sync` chain has no
    # notion of yield — the P177 rail ran three identical zero-added steps
    # per lane — so the step reads every paced lane's OFFLINE diagnosis
    # (PacedCrawl::Engine#diagnose: universe, held?, the on-disk ledger; no
    # request) before and after the sync and judges the step:
    #
    #   :yield      — the held count grew and something is left to select:
    #                 the lane continues;
    #   :zero_yield — nothing new held: the lane STOPS here (a further
    #                 step would replay the same empty slice);
    #   :exhausted  — nothing is left to select after the step (whatever it
    #                 yielded): the lane STOPS, a further step can only be
    #                 zero-yield.
    #
    # The rake shell turns a stop into a nonzero exit, so the plan's `&&`
    # chain breaks there. Yield is summed across a source's lanes (one sync
    # runs them all).
    class RailStep
      Verdict = Data.define(:slug, :status, :held_before, :held_after, :remaining) do
        def added = held_after - held_before
        def stop? = status != :yield

        def line
          case status
          when :yield
            "rail:step #{slug}: +#{added} held (#{held_before} → #{held_after}), #{remaining} remaining — " \
            "the lane continues"
          when :zero_yield
            "rail:step #{slug}: ZERO YIELD — held unchanged at #{held_after} (#{remaining} remaining); " \
            "the lane stops here (per-iteration yield: read the sync's slice report before chaining further)"
          else
            "rail:step #{slug}: cone exhausted — +#{added} held (#{held_before} → #{held_after}), nothing " \
            "left to select; the lane stops here"
          end
        end
      end

      # engines: {lane name => PacedCrawl::Engine} (the adapter's
      # #paced_crawls); sync: the step's sync, called once.
      def initialize(slug:, engines:, sync:)
        raise ArgumentError, "#{slug} has no paced-crawl lane — rail:step guards paced syncs only" if engines.empty?

        @slug = slug
        @engines = engines.values
        @sync = sync
      end

      def run!
        held_before = diagnoses.sum(&:held_count)
        @sync.call
        after = diagnoses
        held_after = after.sum(&:held_count)
        remaining = after.sum(&:remaining_count)
        status = if remaining.zero? then :exhausted
                 elsif held_after > held_before then :yield
                 else :zero_yield
                 end
        Verdict.new(slug: @slug, status: status, held_before: held_before, held_after: held_after,
                    remaining: remaining)
      end

      private

      def diagnoses = @engines.map(&:diagnose)
    end
  end
end
