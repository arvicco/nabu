# frozen_string_literal: true

module Nabu
  module Store
    # Wraps a sync/rebuild in a `runs` row (architecture §8) — written to the
    # history LEDGER (Store::Ledger, P7-1), keyed by source SLUG so run
    # history survives the catalog id re-minting a rebuild performs. The
    # caller must have the ledger open (Ledger.setup! bound).
    #
    # The row closes at OPERATION end, never earlier. Two shapes:
    #
    # * record — the operation IS the block (a fetch-only sync): inserts the
    #   row "running", yields it, and closes it "succeeded" on normal return.
    # * record_load + close — the operation keeps working after its load (a
    #   sync's index slice and lane refreshes; a rebuild's corpus stages).
    #   record_load runs the load stage and stamps its counts + loaded_at but
    #   leaves the row "running"; close runs the post-load stages and only
    #   then writes the terminal status + finished_at. A process that dies
    #   between the two leaves running + loaded_at + no finished_at — the
    #   row says the load landed and the operation never finished, instead
    #   of a "succeeded" over a missing index slice.
    #
    # On any StandardError during the load stage the row records "failed"
    # (the message as notes) and the error re-raises — except
    # Nabu::SyncAborted (the withdrawal circuit breaker), which records the
    # durable status "aborted" so a tripped breaker is distinguishable from a
    # genuine failure. A post-load failure closes every still-open row it was
    # handed "failed" with the boundary named in the notes. Signals
    # (Interrupt, SignalException) are not StandardError and are not
    # rescued: the row stays open, which is exactly the truth. The run row is
    # deliberately *not* wrapped in the caller's transaction — a failed or
    # aborted sync must leave a durable, queryable record, not roll it back.
    #
    #   run = RunRecorder.record_load(source_slug: source.slug) do |run|
    #     loader.load_from(adapter, workdir: dir)   # => LoadReport
    #   end
    #   RunRecorder.close([run]) { reindex!(...) }
    #
    # +kind+ is "sync" (default) or "rebuild": rebuild replays are honest run
    # history but re-add the whole corpus, so trend queries filter kind=sync.
    # The block's return value, when a LoadReport, supplies the counts
    # (LoadReport#withdrawn maps to runs.withdrawn_count).
    class RunRecorder
      # Overridable so tests can pin timestamps; production uses wall-clock.
      DEFAULT_CLOCK = -> { Time.now }

      # The notes prefix a post-load failure carries: the load landed, the
      # operation did not finish.
      POST_LOAD_FAILURE = "failed after the load: "

      def self.record(source_slug:, kind: "sync", clock: DEFAULT_CLOCK, &)
        run = record_load(source_slug: source_slug, kind: kind, clock: clock, &)
        close([run], clock: clock) { nil }
        run
      end

      def self.record_load(source_slug:, kind: "sync", clock: DEFAULT_CLOCK, &)
        new(source_slug: source_slug, kind: kind, clock: clock).record_load(&)
      end

      # Run the post-load stages (the block) and close every still-open row
      # of +runs+: "succeeded" on normal return, "failed" (re-raising) on a
      # StandardError. Rows a load stage already closed are left alone.
      # Returns the block's value.
      def self.close(runs, clock: DEFAULT_CLOCK)
        value = yield
        finish(runs, clock: clock)
        value
      rescue StandardError => e
        fail_open(runs, e, clock: clock)
        raise
      end

      # Close every still-open row of +runs+ "succeeded" — for an operation
      # whose post-load stages cannot sit in one block (a rebuild's corpus
      # stages run once after ALL its replays).
      def self.finish(runs, clock: DEFAULT_CLOCK)
        settle(runs, finished_at: clock.call, status: "succeeded")
      end

      # Close every still-open row of +runs+ "failed", naming the boundary:
      # the load landed, the operation did not finish.
      def self.fail_open(runs, error, clock: DEFAULT_CLOCK)
        settle(runs, finished_at: clock.call, status: "failed", notes: "#{POST_LOAD_FAILURE}#{error.message}")
      end

      # The terminal status of a row nobody closed: its process died (killed,
      # crashed, the machine slept through it) and the row stayed "running".
      ABANDONED = "abandoned"
      ABANDONED_NOTE = "abandoned: still running long after start — the process died without " \
                       "closing the row (closed by `nabu runs close-stale`)"

      # The open rows started before +before+ — killed runs nobody noticed
      # (the health stale-open-runs threshold supplies the cutoff), oldest
      # first. Read-only: the --dry-run view.
      def self.stale(before:)
        Run.where(status: "running").where { started_at < before }.order(:started_at, :id).all
      end

      # Settle the stale open rows "abandoned" (finished_at stamped, the
      # reason in notes) and return them. A live row inside the cutoff and
      # every closed row stand untouched.
      def self.close_stale(before:, clock: DEFAULT_CLOCK)
        rows = stale(before: before)
        settle(rows, finished_at: clock.call, status: ABANDONED, notes: ABANDONED_NOTE)
        rows
      end

      def self.settle(runs, **fields)
        ids = runs.compact.map(&:id)
        Run.where(id: ids, status: "running").update(fields) unless ids.empty?
      end
      private_class_method :settle

      def initialize(source_slug:, kind: "sync", clock: DEFAULT_CLOCK)
        @source_slug = source_slug
        @kind = kind
        @clock = clock
      end

      # The load stage: returns the Store::Run row, still "running", with the
      # load's counts and loaded_at stamped; re-raises (after recording the
      # failure, which closes the row) on error.
      def record_load
        run = Run.create(source_slug: @source_slug, kind: @kind, started_at: @clock.call, status: "running")
        result = yield(run)
        run.update(loaded_at: @clock.call, **counts_from(result))
        run
      rescue StandardError => e
        status = e.is_a?(Nabu::SyncAborted) ? "aborted" : "failed"
        run&.update(finished_at: @clock.call, status: status, notes: e.message)
        raise
      end

      private

      def counts_from(result)
        return {} unless result.is_a?(LoadReport)

        {
          added: result.added, updated: result.updated,
          withdrawn_count: result.withdrawn, errored: result.errored
        }
      end
    end
  end
end
