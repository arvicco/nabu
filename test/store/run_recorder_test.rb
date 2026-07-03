# frozen_string_literal: true

require "test_helper"

module Store
  class RunRecorderTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "test_adapter", name: "Conformance Test Adapter",
        adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def test_success_records_succeeded_run_with_report_counts
      report = Nabu::Store::LoadReport.new(added: 3, updated: 2, skipped: 5, withdrawn: 1, errored: 4)

      run = Nabu::Store::RunRecorder.record(db: @db, source: @source) do |yielded|
        assert_instance_of Nabu::Store::Run, yielded
        assert_equal "running", yielded.status
        report
      end

      run.refresh
      assert_equal @source.id, run.source_id
      assert_equal "succeeded", run.status
      refute_nil run.started_at
      refute_nil run.finished_at
      assert_equal 3, run.added
      assert_equal 2, run.updated
      assert_equal 1, run.withdrawn_count # LoadReport#withdrawn -> withdrawn_count
      assert_equal 4, run.errored
      assert_nil run.notes
      assert_equal 1, Nabu::Store::Run.count
    end

    def test_success_without_a_report_leaves_zero_counts
      run = Nabu::Store::RunRecorder.record(db: @db, source: @source) { nil }

      run.refresh
      assert_equal "succeeded", run.status
      assert_equal 0, run.added
      assert_equal 0, run.withdrawn_count
    end

    def test_failure_records_failed_run_and_reraises
      error = assert_raises(Nabu::FetchError) do
        Nabu::Store::RunRecorder.record(db: @db, source: @source) do
          raise Nabu::FetchError, "upstream unreachable"
        end
      end
      assert_equal "upstream unreachable", error.message

      # The failure record is durable (not rolled back).
      assert_equal 1, Nabu::Store::Run.count
      run = Nabu::Store::Run.first
      assert_equal "failed", run.status
      assert_equal "upstream unreachable", run.notes
      refute_nil run.finished_at
    end

    def test_sync_aborted_records_aborted_status_and_reraises
      error = assert_raises(Nabu::SyncAborted) do
        Nabu::Store::RunRecorder.record(db: @db, source: @source) do
          raise Nabu::SyncAborted.new(existing_count: 5, would_withdraw_count: 3, threshold: 0.2)
        end
      end
      assert_match(/circuit breaker/i, error.message)

      assert_equal 1, Nabu::Store::Run.count
      run = Nabu::Store::Run.first
      assert_equal "aborted", run.status # not "failed"
      assert_match(/withdraw 3 of 5/, run.notes)
      refute_nil run.finished_at
    end

    def test_clock_seam_pins_timestamps
      instant = Time.utc(2026, 7, 3, 12, 0, 0)
      run = Nabu::Store::RunRecorder.record(db: @db, source: @source, clock: -> { instant }) { nil }

      run.refresh
      # The seam drives both timestamps, so a fixed clock makes them identical.
      assert_equal run.started_at, run.finished_at
    end
  end
end
