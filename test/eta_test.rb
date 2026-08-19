# frozen_string_literal: true

require "test_helper"

# Nabu::Eta (P78-r2, Q34): the estimate a stage announcement carries —
# read from the P78-r1 stage_timings history (latest row governs),
# scaled by row-count drift when the caller has a cheap current
# denominator, and honest ("first run — no estimate") when there is no
# history to speak from.
class EtaTest < Minitest::Test
  def setup
    @ledger = Nabu::Store::Ledger.migrate!(Sequel.sqlite)
  end

  def teardown = @ledger.disconnect

  def record!(kind: "rebuild", scope: "corpus", stage: "timeline", seconds: 348.0, rows: nil)
    Nabu::Store::StageTimings.record!(@ledger, kind: kind, scope: scope, stage: stage,
                                               seconds: seconds, rows: rows)
  end

  # -- formatting ----------------------------------------------------------

  def test_format_seconds_spans_the_three_magnitudes
    assert_equal "48s", Nabu::Eta.format_seconds(48.2)
    assert_equal "5m48s", Nabu::Eta.format_seconds(348.0)
    assert_equal "1h04m", Nabu::Eta.format_seconds(3840.0)
  end

  def test_render_names_the_last_run_and_its_rows
    record!(seconds: 348.0, rows: 5_122)
    estimate = Nabu::Eta.for(@ledger, kind: "rebuild", scope: "corpus", stage: "timeline")
    assert_equal "~5m48s (last run 5m48s over 5,122 rows)", estimate.render
    refute_predicate estimate, :none?
  end

  def test_render_without_rows_is_just_the_last_run
    record!(seconds: 12.0)
    estimate = Nabu::Eta.for(@ledger, kind: "rebuild", scope: "corpus", stage: "timeline")
    assert_equal "~12s (last run 12s)", estimate.render
  end

  # -- drift scaling (the era-bound-constants rule) ------------------------

  def test_a_current_denominator_scales_the_estimate
    record!(seconds: 300.0, rows: 1_000)
    estimate = Nabu::Eta.for(@ledger, kind: "rebuild", scope: "corpus", stage: "timeline",
                                      rows: 1_500)
    assert_in_delta 450.0, estimate.seconds
    assert_equal "~7m30s (last run 5m over 1,000 rows; scaled for 1,500)", estimate.render
  end

  def test_scaling_needs_a_recorded_denominator
    record!(seconds: 300.0, rows: nil)
    estimate = Nabu::Eta.for(@ledger, kind: "rebuild", scope: "corpus", stage: "timeline",
                                      rows: 1_500)
    assert_in_delta 300.0, estimate.seconds, 0.001, "no basis rows — the raw last run, never a guess"
  end

  # -- the honest absences -------------------------------------------------

  def test_no_history_is_an_honest_first_run
    estimate = Nabu::Eta.for(@ledger, kind: "rebuild", scope: "corpus", stage: "timeline")
    assert_predicate estimate, :none?
    assert_equal "first run — no estimate", estimate.render
  end

  def test_a_nil_ledger_reads_as_first_run
    assert_predicate Nabu::Eta.for(nil, kind: "rebuild", scope: "corpus", stage: "timeline"), :none?
  end

  def test_the_latest_row_governs
    record!(seconds: 100.0)
    record!(seconds: 200.0)
    estimate = Nabu::Eta.for(@ledger, kind: "rebuild", scope: "corpus", stage: "timeline")
    assert_in_delta 200.0, estimate.seconds
  end

  # -- the umbrella stage (rebuild's "fulltext index" spans six) -----------

  def test_for_stages_sums_the_recorded_sub_stages
    record!(stage: "fts_lemma", seconds: 600.0)
    record!(stage: "trigram", seconds: 120.0)
    estimate = Nabu::Eta.for_stages(@ledger, kind: "rebuild", scope: "corpus",
                                             stages: %w[fts_lemma trigram reflex])
    assert_in_delta 720.0, estimate.seconds, 0.001, "recorded sub-stages sum; absent ones add nothing"
    assert_equal "~12m (last run 12m)", estimate.render
  end

  def test_for_stages_with_no_history_is_first_run
    assert_predicate Nabu::Eta.for_stages(@ledger, kind: "rebuild", scope: "corpus",
                                                   stages: %w[fts_lemma trigram]),
                     :none?
  end

  # -- the sync banner (P78-r2: existing runs durations already answer) ----

  def test_last_sync_reads_the_runs_history
    @ledger[:runs].insert(source_slug: "kanripo", kind: "sync", status: "succeeded",
                          started_at: Time.utc(2026, 8, 17, 10, 0, 0),
                          finished_at: Time.utc(2026, 8, 17, 10, 4, 12), added: 3)
    estimate = Nabu::Eta.last_sync(@ledger, slug: "kanripo")
    assert_in_delta 252.0, estimate.seconds, 0.001
    assert_equal "~4m12s (last run 4m12s)", estimate.render
  end

  def test_last_sync_ignores_failed_and_unfinished_runs_and_other_kinds
    @ledger[:runs].insert(source_slug: "kanripo", kind: "sync", status: "failed",
                          started_at: Time.utc(2026, 8, 17), finished_at: Time.utc(2026, 8, 17))
    @ledger[:runs].insert(source_slug: "kanripo", kind: "sync", status: "succeeded",
                          started_at: Time.utc(2026, 8, 17), finished_at: nil)
    @ledger[:runs].insert(source_slug: "kanripo", kind: "rebuild", status: "succeeded",
                          started_at: Time.utc(2026, 8, 17),
                          finished_at: Time.utc(2026, 8, 17) + 60)
    assert_nil Nabu::Eta.last_sync(@ledger, slug: "kanripo"),
               "a failed, unfinished, or rebuild-kind run never predicts a sync"
  end

  def test_last_sync_on_a_fresh_ledger_is_nil
    assert_nil Nabu::Eta.last_sync(@ledger, slug: "never-synced")
  end
end
