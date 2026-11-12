# frozen_string_literal: true

require_relative "duration_format"

module Nabu
  # The preflight gate — the proportionality law's TOOL-side enforcement
  # (architecture §1; the incrementality review, R1).
  #
  # == Why a gate, and why here
  #
  # Every hours-class incident of 2026-11 was SIZEABLE in advance: the
  # history ledger's stage_timings already held the last run's wall time
  # for each index stage, and the duty to read them before firing lived
  # only in session discipline — which failed, twice. So the duty moves
  # into the tool, at the one moment it cannot be skipped: a command about
  # to run inline index work (sync, index refresh) prints its STAGE PLAN —
  # each index stage the refresh runs with its latest ledger time — BEFORE
  # it touches the db, and REFUSES a predicted inline total past
  # BUDGET_SECONDS unless the owner passes --accept-long. Past the budget
  # the work belongs on the maintenance rail or the owner's word, never
  # silently inline.
  #
  # == What the plan reads
  #
  # The refresh's own timed stages (IndexWatcher::REFRESH_STAGES —
  # index_slice / postings_swaps / fts_merge / reflex_closure, all under
  # the source's scope), the LATEST row of each (the ledger's
  # governing-row convention). The closure's older "corpus"-scoped rows
  # timed the corpus-wide closure the sync path no longer runs, so they
  # are deliberately not read. Prediction is honest about its basis: a
  # source with no history plans nothing and passes (first run — no
  # estimate; refusing every first sync would make the gate a wall), and
  # the plan never invents stages it has no row for. The shadow build
  # (Indexer's above-budget path) is deliberately NOT planned: it is an
  # arrival event that fires on the load's size, which the preflight —
  # running before the load — cannot know; it announces and ticks itself.
  module IndexPreflight
    extend DurationFormat

    # The inline budget: past ~15 minutes of predicted index work, a run
    # is a scheduled event, not a sync side-effect (the cost law's ~15-min
    # heavy line, architecture §1, applied per run).
    BUDGET_SECONDS = 15 * 60

    Stage = Data.define(:scope, :stage, :seconds)

    # +total+ is nil when nothing was planned (no history).
    Plan = Data.define(:slug, :stages) do
      def total = stages.empty? ? nil : stages.sum(&:seconds)
    end

    # The refusal: a Nabu::Error, so every CLI surface prints it as one
    # clean sentence and exits 1.
    class Refused < Nabu::Error; end

    module_function

    # The CLI's one call: read the plan for each of +slugs+ through a
    # short read-only ledger handle (no ledger = a fresh box = no
    # history), print every plan to +out+, then refuse the first one past
    # the budget. Runs before the command opens the catalog or the index.
    def gate!(history_path:, slugs:, accept_long:, out: $stderr)
      return if slugs.empty?

      ledger = Store.connect(history_path, readonly: true) if File.exist?(history_path)
      plans = slugs.map { |slug| plan(ledger, slug: slug) }
      # Every plan prints before the first refusal: the owner sees the
      # whole batch's cost, not just the stage that tripped.
      out.puts(plans.flat_map { |each_plan| lines(each_plan) }) if plans.any?(&:total)
      plans.each { |each_plan| check!(each_plan, accept_long: accept_long) }
      nil
    ensure
      ledger&.disconnect
    end

    def plan(ledger, slug:, stages: IndexWatcher::REFRESH_STAGES)
      return Plan.new(slug: slug, stages: []) unless Store::StageTimings.table?(ledger)

      rows = stages.filter_map do |stage|
        last = Store::StageTimings.last(ledger, kind: "sync", scope: slug, stage: stage)
        Stage.new(scope: slug, stage: stage, seconds: last[:seconds].to_f) if last
      end
      Plan.new(slug: slug, stages: rows)
    end

    # The printed plan: one header with the predicted total, one line per
    # stage. Empty when nothing was planned (the non-tty no-estimate rule:
    # "first run — no estimate" on every tiny sync is noise).
    def lines(plan)
      return [] if plan.stages.empty?

      ["index preflight: #{plan.slug} — predicted inline index work " \
       "~#{format_duration(plan.total)} (ledger, latest run per stage):"] +
        plan.stages.map { |row| "  #{row.stage} (#{row.scope}): #{format_duration(row.seconds)}" }
    end

    # Raise Refused when the plan's total passes +budget+ and the owner
    # did not accept a long run; nil otherwise.
    def check!(plan, accept_long:, budget: BUDGET_SECONDS)
      return nil if accept_long || plan.total.nil? || plan.total <= budget

      raise Refused, "index preflight: #{plan.slug}'s predicted inline index work " \
                     "(~#{format_duration(plan.total)}) exceeds the #{format_duration(budget)} inline budget — " \
                     "refusing to start. Pass --accept-long to run it inline now, or schedule it " \
                     "between phases"
    end
  end
end
