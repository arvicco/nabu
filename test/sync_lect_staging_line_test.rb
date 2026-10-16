# frozen_string_literal: true

require "test_helper"

# The post-sync unstaged-share line, pinned at the RENDERING grain:
# test/lect_staging_test.rb covers the census, this file covers the line
# every sync report path prints. All of them — single `sync <slug>`, the
# multi-slug list, `sync --all` (sync_all_line), quickstart's core and
# starter sweeps — render through CLI#format_sync_outcome, so the
# fragment rides each one; an aborted sync loads nothing and carries no
# census (its ABORTED line is the honest report).
class SyncLectStagingLineTest < Minitest::Test
  def outcome(lect_staging:)
    report = Nabu::Store::LoadReport.new(added: 3, updated: 0, skipped: 0, withdrawn: 0,
                                         errored: 0, skipped_by_rule: 0)
    Nabu::SyncRunner::Outcome.new(slug: "edh", fetch_report: nil, load_report: report,
                                  breaker: nil, indexed: nil, warnings: [], discovery: nil,
                                  lect_staging: lect_staging)
  end

  def census(unstaged:, stageable:, codes:)
    Nabu::LectStaging::Census.new(unstaged: unstaged, stageable: stageable, codes: codes)
  end

  def cli
    Nabu::CLI.new
  end

  def test_sync_line_carries_the_unstaged_share
    line = cli.send(:format_sync_outcome, outcome(lect_staging: census(unstaged: 2091, stageable: 2091, codes: %w[pl])))
    assert_match(%r{  lect: 2,091/2,091 unstaged \(pl\)\z}, line)
  end

  def test_multiple_codes_are_listed
    line = cli.send(:format_sync_outcome,
                    outcome(lect_staging: census(unstaged: 12, stageable: 40, codes: %w[grc la])))
    assert_match(%r{lect: 12/40 unstaged \(grc, la\)}, line)
  end

  def test_sync_all_path_renders_the_same_fragment
    line = cli.send(:sync_all_line, "edh", outcome(lect_staging: census(unstaged: 5, stageable: 9, codes: %w[la])))
    assert_match(%r{lect: 5/9 unstaged \(la\)}, line)
  end

  def test_silent_when_fully_staged_or_nothing_stageable
    refute_match(/lect:/, cli.send(:format_sync_outcome,
                                   outcome(lect_staging: census(unstaged: 0, stageable: 9, codes: %w[la]))))
    refute_match(/lect:/, cli.send(:format_sync_outcome, outcome(lect_staging: nil)))
  end
end
