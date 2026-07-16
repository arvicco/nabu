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
end
