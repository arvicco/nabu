# frozen_string_literal: true

require "test_helper"
require "date"
require "tmpdir"
require "fileutils"

module Ops
  # Nabu::Ops::WatchListCheck (`rake boards:check`). Anchor: watched GitHub
  # threads whose replies never reach any other inbound channel — a row
  # nobody re-checked for a week means a reply can sit unseen. The check
  # is date arithmetic over the boards' "## GH watch list" section; the
  # registers below are fixtures (the real boards are gitignored).
  class WatchListCheckTest < Minitest::Test
    TODAY = Date.new(2026, 11, 5)

    def check(files)
      Dir.mktmpdir do |dir|
        files.each do |rel, body|
          path = File.join(dir, rel)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, body)
        end
        return Nabu::Ops::WatchListCheck.new(boards_dir: dir, today: TODAY).run
      end
    end

    def register(*rows, tail: "")
      "# Register\n\nNext number: x.\n\n## GH watch list (poll at every gate)\n\n" \
        "Format: `- <id> · <owner/repo>#<num> · checked <date> · <state>`\n\n" \
        "#{rows.map { |row| "#{row}\n" }.join}\n#{tail}"
    end

    def row(id, checked, state = "OPEN", repo: "example/repo#7")
      "- #{id} · #{repo} · checked #{checked} · #{state}"
    end

    def test_fresh_rows_pass
      report = check("register.md" => register(row("w-1", "2026-11-05"), row("w-2", "2026-10-29")))
      refute_predicate report, :skipped
      assert_predicate report, :clean?
      assert_equal 2, report.rows
    end

    def test_a_stale_open_row_trips_and_names_the_row
      report = check("register.md" => register(row("w-1", "2026-11-04"), row("w-2", "2026-10-28")))
      refute_predicate report, :clean?
      assert_equal 1, report.findings.size
      finding = report.findings.first
      assert_match(/w-2/, finding)
      assert_match(%r{example/repo#7}, finding)
      assert_match(/checked 2026-10-28/, finding)
      assert_match(/8 days/, finding)
    end

    def test_exactly_seven_days_is_still_fresh
      assert_predicate check("register.md" => register(row("w-1", "2026-10-29"))), :clean?
    end

    def test_free_text_state_counts_as_open
      # Live rows carry prose states ("silent since posting ...") — anything
      # not explicitly CLOSED/DORMANT is a thread still being watched.
      report = check("register.md" => register(row("w-1", "2026-10-01", "silent since posting 2026-09-30")))
      refute_predicate report, :clean?
    end

    def test_closed_and_dormant_stale_rows_do_not_trip
      report = check("register.md" => register(row("w-1", "2026-09-01", "CLOSED (merged 2026-09-02)"),
                                               row("w-2", "2026-09-01", "DORMANT"),
                                               row("w-3", "2026-09-01", "dormant since 2026-09-01")))
      assert_predicate report, :clean?
      assert_equal 3, report.rows
    end

    def test_a_state_merely_mentioning_dormancy_is_still_open
      report = check("register.md" => register(row("w-1", "2026-10-01", "nudged; dormant judgment ~2026-11-18")))
      refute_predicate report, :clean?
    end

    def test_an_explicit_open_row_with_trailing_text_trips_when_stale
      report = check("register.md" => register(row("w-1", "2026-10-01", "OPEN — awaiting review",
                                                   repo: "example/repo#9 (PR)")))
      assert_match(/w-1/, report.findings.first)
    end

    def test_a_row_without_a_parseable_checked_date_trips
      report = check("register.md" => register("- w-1 · example/repo#7 · checked 2026-13-40 · OPEN",
                                               "- w-2 · example/repo#8 · awaiting review"))
      assert_equal 2, report.findings.size
      assert(report.findings.all? { |finding| finding.match?(/no readable checked date/) })
    end

    def test_rows_after_the_section_are_not_watch_rows
      tail = "## Threads\n\n- w-9 · example/repo#1 · checked 2026-01-01 · OPEN\n"
      report = check("register.md" => register(row("w-1", "2026-11-05"), tail: tail))
      assert_predicate report, :clean?
      assert_equal 1, report.rows
    end

    def test_prose_and_blockquotes_inside_the_section_are_ignored
      tail = "> Standing note: checked 2026-01-01 example/repo#3\n\nSome prose line.\n"
      assert_predicate check("register.md" => register(row("w-1", "2026-11-05"), tail: tail)), :clean?
    end

    def test_a_missing_boards_dir_skips
      report = Nabu::Ops::WatchListCheck.new(boards_dir: "/nonexistent/boards-#{Process.pid}", today: TODAY).run
      assert_predicate report, :skipped
      assert_predicate report, :clean?
    end

    def test_boards_without_the_section_skip
      report = check("register.md" => "# Register\n\n## Threads\n\n- w-1 · example/repo#1 · checked 2026-01-01\n")
      assert_predicate report, :skipped
      assert_predicate report, :clean?
    end

    def test_the_section_is_found_in_any_top_level_board_file
      report = check("a.md" => "# A\n", "b.md" => register(row("w-1", "2026-10-01")))
      refute_predicate report, :clean?
      assert_match(/b\.md/, report.findings.first)
    end
  end
end
