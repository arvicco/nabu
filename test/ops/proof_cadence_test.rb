# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nabu/ops/proof_cadence"

module Ops
  # Nabu::Ops::ProofCadence: the ops:drill / fixtures:check last-success
  # stamps under local/proofs/ and the boards:check staleness probe over
  # them. Tmp instance folders only — never the real local/.
  class ProofCadenceTest < Minitest::Test
    CADENCE = Nabu::Ops::ProofCadence
    TODAY = Date.new(2026, 11, 23)

    def setup
      @local = Dir.mktmpdir
    end

    def teardown
      FileUtils.remove_entry(@local)
    end

    def check(today: TODAY) = CADENCE::Check.new(local_dir: @local, today: today).run

    def stamp(proof, date) = CADENCE.record!(local_dir: @local, proof: proof, at: Time.utc(*date))

    def test_absent_proofs_home_is_an_announced_skip
      report = check
      assert report.skipped
      assert_predicate report, :clean?
    end

    def test_record_writes_a_utc_stamp_under_local_proofs
      path = CADENCE.record!(local_dir: @local, proof: "ops-drill", at: Time.new(2026, 11, 1, 12, 0, 0, "+03:00"),
                             detail: "derivation proven")
      assert_equal File.join(@local, "proofs", "ops-drill.yml"), path
      data = YAML.safe_load_file(path)
      assert_equal "2026-11-01T09:00:00Z", data["last_success"]
      assert_equal "derivation proven", data["detail"]
    end

    def test_unknown_proof_is_refused
      assert_raises(ArgumentError) { CADENCE.record!(local_dir: @local, proof: "ops-dril") }
    end

    def test_both_fresh_stamps_are_clean
      stamp("ops-drill", [2026, 10, 1])
      stamp("fixtures-check", [2026, 11, 20])
      report = check
      refute report.skipped
      assert_predicate report, :clean?
      assert_equal Date.new(2026, 10, 1), report.stamps["ops-drill"]
    end

    def test_exactly_sixty_days_is_fresh_sixty_one_is_stale
      stamp("ops-drill", [2026, 9, 24])
      stamp("fixtures-check", [2026, 9, 23])
      findings = check.findings
      assert_equal 1, findings.size
      assert_equal "fixtures-check: last successful run 2026-09-23 (61 days ago, over 60) — run `rake fixtures:check`",
                   findings.first
    end

    def test_missing_stamp_beside_a_present_one_is_named
      stamp("fixtures-check", [2026, 11, 20])
      findings = check.findings
      assert_equal ["ops-drill: no recorded successful run — run `rake ops:drill`"], findings
    end

    def test_unreadable_stamp_is_a_finding_never_a_pass
      stamp("fixtures-check", [2026, 11, 20])
      File.write(CADENCE.stamp_path(@local, "ops-drill"), "last_success: yesterday\n")
      assert_match(/ops-drill: stamp .* unreadable/, check.findings.first)
    end

    def test_restamp_refreshes_a_stale_proof
      stamp("ops-drill", [2026, 1, 1])
      stamp("fixtures-check", [2026, 11, 20])
      refute_predicate check, :clean?
      stamp("ops-drill", [2026, 11, 22])
      assert_predicate check, :clean?
    end
  end
end
