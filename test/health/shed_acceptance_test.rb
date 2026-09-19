# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Health::ShedAcceptance (P102-1 — Q74): the quarantine-acceptance
# mold for withdrawal creep. Config-file only (the P70 posture: the
# instance config IS the durable record; shed itself is measured live
# from the catalog, so no baseline machinery is needed): the owner
# accepts a reviewed shed level, the anomaly quiets to an info note,
# growth PAST the accepted level re-arms the full finding, and a
# recovery BELOW it sends the acceptance dormant (the plain rule
# resumes — a real improvement is never masked).
class ShedAcceptanceTest < Minitest::Test
  def with_path(&)
    Dir.mktmpdir { |dir| yield File.join(dir, "shed_acceptances.yml") }
  end

  def plain_finding
    Nabu::Health::Finding.new(kind: :withdrawal_creep, severity: :loud, message: "withdrawal creep: x")
  end

  def test_accept_writes_the_config_file_and_latest_reads_it_back
    with_path do |path|
      accepted = Nabu::Health::ShedAcceptance.accept!(path: path, slug: "perseus-latin",
                                                      shed: 104, note: "upstream cleanup",
                                                      now: Time.utc(2026, 9, 18))
      assert_equal 104, accepted
      row = Nabu::Health::ShedAcceptance.latest(path, "perseus-latin")
      assert_equal 104, row[:shed]
      assert_equal "upstream cleanup", row[:note]
      assert_match(/2026-09-18/, row[:at].to_s)
      assert_nil Nabu::Health::ShedAcceptance.latest(path, "other")
    end
  end

  def test_acceptance_is_append_only_and_the_latest_row_governs
    with_path do |path|
      Nabu::Health::ShedAcceptance.accept!(path: path, slug: "s", shed: 10, note: nil)
      Nabu::Health::ShedAcceptance.accept!(path: path, slug: "s", shed: 25, note: "again")
      assert_equal 25, Nabu::Health::ShedAcceptance.latest(path, "s")[:shed]
    end
  end

  def test_finding_quiets_at_the_accepted_level_to_an_info_note
    with_path do |path|
      Nabu::Health::ShedAcceptance.accept!(path: path, slug: "s", shed: 104, note: nil,
                                           now: Time.utc(2026, 9, 18))
      acceptance = Nabu::Health::ShedAcceptance.latest(path, "s")
      note = Nabu::Health::ShedAcceptance.finding(plain: plain_finding, acceptance: acceptance,
                                                  shed: 104)
      assert_equal :info, note.severity
      assert_match(/shed accepted at 104 \(owner, 2026-09-18\)/, note.message)
      assert_match(/re-arms past/, note.message)
    end
  end

  def test_finding_re_arms_on_growth_past_the_accepted_level
    with_path do |path|
      Nabu::Health::ShedAcceptance.accept!(path: path, slug: "s", shed: 104, note: nil)
      acceptance = Nabu::Health::ShedAcceptance.latest(path, "s")
      plain = plain_finding
      finding = Nabu::Health::ShedAcceptance.finding(plain: plain, acceptance: acceptance,
                                                     shed: 110)
      assert_same plain, finding, "growth past the accepted level re-arms the full finding"
    end
  end

  def test_finding_goes_dormant_when_shed_recovers_below_the_accepted_level
    with_path do |path|
      Nabu::Health::ShedAcceptance.accept!(path: path, slug: "s", shed: 104, note: nil)
      acceptance = Nabu::Health::ShedAcceptance.latest(path, "s")
      plain = plain_finding
      finding = Nabu::Health::ShedAcceptance.finding(plain: plain, acceptance: acceptance,
                                                     shed: 50)
      assert_same plain, finding,
                  "a recovery below the accepted level sends the acceptance dormant — " \
                  "the plain rule resumes, never masked"
    end
  end

  def test_finding_passes_through_without_an_acceptance_and_idles_without_a_plain
    plain = plain_finding
    assert_same plain, Nabu::Health::ShedAcceptance.finding(plain: plain, acceptance: nil, shed: 104)
    with_path do |path|
      Nabu::Health::ShedAcceptance.accept!(path: path, slug: "s", shed: 104, note: nil)
      acceptance = Nabu::Health::ShedAcceptance.latest(path, "s")
      assert_nil Nabu::Health::ShedAcceptance.finding(plain: nil, acceptance: acceptance, shed: 90),
                 "no plain finding to quiet — the acceptance is idle"
    end
  end
end
