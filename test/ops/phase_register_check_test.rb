# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Ops
  # Nabu::Ops::PhaseRegisterCheck (`rake boards:check`). Anchor: the local
  # phase register (one row appended per phase at its gate) silently missed
  # its appends for five consecutive merged phases — nothing compared it to
  # what had actually merged. The probe compares the register's newest
  # `## P<N>` row against the highest phase merge on the main branch. Git
  # history is an injected seam here: no real repository in these tests.
  class PhaseRegisterCheckTest < Minitest::Test
    SUBJECTS = [
      "Merge pull request #207 from arvicco/phase-160",
      "Merge pull request #206 from arvicco/about-maintainer",
      "Merge pull request #205 from arvicco/phase-159",
      "Merge branch 'phase-999' into scratch"
    ].freeze

    def register(*numbers)
      rows = numbers.map { |number| "## P#{number} · a phase\n\nrow body\n\n" }.join
      "# Phase register\n\nIntro prose naming P999 in passing.\n\n#{rows}"
    end

    def check(body, subjects: SUBJECTS)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "phase-register.md")
        File.write(path, body) if body
        return Nabu::Ops::PhaseRegisterCheck.new(register_path: path, merge_subjects: -> { subjects }).run
      end
    end

    def test_a_register_carrying_the_highest_merged_phase_is_clean
      report = check(register(160, 159, 158))
      refute report.skipped
      assert_predicate report, :clean?
      assert_equal 160, report.newest_row
      assert_equal 160, report.highest_merged
    end

    def test_a_register_behind_the_merged_phases_fails_naming_both_numbers
      report = check(register(155, 154))
      refute_predicate report, :clean?
      assert_equal 1, report.findings.size
      assert_match(/P155/, report.findings.first)
      assert_match(/P160/, report.findings.first)
    end

    def test_the_newest_row_is_the_highest_heading_wherever_it_sits
      assert_predicate check(register(158, 160, 159)), :clean?
    end

    def test_a_register_ahead_of_the_merges_is_clean
      # The row is appended at the gate, before the owner's merge lands.
      assert_predicate check(register(161, 160)), :clean?
    end

    def test_only_pull_request_merges_of_phase_branches_count
      report = check(register(159), subjects: ["Merge pull request #206 from arvicco/about-maintainer",
                                               "Merge pull request #205 from arvicco/phase-159",
                                               "Merge branch 'phase-999' into scratch"])
      assert_predicate report, :clean?
      assert_equal 159, report.highest_merged
    end

    def test_a_register_with_no_phase_rows_fails
      report = check("# Phase register\n\nnothing yet\n")
      refute_predicate report, :clean?
      assert_match(/no .*P<N>/, report.findings.first)
    end

    def test_no_phase_merges_in_history_is_clean
      assert_predicate check(register(1), subjects: []), :clean?
    end

    def test_unreadable_history_fails_loudly
      Dir.mktmpdir do |dir|
        path = File.join(dir, "phase-register.md")
        File.write(path, register(160))
        failing = -> { raise Nabu::Shell::Error.new("git failed", status: 128, stderr: "bad ref") }
        report = Nabu::Ops::PhaseRegisterCheck.new(register_path: path, merge_subjects: failing).run
        refute_predicate report, :clean?
        assert_match(/git history unreadable/, report.findings.first)
      end
    end

    def test_an_absent_register_is_an_announced_skip
      path = File.join(Dir.tmpdir, "no-such-register-#{Process.pid}.md")
      untouched = -> { flunk "history must not be read when the register is absent" }
      report = Nabu::Ops::PhaseRegisterCheck.new(register_path: path, merge_subjects: untouched).run
      assert report.skipped
      assert_predicate report, :clean?
    end
  end
end
