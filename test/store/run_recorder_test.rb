# frozen_string_literal: true

require "test_helper"

module Store
  class RunRecorderTest < Minitest::Test
    include StoreTestDB

    def setup
      @ledger = ledger_test_db
    end

    def test_success_records_succeeded_run_with_report_counts
      report = Nabu::Store::LoadReport.new(added: 3, updated: 2, skipped: 5, withdrawn: 1, errored: 4)

      run = Nabu::Store::RunRecorder.record(source_slug: "test_adapter") do |yielded|
        assert_instance_of Nabu::Store::Run, yielded
        assert_equal "running", yielded.status
        report
      end

      run.refresh
      assert_equal "test_adapter", run.source_slug
      assert_equal "sync", run.kind
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
      run = Nabu::Store::RunRecorder.record(source_slug: "test_adapter") { nil }

      run.refresh
      assert_equal "succeeded", run.status
      assert_equal 0, run.added
      assert_equal 0, run.withdrawn_count
    end

    def test_rebuild_kind_is_recorded
      run = Nabu::Store::RunRecorder.record(source_slug: "test_adapter", kind: "rebuild") { nil }
      assert_equal "rebuild", run.refresh.kind
    end

    def test_failure_records_failed_run_and_reraises
      error = assert_raises(Nabu::FetchError) do
        Nabu::Store::RunRecorder.record(source_slug: "test_adapter") do
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
        Nabu::Store::RunRecorder.record(source_slug: "test_adapter") do
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
      run = Nabu::Store::RunRecorder.record(source_slug: "test_adapter", clock: -> { instant }) { nil }

      run.refresh
      # The seam drives both timestamps, so a fixed clock makes them identical.
      assert_equal run.started_at, run.finished_at
    end

    # -- the two-stage contract: the row closes at OPERATION end -------------
    #
    # A sync or rebuild keeps working after its load (the index slice, the
    # catalog-lane refreshes, the corpus stages). A row that read "succeeded"
    # the moment the load returned lied for the whole post-load stretch —
    # and forever, when the process died in it. record_load stamps the load's
    # counts and loaded_at but keeps the row "running"; only close ends it.

    def test_record_load_stamps_counts_and_loaded_at_but_keeps_the_row_running
      report = Nabu::Store::LoadReport.new(added: 3, updated: 2, skipped: 0, withdrawn: 1, errored: 4)

      run = Nabu::Store::RunRecorder.record_load(source_slug: "test_adapter") { report }

      run.refresh
      assert_equal "running", run.status, "the load landed; the operation has not closed"
      refute_nil run.loaded_at
      assert_nil run.finished_at
      assert_equal [3, 2, 1, 4], [run.added, run.updated, run.withdrawn_count, run.errored]
    end

    def test_close_finalizes_the_open_row_as_succeeded
      run = Nabu::Store::RunRecorder.record_load(source_slug: "test_adapter") { nil }

      value = Nabu::Store::RunRecorder.close([run]) { :post_load_result }

      assert_equal :post_load_result, value
      run.refresh
      assert_equal "succeeded", run.status
      refute_nil run.finished_at
    end

    # The type specimen: the process dies DURING a post-load stage (a
    # background timeout's kill, ^C). Signals are not StandardError, so
    # nothing rescues them — and the row must still say the operation never
    # finished: running, loaded_at set (the load landed), finished_at nil.
    def test_a_kill_after_the_load_leaves_a_row_that_says_so
      run = Nabu::Store::RunRecorder.record_load(source_slug: "test_adapter") { nil }

      assert_raises(Interrupt) do
        Nabu::Store::RunRecorder.close([run]) { raise Interrupt }
      end

      run.refresh
      assert_equal "running", run.status, "a killed operation never reads succeeded"
      refute_nil run.loaded_at, "the load stage did land — the row says how far it got"
      assert_nil run.finished_at
    end

    def test_a_post_load_failure_closes_the_row_failed_and_reraises
      run = Nabu::Store::RunRecorder.record_load(source_slug: "test_adapter") { nil }

      error = assert_raises(Nabu::Error) do
        Nabu::Store::RunRecorder.close([run]) { raise Nabu::Error, "index slice died" }
      end
      assert_equal "index slice died", error.message

      run.refresh
      assert_equal "failed", run.status
      assert_match(/failed after the load: index slice died/, run.notes)
      refute_nil run.finished_at
    end

    # A rebuild closes MANY rows at once (every replayed source's), when the
    # corpus stages end — and fails them all together when one stage dies.
    def test_close_settles_every_row_it_was_handed
      runs = %w[alpha beta].map { |slug| Nabu::Store::RunRecorder.record_load(source_slug: slug, kind: "rebuild") { nil } }

      assert_raises(Nabu::Error) { Nabu::Store::RunRecorder.close(runs) { raise Nabu::Error, "index died" } }

      assert_equal(%w[failed failed], runs.map { |run| run.refresh.status })
    end

    # A row the load stage already closed (failed/aborted) is never
    # re-closed by a later close — its own terminal state stands.
    def test_close_leaves_an_already_closed_row_alone
      failed = Nabu::Store::Run.create(source_slug: "s", kind: "rebuild", started_at: Time.now,
                                       finished_at: Time.now, status: "failed", notes: "own error")

      Nabu::Store::RunRecorder.close([failed]) { nil }

      failed.refresh
      assert_equal "failed", failed.status
      assert_equal "own error", failed.notes
    end

    # `nabu runs close-stale`: a row still "running" past the stale
    # threshold is a killed run nobody noticed. close_stale settles exactly
    # those rows "abandoned" (finished_at stamped, the reason in notes) and
    # returns them; a live row inside the threshold and closed rows stand.
    def test_close_stale_abandons_only_open_rows_started_before_the_cutoff
      now = Time.local(2026, 10, 21, 12) # the ledger stores zone-less local time
      cutoff = now - 3_600
      stale = Nabu::Store::Run.create(source_slug: "dead", kind: "sync", started_at: cutoff - 60, status: "running")
      older = Nabu::Store::Run.create(source_slug: "older", kind: "rebuild", started_at: cutoff - 7_200,
                                      loaded_at: cutoff - 7_000, status: "running")
      live = Nabu::Store::Run.create(source_slug: "live", kind: "sync", started_at: cutoff + 60, status: "running")
      done = Nabu::Store::Run.create(source_slug: "done", kind: "sync", started_at: cutoff - 60,
                                     finished_at: cutoff, status: "failed", notes: "own error")

      closed = Nabu::Store::RunRecorder.close_stale(before: cutoff, clock: -> { now })

      assert_equal(%w[older dead], closed.map(&:source_slug), "oldest first")
      [stale, older].each do |run|
        run.refresh
        assert_equal "abandoned", run.status
        assert_equal now.to_i, run.finished_at.to_i
        assert_match(/abandoned/, run.notes)
      end
      assert_equal "running", live.refresh.status
      assert_equal "failed", done.refresh.status
      assert_equal "own error", done.notes
    end

    def test_stale_lists_without_writing
      cutoff = Time.local(2026, 10, 21)
      run = Nabu::Store::Run.create(source_slug: "dead", kind: "sync", started_at: cutoff - 60, status: "running")

      assert_equal ["dead"], Nabu::Store::RunRecorder.stale(before: cutoff).map(&:source_slug)
      assert_equal "running", run.refresh.status
      assert_empty Nabu::Store::RunRecorder.close_stale(before: cutoff - 3_600)
    end

    # P7-1: runs are keyed by SLUG, not source id — a rebuild re-mints every
    # catalog id, and the ledger's history must read continuously across that
    # boundary. Two runs recorded "before" and "after" an id re-mint are the
    # same source's history.
    def test_slug_keying_reads_continuously_across_id_reminting
      Nabu::Store::RunRecorder.record(source_slug: "corpus") { nil } # catalog source id 1, say
      Nabu::Store::RunRecorder.record(source_slug: "corpus") { nil } # rebuilt: id re-minted; slug unchanged

      runs = Nabu::Store::Run.where(source_slug: "corpus").order(:id).all
      assert_equal 2, runs.size
      assert(runs.all? { |run| run.status == "succeeded" })
    end
  end
end
