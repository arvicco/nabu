# frozen_string_literal: true

require_relative "../duration_format"

module Nabu
  module Health
    # The health board's signal/noise policy (P98-1 — Q71, owner ask at the
    # P97 board read: 185 rows drowned the 3 that mattered). The default
    # view prints FINDINGS ONLY — ok rows and the by-design notes (a
    # feature module's no-rows note, an empty owner shelf) fold into ONE
    # rollup line; `--all` restores the full board unchanged. The verdict
    # is ONE line carrying elapsed (the Q69 standing rule); the CLI says it
    # on the quiet path and raises it on the loud one — never both.
    module BoardView
      extend DurationFormat

      # Info notes that are BY-DESIGN states, not findings: suppressed by
      # default, counted in the rollup. never_synced stays visible — an
      # actionable state, not a designed one.
      BY_DESIGN_NOTES = %i[module_no_rows shelf_empty].freeze

      module_function

      def visible(sources, all: false)
        return sources if all

        sources.reject { |check| suppressed?(check) }
      end

      # An ok row, or a row whose every finding is a by-design note.
      def suppressed?(check)
        check.findings.empty? ||
          check.findings.all? { |finding| BY_DESIGN_NOTES.include?(finding.kind) }
      end

      def rollup(sources)
        ok = sources.count { |check| check.findings.empty? }
        notes = sources.count { |check| !check.findings.empty? && suppressed?(check) }
        soft = sources.sum { |check| check.findings.count(&:soft?) }
        loud = sources.sum { |check| check.findings.count(&:loud?) }
        "#{ok} ok · #{soft} warning · #{loud} anomaly · #{notes} by-design notes suppressed " \
          "(feature modules, empty shelves) — `--all` shows every row"
      end

      # Report-level: counts include golden losses and global findings, so
      # the verdict and the exit code always agree.
      def verdict(report, seconds:)
        elapsed = BoardView.format_duration(seconds)
        if report.any_loud?
          softs = report.soft_count.positive? ? ", #{report.soft_count} warning(s)" : ""
          "health: #{report.loud_count} anomaly finding(s)#{softs} — see above (#{elapsed})"
        elsif report.soft_count.positive?
          "health: OK, #{report.soft_count} warning(s) (#{elapsed})"
        else
          "health: OK (#{elapsed})"
        end
      end
    end
  end
end
