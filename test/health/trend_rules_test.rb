# frozen_string_literal: true

require "test_helper"

# TrendRules (P5-5): pure functions over run-history / document-count numbers.
# No db here — just the threshold logic and the soft/loud classification.
class TrendRulesTest < Minitest::Test
  T = Nabu::Health::TrendRules

  # -- quarantine spike ----------------------------------------------------

  def test_spike_fires_when_above_prior_max_and_over_the_floor
    finding = T.quarantine_spike(latest_errored: 50, prior_errored: [1, 2, 3])
    refute_nil finding
    assert_equal :quarantine_spike, finding.kind
    assert finding.loud?, "a quarantine spike is a loud/red finding"
  end

  # 0→1 must not scream: 1 beats the prior max (0) but is under the floor.
  def test_spike_suppressed_below_the_absolute_floor
    assert_nil T.quarantine_spike(latest_errored: 1, prior_errored: [0, 0])
  end

  # Above the floor but not above the source's own norm ⇒ not a spike.
  def test_spike_suppressed_when_not_above_prior_max
    assert_nil T.quarantine_spike(latest_errored: 12, prior_errored: [12, 15])
  end

  # No prior successful run ⇒ no norm to exceed ⇒ never a spike.
  def test_spike_needs_history
    assert_nil T.quarantine_spike(latest_errored: 999, prior_errored: [])
  end

  # -- added collapse ------------------------------------------------------

  def test_collapse_fires_after_prior_activity
    runs = [{ added: 0, updated: 0 }, { added: 0, updated: 0 }, { added: 0, updated: 0 },
            { added: 5, updated: 1 }]
    finding = T.added_collapse(successful_runs: runs)
    refute_nil finding
    assert_equal :added_collapse, finding.kind
    assert finding.soft?, "added collapse is a soft warning (a quiet corpus looks the same)"
  end

  # A brand-new source with only empty runs was never active ⇒ no collapse.
  def test_collapse_needs_prior_activity
    runs = [{ added: 0, updated: 0 }, { added: 0, updated: 0 }, { added: 0, updated: 0 }]
    assert_nil T.added_collapse(successful_runs: runs)
  end

  # A recent run with any activity breaks the collapse streak.
  def test_collapse_not_flagged_when_latest_still_active
    runs = [{ added: 0, updated: 2 }, { added: 0, updated: 0 }, { added: 0, updated: 0 },
            { added: 9, updated: 0 }]
    assert_nil T.added_collapse(successful_runs: runs)
  end

  # -- withdrawal creep ----------------------------------------------------

  def test_creep_loud_above_fifteen_percent
    finding = T.withdrawal_creep(shed: 20, total: 100)
    assert finding.loud?
    assert_equal :withdrawal_creep, finding.kind
  end

  def test_creep_soft_between_five_and_fifteen_percent
    finding = T.withdrawal_creep(shed: 10, total: 100)
    assert finding.soft?
  end

  def test_creep_silent_at_or_below_five_percent
    assert_nil T.withdrawal_creep(shed: 5, total: 100)
    assert_nil T.withdrawal_creep(shed: 0, total: 100)
    assert_nil T.withdrawal_creep(shed: 0, total: 0)
  end

  # The single-sync sweep reuses the creep thresholds (loud > 15%).
  def test_sync_withdrawal_reuses_creep_thresholds
    assert T.sync_withdrawal(withdrawn: 16, total: 100).loud?
    assert T.sync_withdrawal(withdrawn: 8, total: 100).soft?
    assert_nil T.sync_withdrawal(withdrawn: 3, total: 100)
  end

  # -- stale ---------------------------------------------------------------

  def test_stale_fires_past_the_cadence
    now = Time.utc(2026, 7, 4)
    finding = T.stale_source(last_sync_at: now - (20 * 86_400), now: now)
    refute_nil finding
    assert finding.soft?
    assert_equal :stale, finding.kind
  end

  def test_fresh_source_is_not_stale
    now = Time.utc(2026, 7, 4)
    assert_nil T.stale_source(last_sync_at: now - (2 * 86_400), now: now)
  end

  # never-synced is a distinct signal, handled by the caller — not "stale".
  def test_nil_last_sync_is_not_stale
    assert_nil T.stale_source(last_sync_at: nil, now: Time.now)
  end

  def test_stale_tolerates_a_string_timestamp
    now = Time.utc(2026, 7, 4)
    finding = T.stale_source(last_sync_at: (now - (30 * 86_400)).to_s, now: now)
    assert finding.soft?
  end
end
