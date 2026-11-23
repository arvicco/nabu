# frozen_string_literal: true

require "test_helper"
require "nabu/ops/decision_register_check"
require "tmpdir"

module Ops
  class DecisionRegisterCheckTest < Minitest::Test
    SIGIL = Nabu::Ops::DecisionRegisterCheck::SIGIL

    def check(content)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "decision-register.md")
        File.write(path, content)
        return Nabu::Ops::DecisionRegisterCheck.new(register_path: path).run
      end
    end

    def test_missing_register_is_an_announced_skip
      report = Nabu::Ops::DecisionRegisterCheck.new(register_path: "/nonexistent/decision-register.md").run
      assert report.skipped
      assert report.clean?
    end

    def test_open_waits_pass
      report = check(<<~MD)
        # The decision register

        ## #{SIGIL}R-169 · CATSS — sign, write, or park?  [minted 2026-11-17; DELAYED 2 weeks by the owner 2026-11-18 — resurface ~2026-12-02]
        Body.

        ## #{SIGIL}R-127 · The Perseus kind posture  [minted 2026-10-22; DEFERRED by the owner 2026-10-28]
        Body.

        ## #{SIGIL}R-133 · The NDA question  [minted 2026-10-30; option (b) TAKEN 2026-10-30 — re-opens when they answer]
        Body.
      MD
      refute report.skipped
      assert_equal 3, report.rows
      assert report.clean?, report.findings.join("; ")
    end

    def test_a_resolution_banner_fails_the_row
      report = check(<<~MD)
        ## #{SIGIL}R-177 · Wellcome  [minted 2026-11-23; RULED 2026-11-23 — trickle runner]
        Body.

        ## #{SIGIL}R-175 · A release cadence  [minted 2026-11-23; ROW CLOSED 2026-11-23: READY handed]
        Body.

        ## #{SIGIL}R-180 · Still waiting  [minted 2026-11-23]
        Body.
      MD
      assert_equal 3, report.rows
      assert_equal 2, report.findings.size
      assert(report.findings.all? { |f| f.include?("resolution banner") })
      assert(report.findings.any? { |f| f.include?("R-177") })
      assert(report.findings.any? { |f| f.include?("R-175") })
    end

    def test_an_empty_register_is_clean
      report = check("# The decision register\n\nNext number: #{SIGIL}R-5.\n")
      refute report.skipped
      assert_equal 0, report.rows
      assert report.clean?
    end
  end
end
