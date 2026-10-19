# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Ops
  # Nabu::Ops::BoardCheck (`rake boards:check`). Anchor: a register header
  # that went stale — it still named a number already minted — so the next
  # mint would have reused it; found by eye at a gate. Board text below is
  # built from the sigil constant: tracked files never carry it literally.
  class BoardCheckTest < Minitest::Test
    S = Nabu::Ops::BoardCheck::SIGIL

    def check(files)
      Dir.mktmpdir do |dir|
        files.each do |rel, body|
          path = File.join(dir, rel)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, body)
        end
        return Nabu::Ops::BoardCheck.new(boards_dir: dir).run
      end
    end

    def log(next_number, *numbers)
      "# Log\n\nNext number: #{S}I-#{next_number}.\n\n" +
        numbers.map { |number| "## #{S}I-#{number} · entry\n\nbody\n\n" }.join
    end

    def test_a_current_log_register_is_clean
      report = check("incident-register.md" => log(3, 2, 1))
      assert_predicate report, :clean?
      assert_equal ["incident-register.md"], report.registers
    end

    def test_a_header_naming_an_already_minted_number_is_stale
      report = check("incident-register.md" => log(2, 2, 1))
      refute_predicate report, :clean?
      assert_match(/#{S}I-2 .*already minted/, report.findings.first.message)
    end

    def test_a_mint_cited_only_in_a_plan_doc_counts
      report = check("incident-register.md" => log(3, 2, 1),
                     "p9-plan.md" => "minted #{S}I-3 for the crash\n")
      assert_match(/p9-plan\.md/, report.findings.first.message)
    end

    def test_a_log_register_whose_header_skipped_ahead_is_stale
      report = check("incident-register.md" => log(5, 2, 1))
      assert_match(/must say Next number #{S}I-3/, report.findings.first.message)
    end

    def test_a_register_that_removes_ruled_rows_is_checked_one_way_only
      body = "Next number: #{S}R-110.\n\n## #{S}R-99 · open\n\n## #{S}R-14 · deferred\n"
      assert_predicate check("decision-register.md" => body), :clean?
      assert_predicate check("decision-register.md" => body, "p1-plan.md" => "#{S}R-109 ruled\n"), :clean?
      refute_predicate check("decision-register.md" => body, "p1-plan.md" => "#{S}R-110 minted\n"), :clean?
    end

    def test_archived_boards_are_history_not_mints
      report = check("incident-register.md" => log(3, 2, 1),
                     "old-phases/p1-plan.md" => "#{S}I-7 from another era\n")
      assert_predicate report, :clean?
    end

    def test_no_boards_dir_is_an_announced_skip
      report = Nabu::Ops::BoardCheck.new(boards_dir: File.join(Dir.tmpdir, "no-such-boards-#{Process.pid}")).run
      assert report.skipped
      assert_predicate report, :clean?
    end
  end
end
