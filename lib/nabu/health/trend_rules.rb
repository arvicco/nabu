# frozen_string_literal: true

require "time"

module Nabu
  module Health
    # A single anomaly finding produced by a trend rule. +severity+ drives the
    # exit code and the label the CLI prints:
    #
    #   :loud — a red finding; `nabu health` exits 1 (quarantine spike, >15%
    #           withdrawal creep, a lost golden query, a >15% single-sync sweep).
    #   :soft — an advisory warning; exit stays 0 (added collapse, 5–15% creep,
    #           a stale source). Something to eyeball, not an emergency.
    #   :info — purely informational (a never-synced source); never affects exit.
    Finding = Data.define(:kind, :severity, :message) do
      def loud? = severity == :loud
      def soft? = severity == :soft
    end

    # The trend rules: pure functions over run-history / document-count numbers,
    # shared by `nabu health` (LocalCheck, replaying a source's whole history)
    # and `nabu sync` (SyncRunner, checking a single fresh LoadReport). Thresholds
    # live here ONCE so both callers agree; each rule returns a Finding or nil.
    #
    # == Quarantine spike (:loud)
    #
    # The latest successful run quarantined "notably" more documents than the
    # source's recent norm. "Notably" is deliberately two-part so that a corpus
    # that normally quarantines nothing does not scream at the first stray error:
    #
    #   latest_errored > max(prior_errored)   AND   latest_errored > SPIKE_FLOOR
    #
    # The max-of-window guard catches a genuine regression against THIS source's
    # baseline; the absolute floor suppresses small-number noise (0→1, 2→3). With
    # no prior successful run there is no norm to exceed, so a first sync is never
    # a spike (a bad first import is a different, human-watched event).
    #
    # == Added collapse (:soft)
    #
    # The last COLLAPSE_RUNS successful runs all added 0 AND updated 0, while some
    # earlier run was active — "possibly a stale upstream pin or a dead pipeline."
    # Soft on purpose: a genuinely quiet corpus reads the same way (maintenance
    # §2's "0,0,0 for a year → candidate for frozen"), so this is a nudge to look,
    # not a failure. The "historically active" guard means a brand-new source with
    # three empty runs never trips (it was never active to collapse FROM).
    #
    # == Withdrawal / retirement creep (:soft >5%, :loud >15%)
    #
    # The cumulative fraction of a source's documents that are withdrawn or
    # retired-upstream. The per-sync 20% breaker only sees one sync; slow bleed
    # (2% a sync for ten syncs) slips under it, so this watches the running total.
    # >15% is loud, 5–15% soft. Reused verbatim by the single-sync sweep check.
    #
    # == Stale source (:soft)
    #
    # An enabled, live-policy source whose last successful sync is older than the
    # cadence expectation (STALE_AFTER_DAYS). Manual/frozen sources are expected
    # to sit still, so only live ones are eligible (the caller gates that).
    module TrendRules
      module_function

      # Absolute floor a spike must clear on top of beating the prior max, so a
      # normally-clean source's stray quarantine (0→1, 2→7) is not "notable".
      SPIKE_FLOOR = 10
      # How many prior successful runs form the "recent norm" the spike beats.
      SPIKE_WINDOW = 5
      # Consecutive most-recent all-zero (added AND updated) runs that, given
      # prior activity, read as a collapsed pipeline.
      COLLAPSE_RUNS = 3
      # Cumulative withdrawn+retired fraction thresholds (soft / loud).
      CREEP_SOFT_FRACTION = 0.05
      CREEP_LOUD_FRACTION = 0.15
      # A live source unsynced longer than this is stale (a constant, not config
      # plumbing — maintenance §1's weekly cadence with slack).
      STALE_AFTER_DAYS = 14

      # +prior_errored+: errored counts of up to SPIKE_WINDOW successful runs
      # before the latest (any order — only their max matters).
      def quarantine_spike(latest_errored:, prior_errored:)
        return nil if latest_errored <= SPIKE_FLOOR
        return nil if prior_errored.empty?
        return nil unless latest_errored > prior_errored.max

        Finding.new(
          kind: :quarantine_spike, severity: :loud,
          message: "quarantine spike: #{latest_errored} errored this run vs a recent max of " \
                   "#{prior_errored.max} — parser or upstream regression?"
        )
      end

      # +successful_runs+: newest-first array of { added:, updated: } for every
      # successful run of the source.
      def added_collapse(successful_runs:)
        return nil if successful_runs.size < COLLAPSE_RUNS

        latest = successful_runs.first(COLLAPSE_RUNS)
        return nil unless latest.all? { |run| run[:added].zero? && run[:updated].zero? }
        return nil unless successful_runs.drop(COLLAPSE_RUNS).any? { |run| !run[:added].zero? || !run[:updated].zero? }

        Finding.new(
          kind: :added_collapse, severity: :soft,
          message: "added collapse: #{COLLAPSE_RUNS} runs with 0 added and 0 updated after prior activity — " \
                   "stale upstream pin or dead pipeline?"
        )
      end

      # Cumulative shed (withdrawn OR retired) fraction of the source's documents.
      def withdrawal_creep(shed:, total:)
        severity = creep_severity(shed: shed, total: total)
        return nil unless severity

        Finding.new(
          kind: :withdrawal_creep, severity: severity,
          message: "withdrawal creep: #{shed}/#{total} documents (#{percent(shed, total)}) " \
                   "withdrawn or retired — upstream is shedding content"
        )
      end

      # One sync's own withdrawal sweep as a fraction of the source's documents;
      # reuses the creep thresholds (the >20% band already aborts in the breaker,
      # so this warns in the 5–20% no-abort band). Used by SyncRunner.
      def sync_withdrawal(withdrawn:, total:)
        severity = creep_severity(shed: withdrawn, total: total)
        return nil unless severity

        Finding.new(
          kind: :mass_withdrawal, severity: severity,
          message: "this sync withdrew #{withdrawn}/#{total} documents (#{percent(withdrawn, total)})"
        )
      end

      # +last_sync_at+ may be nil (never synced — handled as its own signal, not
      # stale). +now+ is injected so tests pin the clock.
      def stale_source(last_sync_at:, now:)
        return nil if last_sync_at.nil?

        age_days = (now - to_time(last_sync_at)) / 86_400.0
        return nil unless age_days > STALE_AFTER_DAYS

        Finding.new(
          kind: :stale, severity: :soft,
          message: "stale: last synced #{age_days.floor} days ago (> #{STALE_AFTER_DAYS}) — cadence slipped?"
        )
      end

      def creep_severity(shed:, total:)
        return nil if total.zero?

        fraction = shed.to_f / total
        return :loud if fraction > CREEP_LOUD_FRACTION
        return :soft if fraction > CREEP_SOFT_FRACTION

        nil
      end

      def percent(part, whole) = format("%.1f%%", 100.0 * part / whole)

      # SQLite hands timestamps back as Time already, but a String slips through
      # from some drivers/paths; parse defensively so stale math never crashes.
      def to_time(value) = value.is_a?(Time) ? value : Time.parse(value.to_s)
    end
  end
end
