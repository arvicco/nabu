# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Ops
  # Nabu::Ops::IncidentRegisterCheck (`rake boards:check`). The incident
  # register is a LOG of `## <sigil>I-n · <title>  [<date> · <STATUS …>]`
  # rows (the sigil from its codepoint: tracked files never carry it);
  # a row whose bracketed suffix carries no recognizable status token
  # cannot be censused (open vs closed is unreadable), so it fails the
  # check, named. Fixture register text only — never the real .docs/.
  class IncidentRegisterCheckTest < Minitest::Test
    S = Nabu::Ops::IncidentRegisterCheck::SIGIL

    CLEAN = <<~MD.gsub("#I", "#{S}I")
      # Incident register

      Intro prose naming #I-99 in passing, and a ## heading that is not a row.

      ## #I-4 · A live crash  [2026-11-20 · OPEN — fix queued]

      body

      ## #I-3 · A staged fix  [2026-11-19 · FIX-STAGED same hour; CLOSED at the gate merge]

      ## #I-2 · A mitigation  [2026-11-18 · MITIGATED for the wave]

      ## #I-1 · An old one  [CLOSED — fix shipped at the P122 gate]
    MD

    def check(body)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "incident-register.md")
        File.write(path, body) if body
        return Nabu::Ops::IncidentRegisterCheck.new(register_path: path).run
      end
    end

    def test_every_row_carrying_a_status_token_is_clean
      report = check(CLEAN)
      refute report.skipped
      assert_predicate report, :clean?
      assert_equal 4, report.rows
    end

    def test_a_row_with_a_dated_suffix_but_no_status_fails_naming_its_number
      report = check("#{CLEAN}\n## #{S}I-5 · Dated only  [2026-11-09]\n\n## #{S}I-6 · Fine  [2026-11-10 · CLOSED]\n")
      refute_predicate report, :clean?
      assert_equal 1, report.findings.size
      assert_match(/#{S}I-5\b/, report.findings.first)
      assert_match(/OPEN.*CLOSED.*FIX-STAGED.*MITIGATED/, report.findings.first)
    end

    def test_a_row_with_no_bracketed_suffix_fails
      report = check("## #{S}I-7 · No suffix at all\n")
      assert_equal 1, report.findings.size
      assert_match(/#{S}I-7\b.*no bracketed/, report.findings.first)
    end

    def test_a_status_word_in_the_title_does_not_count
      report = check("## #{S}I-8 · The CLOSED-loop crash  [2026-11-09]\n")
      assert_equal 1, report.findings.size
      assert_match(/#{S}I-8\b/, report.findings.first)
    end

    def test_tokens_must_be_whole_uppercase_words
      bodies = ["## #{S}I-9 · t  [2026-11-09 · REOPENED]\n",
                "## #{S}I-9 · t  [2026-11-09 · closed]\n",
                "## #{S}I-9 · t  [2026-11-09 · UNMITIGATED]\n"]
      bodies.each { |body| refute_predicate check(body), :clean?, body }
    end

    def test_every_unstatused_row_is_named
      report = check("## #{S}I-10 · a  [2026-11-01]\n## #{S}I-11 · b  [2026-11-02]\n## #{S}I-12 · c  [OPEN]\n")
      assert_equal 2, report.findings.size
      assert_match(/#{S}I-10\b/, report.findings[0])
      assert_match(/#{S}I-11\b/, report.findings[1])
    end

    def test_a_register_with_no_rows_fails
      report = check("# Incident register\n\nnothing yet\n")
      refute_predicate report, :clean?
      assert_match(/no `## #{S}I-n ·` row/, report.findings.first)
    end

    def test_an_absent_register_is_an_announced_skip
      report = check(nil)
      assert report.skipped
      assert_predicate report, :clean?
      assert_equal 0, report.rows
    end
  end
end
