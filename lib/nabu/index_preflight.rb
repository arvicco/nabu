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
  # the plan never invents stages it has no row for.
  #
  # == The shadow build: delta-engaged is not delta-priced
  #
  # A sync's shadow build (Indexer's above-budget path) is an arrival
  # event that fires on the load's size, which the sync preflight —
  # running before the load — cannot know; there it announces and ticks
  # itself. An `index refresh` is different: its load already landed, so
  # the shadow is PREDICTABLE (Indexer.fts_shadow_forecasts reads the
  # state the run decides on), and it must be — the refreshed slices are
  # the delta, but the shadow is the whole index (MEASURED 2026-11-21: a
  # wave whose slices priced ~13m ran an hour-long ~95M-row shadow build,
  # the fts governor consolidating the fresh shadow inside it; the
  # watcher's slice-priced deadline killed it three times, and every kill
  # discarded the whole build — kill + retry restarted from zero). So
  # the refresh hands its forecast to gate!, which prices each predicted
  # build as its own stage, "fts_shadow" — the latest fts_shadow row of
  # ANY scope (the cost is the shadow's size, not whose refresh triggered
  # it), scaled by the rows it recorded when it recorded them; with no
  # row at all, a conservative floor from the forecast's row count
  # (SHADOW_FLOOR_ROWS_PER_SECOND) — and returns the priced stages so the
  # watcher's deadline covers slices + shadow together. And it refuses
  # up front (check_shadow!) whenever a kill would land inside the stage
  # or the run is long and unaccepted, naming the stage, its price, and
  # the flags that proceed.
  #
  # == The full-rebuild fallback
  #
  # A refresh against a fulltext that is not incremental-ready (a table
  # missing, or one predating its current shape — Indexer.incremental_ready?)
  # does not refresh a slice at all: it falls back to Indexer.rebuild!,
  # the WHOLE index (~4h13m on the live corpus). That path is as
  # predictable as the shadow, so the caller says so (+fallback+) and the
  # gate prices it as its own stage, "index_rebuild" — the summed latest
  # rows of the rebuild's corpus index stages (Eta.for_stages over
  # Rebuild::INDEX_ETA_STAGES, the read the rebuild's own banner
  # carries). It refuses on the shadow's terms (check_fallback!): past the
  # budget without --accept-long, or an explicit --deadline that cannot
  # cover it. With no rebuild history it announces "first run — no
  # estimate" and proceeds (a fresh box's first sync builds the index this
  # way; refusing it would make the gate a wall).
  module IndexPreflight
    extend DurationFormat

    # The inline budget: past ~15 minutes of predicted index work, a run
    # is a scheduled event, not a sync side-effect (the cost law's ~15-min
    # heavy line, architecture §1, applied per run).
    BUDGET_SECONDS = 15 * 60

    # +ledgered+/+basis+ describe a PRICED stage (the forecast shadow):
    # whether a ledger row priced it, and the one-clause account of how.
    Stage = Data.define(:scope, :stage, :seconds, :ledgered, :basis) do
      def initialize(scope:, stage:, seconds:, ledgered: true, basis: nil) = super
    end

    # The forecast shadow's ledger stage (Indexer's timed fts_shadow).
    SHADOW_STAGE = "fts_shadow"

    # The full-rebuild fallback's priced stage (the fallback note).
    FALLBACK_STAGE = "index_rebuild"

    # The first-run floor for a shadow build with no ledger row: rows per
    # second, deliberately slow. MEASURED: the clean 2026-11-22 wave wrote
    # a ~95M-row shadow in about an hour on a quiet box (its 73m33s less
    # the ~13m its slices priced — ~26k rows/s);
    # the floor sits well under that so contention (a parallel suite
    # shared the box at one of the kills) cannot outrun it.
    SHADOW_FLOOR_ROWS_PER_SECOND = 15_000

    # The least an explicit --deadline may be against a forecast shadow:
    # COVER_MARGIN × the priced total, in whole minutes rounded up. A
    # deadline merely above the estimate is no cover — MEASURED: a 75m
    # deadline against a run whose clean quiet-box wall was 73m33s still
    # died at the deadline, the box shared with a parallel test suite.
    # Contention is the margin's job; the 2.5× the refusal suggests
    # (IndexWatcher::DEADLINE_FACTOR) stays the comfortable value.
    COVER_MARGIN = 1.25

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
    # the budget. Runs before the command opens the catalog or the index
    # for writing (the shadow forecast reads them through read-only handles).
    #
    # +shadows+ (Indexer::ShadowForecast list — `index refresh` only) are
    # priced as stages of their own, printed with the plans, and checked
    # against +deadline_minutes+ (the command's --deadline; nil = none)
    # by check_shadow!. +fallback+ (the fallback note): the run will take
    # the full-rebuild fallback — priced, printed and checked
    # (check_fallback!) as the "index_rebuild" stage. Returns the priced
    # stages (shadows, then the fallback; empty without either), whose
    # seconds the caller adds to the watcher's estimate.
    def gate!(history_path:, slugs:, accept_long:, out: $stderr, shadows: [], deadline_minutes: nil,
              fallback: false)
      return [] if slugs.empty?

      ledger = Store.connect(history_path, readonly: true) if File.exist?(history_path)
      plans = slugs.map { |slug| plan(ledger, slug: slug) }
      priced = shadows.map { |forecast| price_shadow(ledger, forecast) }
      rebuild = price_fallback(ledger) if fallback
      # Every plan prints before the first refusal: the owner sees the
      # whole batch's cost, not just the stage that tripped.
      out.puts(plans.flat_map { |each_plan| lines(each_plan) }) if plans.any?(&:total)
      out.puts(shadows.zip(priced).map { |forecast, stage| shadow_line(forecast, stage) }) unless priced.empty?
      out.puts(fallback_line(rebuild)) if rebuild
      check_fallback!(rebuild, accept_long: accept_long, deadline_minutes: deadline_minutes) if rebuild
      check_shadow!(plans, shadows, priced, accept_long: accept_long, deadline_minutes: deadline_minutes)
      plans.each { |each_plan| check!(each_plan, accept_long: accept_long) }
      rebuild ? priced + [rebuild] : priced
    ensure
      ledger&.disconnect
    end

    # The fallback priced as a Stage (the fallback note): the rebuild's
    # measured corpus index stages summed, or an unledgered zero-second
    # stage when the ledger has none.
    def price_fallback(ledger)
      eta = Eta.for_stages(ledger, kind: "rebuild", scope: "corpus", stages: Rebuild::INDEX_ETA_STAGES)
      if eta.none?
        return Stage.new(scope: "corpus", stage: FALLBACK_STAGE, seconds: 0.0, ledgered: false, basis: eta.render)
      end

      Stage.new(scope: "corpus", stage: FALLBACK_STAGE, seconds: eta.seconds.to_f, ledgered: true,
                basis: "ledger: the last rebuild's corpus index stages (#{Rebuild::INDEX_ETA_STAGES.join(' + ')})")
    end

    def fallback_line(stage)
      price = stage.ledgered ? "~#{format_duration(stage.seconds)} (#{stage.basis})" : stage.basis
      "index preflight: predicted #{FALLBACK_STAGE} (corpus) — the fulltext index is not incremental-ready " \
        "(a table missing or predating its shape), so the refresh falls back to the FULL index rebuild: #{price}"
    end

    # The fallback's refusal (the fallback note): an explicit positive
    # --deadline under the margined cover, or — without --accept-long — a
    # priced total past +budget+. An unledgered fallback proceeds.
    def check_fallback!(stage, accept_long:, deadline_minutes:, budget: BUDGET_SECONDS)
      return nil unless stage.ledgered

      total = stage.seconds
      reason =
        if deadline_minutes.to_f.positive? && deadline_minutes.to_f < cover_minutes(total)
          "--deadline #{format_minutes(deadline_minutes)} cannot cover it (under the #{cover_minutes(total)}-minute " \
            "minimum, #{COVER_MARGIN}x the priced total)"
        elsif !accept_long && total > budget
          "the total is past the #{format_duration(budget)} inline budget"
        end
      return nil if reason.nil?

      minutes = [(total * IndexWatcher::DEADLINE_FACTOR / 60).ceil, IndexWatcher::MIN_DEADLINE_SECONDS / 60].max
      raise Refused, "index preflight: this refresh falls back to the FULL index rebuild (the fulltext index is " \
                     "not incremental-ready) — stage #{FALLBACK_STAGE} (corpus), the whole index rebuilt, priced " \
                     "~#{format_duration(total)} (#{stage.basis}); #{reason}, so refusing to start. Proceed with " \
                     "--deadline #{minutes} --accept-long (#{IndexWatcher::DEADLINE_FACTOR}x the priced total), " \
                     "or --deadline 0 --accept-long (never kill) — or schedule it as an owner-fired rebuild"
    end

    # One forecast shadow priced as a Stage (class note): the latest
    # fts_shadow row of any scope — scaled by the forecast's rows when the
    # row recorded its own — else the floor from the forecast's size.
    def price_shadow(ledger, forecast)
      last = latest_shadow_row(ledger)
      if last.nil?
        return Stage.new(scope: forecast.scope, stage: SHADOW_STAGE,
                         seconds: forecast.rows.to_f / SHADOW_FLOOR_ROWS_PER_SECOND, ledgered: false,
                         basis: "UNPRICED — no #{SHADOW_STAGE} row in the ledger; conservative floor at " \
                                "#{Eta.commas(SHADOW_FLOOR_ROWS_PER_SECOND)} rows/s")
      end

      scalable = last[:rows]&.positive?
      seconds = scalable ? last[:seconds] * forecast.rows / last[:rows].to_f : last[:seconds].to_f
      basis = "ledger: last run #{format_duration(last[:seconds])}"
      basis += " over #{Eta.commas(last[:rows])} rows; scaled for #{Eta.commas(forecast.rows)}" if scalable
      Stage.new(scope: forecast.scope, stage: SHADOW_STAGE, seconds: seconds, ledgered: true, basis: basis)
    end

    def latest_shadow_row(ledger)
      return nil unless Store::StageTimings.table?(ledger)

      ledger[Store::StageTimings::TABLE].where(kind: "sync", stage: SHADOW_STAGE)
                                        .order(Sequel.desc(:id)).select(:seconds, :rows).first
    end

    def shadow_line(forecast, stage)
      "index preflight: predicted #{describe_shadow(forecast)} — the passages_fts shadow build over " \
        "~#{Eta.commas(forecast.rows)} rows: ~#{format_duration(stage.seconds)} (#{stage.basis})"
    end

    def describe_shadow(forecast)
      members = forecast.scope == "corpus" ? " — #{forecast.slugs.join(' + ')}" : ""
      "#{SHADOW_STAGE} (#{forecast.scope}#{members})"
    end

    # The honest refusal for a forecast shadow (class note). A kill inside
    # the stage discards the whole build, so the run refuses when:
    #   - an explicit positive --deadline is under cover_minutes — the
    #     priced total (slices + shadow) with COVER_MARGIN on top: the
    #     kill would land inside the stage, --accept-long or not;
    #   - without --accept-long, the priced total passes +budget+, or the
    #     shadow is UNPRICED (no ledger row — the floor is a guess, not
    #     evidence) and no explicit --deadline sized the run.
    # Otherwise it proceeds; a computed deadline (DEADLINE_FACTOR × the
    # priced total) covers the total by construction.
    def check_shadow!(plans, shadows, priced, accept_long:, deadline_minutes:, budget: BUDGET_SECONDS)
      return nil if priced.empty?

      total = plans.sum { |each_plan| each_plan.total || 0 } + priced.sum(&:seconds)
      reason =
        if deadline_minutes.to_f.positive? && deadline_minutes.to_f < cover_minutes(total)
          "--deadline #{format_minutes(deadline_minutes)} cannot cover it (under the #{cover_minutes(total)}-minute " \
            "minimum, #{COVER_MARGIN}x the priced total: the kill would land inside the stage)"
        elsif accept_long
          nil
        elsif total > budget
          "the total is past the #{format_duration(budget)} inline budget"
        elsif deadline_minutes.nil? && priced.any? { |stage| !stage.ledgered }
          "no ledger row prices it yet"
        end
      return nil if reason.nil?

      raise Refused, shadow_refusal(shadows, priced, total, reason, long: total > budget)
    end

    def shadow_refusal(shadows, priced, total, reason, long:)
      stages = shadows.zip(priced).map do |forecast, stage|
        price = stage.ledgered ? "priced ~#{format_duration(stage.seconds)} (#{stage.basis})" : stage.basis
        "stage #{describe_shadow(forecast)}, the whole index rewritten append-only over " \
          "~#{Eta.commas(forecast.rows)} rows with the fts governor's consolidation inside it — #{price}"
      end
      minutes = [(total * IndexWatcher::DEADLINE_FACTOR / 60).ceil, IndexWatcher::MIN_DEADLINE_SECONDS / 60].max
      sized = "--deadline #{minutes}#{' --accept-long' if long}"
      "index preflight: this refresh will run the passages_fts shadow build — #{stages.join('; ')}; " \
        "predicted total with the slices ~#{format_duration(total)}, and #{reason}. A kill inside the " \
        "stage discards the whole build (the retry restarts it from zero), so refusing to start. " \
        "Proceed with #{sized} (#{IndexWatcher::DEADLINE_FACTOR}x the priced total; no explicit deadline " \
        "under #{cover_minutes(total)} is accepted — #{COVER_MARGIN}x), or " \
        "--deadline 0 --accept-long (never kill)"
    end

    # The least explicit --deadline (minutes) that covers +total+ seconds.
    def cover_minutes(total) = (total * COVER_MARGIN / 60).ceil

    def format_minutes(minutes)
      value = minutes.to_f
      value == value.floor ? value.to_i.to_s : value.to_s
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
