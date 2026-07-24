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
    # there). The creep-acceptance readers (ledger migration 008, P43-0)
    # follow the same convention: a pre-008 ledger reads as "no acceptances".
    module QuarantineBaseline
      TABLE = :quarantine_baselines
      # Owner creep acceptances (P43-0/D42-c): append-only history, the LATEST
      # row governs. Written only by `nabu health --accept-creep`.
      ACCEPTANCES_TABLE = :creep_acceptances

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

      # The health-time cumulative check: baseline drift above the anchor —
      # acceptance-aware (P43-0). The comparison rule, designed against three
      # requirements (quiet the accepted total; re-alarm on growth past it;
      # never mask creep after a RECOVERY below it): the latest accepted
      # baseline serves as an anchor-FLOOR iff it sits at or below the current
      # baseline; when the baseline has recovered BELOW the accepted value (a
      # parser fix), the acceptance goes dormant and the plain low-water rule
      # resumes. TrendRules.quarantine_creep stays a pure function — it just
      # receives the effective anchor. When the acceptance is actively
      # quieting a would-be anomaly, an info-grade note says so: quiet is
      # never silent.
      def creep_finding(ledger, slug)
        row = read(ledger, slug)
        return nil if row.nil?

        plain = TrendRules.quarantine_creep(baseline: row[:baseline], anchor: row[:anchor])
        acceptance = latest_acceptance(ledger, slug)
        return plain if acceptance.nil? || acceptance[:accepted_baseline] > row[:baseline]

        effective = TrendRules.quarantine_creep(
          baseline: row[:baseline], anchor: [row[:anchor], acceptance[:accepted_baseline]].max
        )
        return effective unless effective.nil? # growth past the accepted level: re-armed
        return nil if plain.nil?               # nothing to quiet — the acceptance is idle

        accepted_note(acceptance)
      end

      # Record the owner's acceptance of +slug+'s CURRENT baseline (P43-0).
      # Append-only — the latest row governs. Returns the accepted baseline,
      # or nil when there is no recorded baseline to accept (the caller names
      # that error) or the ledger predates migration 008 (honest decline,
      # the record! convention).
      def accept!(ledger, slug, note: nil, now: Time.now)
        row = read(ledger, slug)
        return nil if row.nil? || !acceptances_table?(ledger)

        ledger[ACCEPTANCES_TABLE].insert(
          source_slug: slug, accepted_baseline: row[:baseline], note: note, recorded_at: now
        )
        row[:baseline]
      end

      # The governing (latest) acceptance for +slug+, or nil — including on a
      # nil or pre-008 ledger ("no acceptances", the module convention).
      def latest_acceptance(ledger, slug)
        return nil unless acceptances_table?(ledger)

        ledger[ACCEPTANCES_TABLE].where(source_slug: slug)
                                 .order(Sequel.desc(:id))
                                 .select(:accepted_baseline, :note, :recorded_at)
                                 .first
      end

      def accepted_note(acceptance)
        stamp = TrendRules.to_time(acceptance[:recorded_at]).strftime("%Y-%m-%d")
        Finding.new(
          kind: :quarantine_creep_accepted, severity: :info,
          message: "quarantine creep accepted at #{acceptance[:accepted_baseline]} (owner, #{stamp}) — " \
                   "the alarm re-arms past that level"
        )
      end

      def table?(ledger)
        !ledger.nil? && ledger.table_exists?(TABLE)
      end

      def acceptances_table?(ledger)
        !ledger.nil? && ledger.table_exists?(ACCEPTANCES_TABLE)
      end
    end
  end
end
