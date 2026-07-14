# frozen_string_literal: true

require_relative "trend_rules"

module Nabu
  module Health
    # Storage side of the quarantine baseline (ledger migration 005; the rule
    # logic is TrendRules.quarantine_delta / .quarantine_creep — pure functions,
    # thresholds live there ONCE). One row per source in the ledger's
    # quarantine_baselines table:
    #
    #   baseline — errored count of the most recent OK sync/rebuild run;
    #              auto-advances at every ok run (each change announced once).
    #   anchor   — the low-water mark; advances DOWNWARD only, so `nabu
    #              health` can see the cumulative creep the advancing baseline
    #              absorbs step by step (see the migration's advance-rule note).
    #
    # Every reader degrades honestly: a nil ledger (fresh machine) or a
    # pre-005 ledger (read paths never migrate) reads as "no baseline", and
    # record! silently declines rather than crashing a sync against an old
    # ledger file (write paths migrate first, so in practice the table is
    # there).
    module QuarantineBaseline
      TABLE = :quarantine_baselines

      module_function

      # The recorded {baseline:, anchor:} for +slug+, or nil.
      def read(ledger, slug)
        return nil unless table?(ledger)

        ledger[TABLE].where(source_slug: slug).select(:baseline, :anchor).first
      end

      # Record an OK run's errored count: baseline advances always, anchor only
      # downward (first recording sets both). +now+ injectable for tests.
      def record!(ledger, slug, errored:, now: Time.now)
        return unless table?(ledger)

        row = ledger[TABLE].where(source_slug: slug).first
        if row
          ledger[TABLE].where(id: row[:id])
                       .update(baseline: errored, anchor: [row[:anchor], errored].min, recorded_at: now)
        else
          ledger[TABLE].insert(source_slug: slug, baseline: errored, anchor: errored, recorded_at: now)
        end
      end

      # The sync/rebuild-end warning for a fresh ok run: delta vs the recorded
      # baseline (nil when unchanged). Call BEFORE record! — the comparison is
      # against the PREVIOUS ok run's level.
      def delta_finding(ledger, slug, errored:)
        TrendRules.quarantine_delta(errored: errored, baseline: read(ledger, slug)&.fetch(:baseline))
      end

      # The health-time cumulative check: baseline drift above the anchor.
      def creep_finding(ledger, slug)
        row = read(ledger, slug)
        return nil if row.nil?

        TrendRules.quarantine_creep(baseline: row[:baseline], anchor: row[:anchor])
      end

      def table?(ledger)
        !ledger.nil? && ledger.table_exists?(TABLE)
      end
    end
  end
end
