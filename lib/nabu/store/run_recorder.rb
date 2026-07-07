# frozen_string_literal: true

module Nabu
  module Store
    # Wraps a sync/rebuild in a `runs` row (architecture §8) — written to the
    # history LEDGER (Store::Ledger, P7-1), keyed by source SLUG so run
    # history survives the catalog id re-minting a rebuild performs. The
    # caller must have the ledger open (Ledger.setup! bound). Inserts the row
    # as "running" up front, yields it, and on normal return finalizes it to
    # "succeeded" with the LoadReport counts; on any error it records "failed"
    # (with the message as notes) and re-raises — except Nabu::SyncAborted (the
    # withdrawal circuit breaker), which records the durable status "aborted" so
    # a tripped breaker is distinguishable from a genuine failure. The run row is
    # deliberately *not* wrapped in the caller's transaction — a failed or
    # aborted sync must leave a durable, queryable record, not roll it back.
    #
    #   RunRecorder.record(source_slug: source.slug) do |run|
    #     loader.load_from(adapter, workdir: dir)   # => LoadReport
    #   end
    #
    # +kind+ is "sync" (default) or "rebuild": rebuild replays are honest run
    # history but re-add the whole corpus, so trend queries filter kind=sync.
    # The block's return value, when a LoadReport, supplies the counts
    # (LoadReport#withdrawn maps to runs.withdrawn_count).
    class RunRecorder
      # Overridable so tests can pin timestamps; production uses wall-clock.
      DEFAULT_CLOCK = -> { Time.now }

      def self.record(source_slug:, kind: "sync", clock: DEFAULT_CLOCK, &)
        new(source_slug: source_slug, kind: kind, clock: clock).record(&)
      end

      def initialize(source_slug:, kind: "sync", clock: DEFAULT_CLOCK)
        @source_slug = source_slug
        @kind = kind
        @clock = clock
      end

      # Returns the finalized Store::Run row on success; re-raises (after
      # recording the failure) on error.
      def record
        run = Run.create(source_slug: @source_slug, kind: @kind, started_at: @clock.call, status: "running")
        result = yield(run)
        run.update(finished_at: @clock.call, status: "succeeded", **counts_from(result))
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
