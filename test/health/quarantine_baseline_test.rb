# frozen_string_literal: true

require "test_helper"

# QuarantineBaseline (P18-7): the ledger storage side of the delta-aware
# quarantine warning — record/advance semantics and the honest degradations
# (no ledger, pre-005 ledger). The rule logic itself is TrendRulesTest's.
class QuarantineBaselineTest < Minitest::Test
  include StoreTestDB

  Q = Nabu::Health::QuarantineBaseline

  def setup
    @ledger = ledger_test_db
  end

  def test_first_record_sets_baseline_and_anchor
    Q.record!(@ledger, "papyri", errored: 9_312)
    assert_equal({ baseline: 9_312, anchor: 9_312 }, Q.read(@ledger, "papyri"))
  end

  # The advance rule: baseline follows every ok run; the anchor is the
  # low-water mark and only ever moves DOWN — the creep backstop's memory.
  def test_baseline_advances_up_but_the_anchor_does_not
    Q.record!(@ledger, "papyri", errored: 9_312)
    Q.record!(@ledger, "papyri", errored: 9_400)
    assert_equal({ baseline: 9_400, anchor: 9_312 }, Q.read(@ledger, "papyri"))
    assert_equal 1, @ledger[:quarantine_baselines].count, "one row per source (state, not history)"
  end

  def test_an_improvement_advances_the_anchor_down
    Q.record!(@ledger, "papyri", errored: 9_312)
    Q.record!(@ledger, "papyri", errored: 9_000)
    assert_equal({ baseline: 9_000, anchor: 9_000 }, Q.read(@ledger, "papyri"))
  end

  def test_delta_finding_compares_against_the_stored_baseline
    Q.record!(@ledger, "papyri", errored: 9_312)
    assert_nil Q.delta_finding(@ledger, "papyri", errored: 9_312)
    assert_predicate Q.delta_finding(@ledger, "papyri", errored: 9_313), :loud?
  end

  def test_creep_finding_reads_baseline_vs_anchor
    Q.record!(@ledger, "src", errored: 1_000)
    Q.record!(@ledger, "src", errored: 1_100) # +10% drift, absorbed step-wise
    finding = Q.creep_finding(@ledger, "src")
    assert_equal :quarantine_creep, finding.kind
    assert_predicate finding, :soft?
    assert_nil Q.creep_finding(@ledger, "other"), "no row → no creep"
  end

  # -- the EDH 27→1 story (P23-3c) --------------------------------------------

  # The 26 lost-text records leave quarantine via the whole-inscription
  # fallback at the owner's `sync edh --parse-only`. The machinery handles the
  # drop BY DESIGN — no baseline surgery needed: the delta announces the -26
  # exactly once at that run, record! then advances the baseline AND the
  # anchor down to 1 (an improvement resets the low-water mark), so the creep
  # backstop stays silent and the steady state at 1 (hd059778, the honest
  # malformed-XML permanent quarantine) never alarms again.
  def test_edh_quarantines_leaving_via_the_fallback_announce_once_and_settle
    Q.record!(@ledger, "edh", errored: 27) # the anchored P18-gate audit level

    drop = Q.delta_finding(@ledger, "edh", errored: 1)
    assert_predicate drop, :loud?, "the -26 is announced at the run that lands the fallback"
    assert_match(/-26/, drop.message)

    Q.record!(@ledger, "edh", errored: 1)
    assert_equal({ baseline: 1, anchor: 1 }, Q.read(@ledger, "edh"))
    assert_nil Q.creep_finding(@ledger, "edh"), "the drop must not trip the creep anchor"
    assert_nil Q.delta_finding(@ledger, "edh", errored: 1), "steady state at 1 is silent"
  end

  # -- creep acceptance (P43-0, D42-c) ---------------------------------------

  # The durable record: accept! books the CURRENT baseline (ledger migration
  # 008); multiple acceptances accrue over time and the LATEST governs.
  def test_acceptance_round_trip_and_latest_wins
    Q.record!(@ledger, "papyri", errored: 1_000)
    Q.record!(@ledger, "papyri", errored: 1_200)

    assert_equal 1_200, Q.accept!(@ledger, "papyri", note: "reviewed: upstream schema shift")
    Q.record!(@ledger, "papyri", errored: 1_500)
    assert_equal 1_500, Q.accept!(@ledger, "papyri")

    assert_equal 2, @ledger[:creep_acceptances].where(source_slug: "papyri").count,
                 "acceptances are history, not state — every one is kept"
    latest = Q.latest_acceptance(@ledger, "papyri")
    assert_equal 1_500, latest[:accepted_baseline]
    assert_nil latest[:note]
    first = @ledger[:creep_acceptances].where(source_slug: "papyri").order(:id).first
    assert_equal "reviewed: upstream schema shift", first[:note]
  end

  def test_accepting_with_no_recorded_baseline_declines_and_records_nothing
    assert_nil Q.accept!(@ledger, "nobody")
    assert_equal 0, @ledger[:creep_acceptances].count
  end

  # Requirement (a): acceptance at N quiets the anomaly at baseline N — and
  # quiet is never silent: the line downgrades to an info-grade note.
  def test_acceptance_at_the_current_baseline_quiets_the_anomaly_to_a_note
    Q.record!(@ledger, "src", errored: 1_000)
    Q.record!(@ledger, "src", errored: 1_200) # +20% drift above the anchor: loud
    assert_predicate Q.creep_finding(@ledger, "src"), :loud?

    Q.accept!(@ledger, "src", now: Time.utc(2026, 7, 23))
    finding = Q.creep_finding(@ledger, "src")
    assert_equal :quarantine_creep_accepted, finding.kind
    assert_equal :info, finding.severity
    assert_match(/quarantine creep accepted at 1200 \(owner, 2026-07-23\)/, finding.message)
  end

  # Requirement (b): baseline growth PAST the accepted level re-alarms — the
  # acceptance is an anchor-floor, not a mute.
  def test_baseline_growth_past_the_accepted_level_realarms
    Q.record!(@ledger, "src", errored: 1_000)
    Q.record!(@ledger, "src", errored: 1_200)
    Q.accept!(@ledger, "src")

    Q.record!(@ledger, "src", errored: 1_500) # +25% past the accepted 1200
    finding = Q.creep_finding(@ledger, "src")
    assert_equal :quarantine_creep, finding.kind
    assert_predicate finding, :loud?
    assert_match(/1200/, finding.message, "the effective anchor is the accepted level")
  end

  # Requirement (c): a RECOVERY below the accepted value (parser fix) makes the
  # acceptance dormant — re-growth alarms from the recovered low-water mark,
  # never masked by the old, higher acceptance.
  def test_recovery_below_the_accepted_value_ignores_the_acceptance
    Q.record!(@ledger, "src", errored: 1_000)
    Q.record!(@ledger, "src", errored: 1_200)
    Q.accept!(@ledger, "src")

    Q.record!(@ledger, "src", errored: 100) # parser fix: baseline AND anchor drop
    assert_nil Q.creep_finding(@ledger, "src"), "steady state at the recovered low is quiet"

    Q.record!(@ledger, "src", errored: 300) # re-growth from the recovered low
    finding = Q.creep_finding(@ledger, "src")
    assert_equal :quarantine_creep, finding.kind
    assert_predicate finding, :loud?, "the dormant 1200 acceptance must not mask +200 over the anchor 100"
    assert_match(/100/, finding.message, "the plain low-water anchor rule resumes")
  end

  # Sub-alarm drift above an acceptance stays plain quiet (nil, no note): the
  # note appears only when the acceptance is ACTIVELY quieting a would-be alarm.
  def test_no_note_when_nothing_would_alarm
    Q.record!(@ledger, "src", errored: 1_000)
    Q.accept!(@ledger, "src")
    assert_nil Q.creep_finding(@ledger, "src")
  end

  # -- honest degradation ----------------------------------------------------

  def test_nil_ledger_reads_as_no_baseline_and_declines_writes
    assert_nil Q.read(nil, "x")
    assert_nil Q.creep_finding(nil, "x")
    Q.record!(nil, "x", errored: 5) # must not raise
    finding = Q.delta_finding(nil, "x", errored: 5)
    assert_equal :quarantine_baseline_recorded, finding.kind
  end

  # A pre-005 ledger (read paths never migrate): same degradation, no crash.
  def test_pre_005_ledger_without_the_table_degrades
    @ledger.drop_table(:quarantine_baselines)
    assert_nil Q.read(@ledger, "x")
    Q.record!(@ledger, "x", errored: 5) # must not raise
    assert_nil Q.creep_finding(@ledger, "x")
  end

  # A pre-008 ledger (baselines table present, acceptances table not yet):
  # reads as "no acceptances" — the plain anchor rule runs — and accept!
  # declines rather than crashing. Same convention as the pre-005 case.
  def test_pre_008_ledger_without_the_acceptances_table_degrades
    Q.record!(@ledger, "src", errored: 1_000)
    Q.record!(@ledger, "src", errored: 1_200)
    @ledger.drop_table(:creep_acceptances)

    assert_nil Q.latest_acceptance(@ledger, "src")
    assert_nil Q.accept!(@ledger, "src") # must not raise
    assert_predicate Q.creep_finding(@ledger, "src"), :loud?, "the plain low-water rule still runs"
  end

  def test_nil_ledger_acceptance_reads_degrade
    assert_nil Q.latest_acceptance(nil, "x")
    assert_nil Q.accept!(nil, "x")
  end
end
