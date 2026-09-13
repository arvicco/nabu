# frozen_string_literal: true

require "test_helper"

module Health
  # Nabu::Health::BoardView (P98-1 — Q71): the board's signal/noise policy.
  # Default view = findings only (ok rows + by-design notes fold into one
  # rollup line); `--all` restores every row; the verdict is one line with
  # elapsed. The suppression is a VIEW policy — the underlying report keeps
  # every row, so `--all` is byte-compatible with the pre-P98 board.
  class BoardViewTest < Minitest::Test
    Finding = Nabu::Health::Finding
    Check = Nabu::Health::LocalCheck::SourceCheck

    def ok(slug) = Check.new(slug: slug, findings: [])

    def noted(slug, kind)
      Check.new(slug: slug, findings: [Finding.new(kind: kind, severity: :info, message: "m")])
    end

    def warned(slug)
      Check.new(slug: slug, findings: [Finding.new(kind: :stale, severity: :soft, message: "m")])
    end

    def spiky(slug)
      Check.new(slug: slug, findings: [Finding.new(kind: :quarantine_spike, severity: :loud, message: "m")])
    end

    def board
      [ok("a"), ok("b"), noted("mod", :module_no_rows), noted("shelf", :shelf_empty),
       noted("fresh", :never_synced), warned("old"), spiky("loud")]
    end

    def test_default_view_shows_findings_only
      visible = Nabu::Health::BoardView.visible(board)
      assert_equal %w[fresh old loud], visible.map(&:slug),
                   "ok rows and by-design notes drop; real findings (never-synced included) stay"
    end

    def test_all_restores_every_row
      assert_equal board, Nabu::Health::BoardView.visible(board, all: true)
    end

    def test_a_module_with_a_real_finding_still_prints
      mixed = Check.new(slug: "mod", findings: [
                          Finding.new(kind: :module_no_rows, severity: :info, message: "m"),
                          Finding.new(kind: :failed_run, severity: :loud, message: "boom")
                        ])
      assert_includes Nabu::Health::BoardView.visible([mixed]).map(&:slug), "mod"
    end

    def test_rollup_counts_and_names_the_way_back
      line = Nabu::Health::BoardView.rollup(board)
      assert_includes line, "2 ok"
      assert_includes line, "1 warning"
      assert_includes line, "1 anomaly"
      assert_includes line, "2 by-design notes suppressed"
      assert_includes line, "--all", "the rollup must name the way back to the full board"
    end

    def test_verdict_is_one_line_with_elapsed
      report = Nabu::Health::LocalCheck::Report.new(sources: board, golden: [], corpus: :present)
      line = Nabu::Health::BoardView.verdict(report, seconds: 12.34)
      assert_includes line, "1 anomaly finding(s)"
      assert_includes line, "1 warning"
      assert_includes line, "12.3s", "elapsed rides every summary (owner rule 2026-09-11)"
      refute_includes line, "\n"
    end

    def test_verdict_ok_shapes
      clean = Nabu::Health::LocalCheck::Report.new(sources: [ok("a")], golden: [], corpus: :present)
      assert_equal "health: OK (0.5s)", Nabu::Health::BoardView.verdict(clean, seconds: 0.5)
      soft = Nabu::Health::LocalCheck::Report.new(sources: [warned("old")], golden: [], corpus: :present)
      assert_equal "health: OK, 1 warning(s) (0.5s)", Nabu::Health::BoardView.verdict(soft, seconds: 0.5)
    end
  end
end
