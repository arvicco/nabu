# frozen_string_literal: true

require "test_helper"

# Store::StageTimings (P78-r1, Q34): the durable per-stage wall-time
# record under the history ledger — what the ETA line reads. Append-only
# history keyed (kind, scope, stage); the LATEST row governs; +rows+
# carries the run's work size so the estimate can scale by drift.
class StageTimingsTest < Minitest::Test
  def setup
    @ledger = Nabu::Store::Ledger.migrate!(Sequel.sqlite)
  end

  def teardown = @ledger.disconnect

  def test_record_and_last_roundtrip
    at = Time.utc(2026, 8, 18, 12, 0, 0)
    Nabu::Store::StageTimings.record!(@ledger, kind: "rebuild", scope: "kanripo",
                                               stage: "load", seconds: 348.2, rows: 5_122, at: at)
    row = Nabu::Store::StageTimings.last(@ledger, kind: "rebuild", scope: "kanripo", stage: "load")
    assert_in_delta 348.2, row[:seconds]
    assert_equal 5_122, row[:rows]
    # SQLite stores the naive timestamp; Sequel reads it back in local time —
    # compare the wall-clock value, the ledger convention.
    assert_equal at.strftime("%F %T"), row[:finished_at].strftime("%F %T")
  end

  def test_history_appends_and_the_latest_row_governs
    2.times do |i|
      Nabu::Store::StageTimings.record!(@ledger, kind: "rebuild", scope: "corpus",
                                                 stage: "timeline", seconds: 10.0 + i,
                                                 at: Time.utc(2026, 8, 17 + i))
    end
    assert_equal 2, @ledger[:stage_timings].count, "append-only history, never an upsert"
    row = Nabu::Store::StageTimings.last(@ledger, kind: "rebuild", scope: "corpus", stage: "timeline")
    assert_in_delta 11.0, row[:seconds], 0.001, "the LATEST row governs the estimate"
  end

  def test_the_key_is_the_full_triple
    Nabu::Store::StageTimings.record!(@ledger, kind: "rebuild", scope: "kanripo",
                                               stage: "load", seconds: 5.0)
    assert_nil Nabu::Store::StageTimings.last(@ledger, kind: "sync", scope: "kanripo", stage: "load")
    assert_nil Nabu::Store::StageTimings.last(@ledger, kind: "rebuild", scope: "cbeta", stage: "load")
    assert_nil Nabu::Store::StageTimings.last(@ledger, kind: "rebuild", scope: "kanripo", stage: "parse")
  end

  def test_rows_is_optional_history_without_a_denominator_is_still_history
    Nabu::Store::StageTimings.record!(@ledger, kind: "rebuild", scope: "corpus",
                                               stage: "analyze", seconds: 2.5)
    row = Nabu::Store::StageTimings.last(@ledger, kind: "rebuild", scope: "corpus", stage: "analyze")
    assert_nil row[:rows]
  end

  # The module convention (QuarantineBaseline): a pre-009 ledger reads as
  # "no history" and record! declines rather than crashing — read paths
  # never migrate.
  def test_a_pre_009_ledger_degrades_honestly
    bare = Sequel.sqlite
    assert_nil Nabu::Store::StageTimings.last(bare, kind: "rebuild", scope: "corpus", stage: "timeline")
    Nabu::Store::StageTimings.record!(bare, kind: "rebuild", scope: "corpus",
                                            stage: "timeline", seconds: 1.0) # must not raise
    refute bare.table_exists?(:stage_timings)
  ensure
    bare&.disconnect
  end

  def test_a_nil_ledger_reads_as_no_history
    assert_nil Nabu::Store::StageTimings.last(nil, kind: "rebuild", scope: "corpus", stage: "timeline")
  end
end
