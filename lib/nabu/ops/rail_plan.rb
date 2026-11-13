# frozen_string_literal: true

require_relative "../paced_crawl"
require_relative "../eta"
require_relative "../store/stage_timings"

module Nabu
  module Ops
    # The phase's paced-crawl plan, GENERATED from declarations (the
    # 2026-11-13 chain over-run class: a crawl chain hand-assembled from a
    # board table plus a misremembered backlog concept over-ran a source's
    # intended cadence). The only chain assembly is this reader; `rake
    # rail:plan[BUDGET_MINUTES]` is its thin shell.
    #
    # ROSTER — every registered adapter whose class carries a
    # PacedCrawl::Schedule declaration (a Spec constant's schedule, or a
    # bare Schedule constant), registration order; never a hard-coded
    # list. An adapter declaring several distinct schedules is capped at
    # the STRICTEST slices_per_phase (one sync step runs every lane).
    #
    # MEASURED SLICE TIME — read from the history ledger's stage timings
    # (kind "sync", scope = the slug). One slice = one `bin/nabu sync
    # <slug>` step: its fetch runs one paced slice, then the load (and any
    # inline index stage) follows. A step is the run of rows from a `fetch`
    # row up to the next `fetch` row (ledger id order); it is COMPLETE once
    # it holds a `load` row (a fetch with no load yet is a step in flight
    # or one that died). The slice time is the newest complete step's sum
    # over the FIRST row of each stage in it — a later parse-only sync's
    # second load is not part of the slice. No complete step = "unmeasured"
    # (never an invented number): excluded from the budget math and listed
    # separately.
    #
    # PARALLEL LANES — one lane per source (sources run concurrently,
    # slices within a source sequential). With a budget B, each measured
    # lane plans min(cap, floor(B / slice time)) slices — so every lane,
    # and therefore the parallel wall time (the longest lane), fits B. The
    # declared slices_per_phase is a CAP (upstream politeness), never a
    # quota. With no budget, the caps alone size the plan, unmeasured
    # sources included (their lane wall shows "?").
    #
    # OUTPUT CONTRACT (render) — a header line, the human table (source,
    # cap, slice, planned, lane wall), the unmeasured list, the plan's wall
    # time, then one line per planned slice, grouped by lane in roster
    # order, exactly:
    #
    #   lane <slug> step <N>: <command>
    #
    # (N counts from 1 within the lane; STEP_LINE matches it). A chain
    # runner takes the lines whose first token is "lane", runs each lane's
    # steps in N order, and the lanes concurrently.
    class RailPlan
      STEP_LINE = /\Alane (?<slug>[a-z0-9][a-z0-9-]*) step (?<step>[1-9]\d*): (?<command>\S.*)\z/
      COMMAND = "bin/nabu sync %<slug>s"

      Source = Data.define(:slug, :cap, :slice_seconds, :slices) do
        def measured? = !slice_seconds.nil?
        def lane_seconds = measured? ? slices * slice_seconds : nil
        def command = format(COMMAND, slug: slug)
      end

      # lanes: the measured sources; unmeasured: the rest. budget_seconds
      # nil = the caps-only view.
      Plan = Data.define(:budget_seconds, :lanes, :unmeasured) do
        def all_sources = lanes + unmeasured
        def wall_seconds = lanes.map(&:lane_seconds).max || 0.0
      end

      def initialize(registry:, ledger:, budget_minutes: nil)
        @registry = registry
        @ledger = ledger
        unless budget_minutes.nil? || budget_minutes.to_f.positive?
          raise ArgumentError, "budget must be a positive number of minutes (got #{budget_minutes.inspect})"
        end

        @budget_seconds = budget_minutes && (budget_minutes.to_f * 60)
      end

      def plan
        sources = roster.map { |slug, cap| size(slug, cap, slice_seconds(slug)) }
        Plan.new(budget_seconds: @budget_seconds, lanes: sources.select(&:measured?),
                 unmeasured: sources.reject(&:measured?))
      end

      def self.render(plan)
        out = [header(plan), table(plan)]
        unless plan.unmeasured.empty?
          verdict = plan.budget_seconds ? "excluded from the budget math" : "planned at their caps, wall unknown"
          out << "unmeasured (#{verdict}): #{plan.unmeasured.map(&:slug).join(', ')}"
        end
        out << "plan wall time (parallel lanes): #{Eta.format_seconds(plan.wall_seconds)}"
        out << steps(plan)
        "#{out.reject(&:empty?).join("\n")}\n"
      end

      def self.header(plan)
        return "rail:plan — no budget — the declared caps alone size the plan" unless plan.budget_seconds

        "rail:plan — budget #{Eta.format_seconds(plan.budget_seconds)} of parallel wall time"
      end

      def self.table(plan)
        rows = [["source", "cap", "slice", "planned", "lane wall"]]
        plan.lanes.each do |source|
          rows << [source.slug, source.cap.to_s, Eta.format_seconds(source.slice_seconds), source.slices.to_s,
                   Eta.format_seconds(source.lane_seconds)]
        end
        plan.unmeasured.each do |source|
          planned = plan.budget_seconds ? "-" : source.slices.to_s
          wall = plan.budget_seconds ? "-" : "?"
          rows << [source.slug, source.cap.to_s, "unmeasured", planned, wall]
        end
        widths = rows.transpose.map { |column| column.map(&:length).max }
        rows.map { |row| row.each_with_index.map { |cell, i| cell.ljust(widths[i]) }.join("  ").rstrip }.join("\n")
      end

      def self.steps(plan)
        planned = plan.budget_seconds ? plan.lanes : plan.all_sources
        planned.flat_map do |source|
          (1..source.slices).map { |n| "lane #{source.slug} step #{n}: #{source.command}" }
        end.join("\n")
      end

      private_class_method :header, :table, :steps

      private

      def size(slug, cap, seconds)
        slices = if seconds.nil?
                   @budget_seconds ? 0 : cap
                 elsif @budget_seconds
                   [cap, (@budget_seconds / seconds).floor].min
                 else
                   cap
                 end
        Source.new(slug: slug, cap: cap, slice_seconds: seconds, slices: slices)
      end

      # [[slug, cap]] for every schedule-declaring adapter, registration order.
      def roster
        @registry.each_source.filter_map do |entry|
          klass = adapter_class(entry)
          next unless klass

          caps = schedules(klass).map(&:slices_per_phase)
          [entry.slug, caps.min] unless caps.empty?
        end
      end

      def adapter_class(entry)
        entry.adapter_class
      rescue Nabu::ValidationError
        nil
      end

      def schedules(klass)
        klass.constants(false).filter_map do |name|
          case klass.const_get(name, false)
          in PacedCrawl::Schedule => schedule then schedule
          in PacedCrawl::Spec => spec then spec.schedule
          else nil
          end
        end.compact.uniq
      end

      def slice_seconds(slug)
        return nil unless Store::StageTimings.table?(@ledger)

        rows = @ledger[Store::StageTimings::TABLE].where(kind: "sync", scope: slug)
                                                  .order(:id).select(:stage, :seconds).all
        steps = rows.slice_before { |row| row[:stage] == "fetch" }.select { |step| step.first[:stage] == "fetch" }
        step = steps.reverse.find { |rows_of_step| rows_of_step.any? { |row| row[:stage] == "load" } }
        return nil unless step

        step.uniq { |row| row[:stage] }.sum { |row| row[:seconds].to_f }
      end
    end
  end
end
