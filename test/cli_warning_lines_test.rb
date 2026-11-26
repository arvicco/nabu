# frozen_string_literal: true

require "test_helper"

# The CLI text of the load-settlement warnings, pinned at the seam both
# print paths render through: [line, colour] pairs, so text AND colour are
# asserted without capturing a terminal. A tripped parse breaker is a
# refusal (rows KEPT pending the operator) — red on sync and rebuild alike;
# the advisory lines stay yellow.
class CLIWarningLinesTest < Minitest::Test
  def cli = Nabu::CLI.new

  def report(parse_withdrawn: 0, parse_held: 0, errored: 1)
    Nabu::Store::LoadReport.new(added: 0, updated: 0, skipped: 3, withdrawn: parse_withdrawn,
                                errored: errored, parse_withdrawn: parse_withdrawn, parse_held: parse_held)
  end

  def breaker_text(slug, count, noun: "document(s)")
    "PARSE BREAKER: #{count} held #{noun} now fail to parse — this looks like a parser regression; " \
      "their rows were KEPT (still served). If the change is intended, accept the withdrawals with: " \
      "bin/nabu sync #{slug} --parse-only --force"
  end

  def test_rebuild_warning_lines_are_pinned_with_their_colours
    quarantine = Nabu::Health::Finding.new(kind: :quarantine_delta, severity: :loud, message: "quarantine moved")
    outcomes = [
      Nabu::Rebuild::Outcome.new(slug: "beta", report: report(parse_held: 11, errored: 11), quarantine: quarantine),
      Nabu::Rebuild::Outcome.new(slug: "glossy", report: report(parse_withdrawn: 2),
                                 noun: Nabu::Store::LoadReport::ENTRY_NOUN)
    ]
    result = Struct.new(:warnings).new(outcomes)

    assert_equal [
      ["  WARNING: beta quarantine moved", :yellow],
      ["  WARNING: beta #{breaker_text('beta', 11)}", :red],
      ["  WARNING: glossy withdrew 2 held entr(ies) whose file no longer parses " \
       "(quarantined or skipped by rule; 1 file(s) errored this run)", :yellow]
    ], cli.send(:outcome_warning_lines, result)
  end

  def test_sync_parse_breaker_line_is_red_and_advisories_stay_yellow
    findings = [
      Nabu::Health::Finding.new(kind: :parse_withdrawal, severity: :loud, message: "withdrew 1 held document(s)"),
      Nabu::Health::Finding.new(kind: :parse_breaker, severity: :loud, message: breaker_text("failing", 13))
    ]
    outcome = Nabu::SyncRunner::Outcome.new(slug: "failing", fetch_report: nil, load_report: report, breaker: nil,
                                            indexed: nil, warnings: findings, discovery: nil)

    assert_equal [
      ["  ! withdrew 1 held document(s)", :yellow],
      ["  ! #{breaker_text('failing', 13)}", :red]
    ], cli.send(:sync_warning_lines, outcome)
  end
end
