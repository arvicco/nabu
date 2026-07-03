# frozen_string_literal: true

module Nabu
  module Store
    # Wraps a sync/rebuild in a `runs` row (architecture §8). Inserts the row as
    # "running" up front, yields it, and on normal return finalizes it to
    # "succeeded" with the LoadReport counts; on any error it records "failed"
    # (with the message as notes) and re-raises. The run row is deliberately
    # *not* wrapped in the caller's transaction — a failed sync must leave a
    # durable, queryable failure record, not roll it back.
    #
    #   RunRecorder.record(db: db, source: source) do |run|
    #     loader.load_from(adapter, workdir: dir)   # => LoadReport
    #   end
    #
    # The block's return value, when a LoadReport, supplies the counts
    # (LoadReport#withdrawn maps to runs.withdrawn_count).
    class RunRecorder
      # Overridable so tests can pin timestamps; production uses wall-clock.
      DEFAULT_CLOCK = -> { Time.now }

      def self.record(db:, source:, clock: DEFAULT_CLOCK, &)
        new(db: db, source: source, clock: clock).record(&)
      end

      def initialize(db:, source:, clock: DEFAULT_CLOCK)
        @db = db
        @source = source
        @clock = clock
      end

      # Returns the finalized Store::Run row on success; re-raises (after
      # recording the failure) on error.
      def record
        run = Run.create(source_id: @source.id, started_at: @clock.call, status: "running")
        result = yield(run)
        run.update(finished_at: @clock.call, status: "succeeded", **counts_from(result))
        run
      rescue StandardError => e
        run&.update(finished_at: @clock.call, status: "failed", notes: e.message)
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
