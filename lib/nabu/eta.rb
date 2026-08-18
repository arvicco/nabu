# frozen_string_literal: true

module Nabu
  # The estimate a stage announcement carries (P78-r2, Q34: every long pass
  # should say how long it expects to run). Reads the P78-r1 stage_timings
  # history (Store::StageTimings — latest row governs), scales by row-count
  # drift when the caller has a cheap current denominator (the era-bound-
  # constants rule: a historical number silently ages unless the work size
  # rides with it), and answers "first run — no estimate" when there is no
  # history to speak from — an honest absence, never a guess.
  #
  # Pure lookup + formatting: no IO, no printing. The runners attach an
  # estimate to ProgressReporter#stage; the CLI decides how it renders.
  module Eta
    # A speakable estimate. +seconds+ is the prediction (basis, drift-scaled
    # when +scaled_rows+ is set); +basis_seconds+/+basis_rows+ the recorded
    # run it derives from.
    Estimate = Data.define(:seconds, :basis_seconds, :basis_rows, :scaled_rows) do
      def initialize(seconds:, basis_seconds:, basis_rows: nil, scaled_rows: nil)
        super
      end

      def none? = false

      def render
        basis = "last run #{Eta.format_seconds(basis_seconds)}"
        basis += " over #{Eta.commas(basis_rows)} rows" if basis_rows
        basis += "; scaled for #{Eta.commas(scaled_rows)}" if scaled_rows
        "~#{Eta.format_seconds(seconds)} (#{basis})"
      end
    end

    # The honest empty answer — renders as itself so the CLI never has to
    # distinguish "no history" from "history" at the print site.
    NONE = Object.new.tap do |none|
      def none.none? = true
      def none.render = "first run — no estimate"
      def none.seconds = nil
    end.freeze

    module_function

    # The estimate for one (kind, scope, stage), or NONE. +rows+ is the
    # caller's current work size — given, and with a recorded denominator to
    # scale against, the estimate stretches with the drift.
    def for(ledger, kind:, scope:, stage:, rows: nil)
      last = Store::StageTimings.last(ledger, kind: kind, scope: scope, stage: stage)
      return NONE if last.nil?

      scalable = rows && last[:rows]&.positive?
      Estimate.new(
        seconds: scalable ? last[:seconds] * rows / last[:rows].to_f : last[:seconds],
        basis_seconds: last[:seconds], basis_rows: last[:rows],
        scaled_rows: scalable ? rows : nil
      )
    end

    # The summed estimate for an umbrella stage that spans several recorded
    # sub-stages (rebuild's "fulltext index" covers fts_lemma…reflex).
    # Recorded sub-stages sum; absent ones add nothing; none recorded = NONE.
    def for_stages(ledger, kind:, scope:, stages:)
      recorded = stages.filter_map do |stage|
        Store::StageTimings.last(ledger, kind: kind, scope: scope, stage: stage)
      end
      return NONE if recorded.empty?

      total = recorded.sum { |row| row[:seconds] }
      Estimate.new(seconds: total, basis_seconds: total)
    end

    # The sync banner's estimate: the last succeeded, finished sync run's
    # duration from the ledger runs history (it already answers — P78-r1
    # persists nothing sync-side). nil when no such run: an explicit sync of
    # a new source already narrates plenty, so the banner just stays silent.
    def last_sync(ledger, slug:)
      return nil if ledger.nil? || !ledger.table_exists?(:runs)

      run = ledger[:runs].where(source_slug: slug, kind: "sync", status: "succeeded")
                         .exclude(finished_at: nil)
                         .order(Sequel.desc(:id))
                         .select(:started_at, :finished_at)
                         .first
      return nil if run.nil?

      seconds = run[:finished_at] - run[:started_at]
      Estimate.new(seconds: seconds, basis_seconds: seconds)
    end

    # "48s" / "5m48s" / "1h04m" — coarse on purpose: an estimate that names
    # sub-second precision would be claiming knowledge it doesn't have.
    def format_seconds(secs)
      secs = secs.round
      return "#{secs}s" if secs < 60
      if secs < 3600
        return (secs % 60).zero? ? "#{secs / 60}m" : "#{secs / 60}m#{format('%02d', secs % 60)}s"
      end

      minutes = (secs % 3600) / 60
      minutes.zero? ? "#{secs / 3600}h" : "#{secs / 3600}h#{format('%02d', minutes)}m"
    end

    def commas(count)
      count.to_s.gsub(/\B(?=(\d{3})+\z)/, ",")
    end
  end
end
