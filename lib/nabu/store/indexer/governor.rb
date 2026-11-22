# frozen_string_literal: true

# Nabu::Store::Indexer — the merge governor.
# A partial of lib/nabu/store/indexer.rb, which loads it.
module Nabu
  module Store
    module Indexer
      module_function

      # -- the merge governor (the 2026-11-11 crisis-merge stall) ------------

      # The governor for +table+'s batch loop, or nil when the table is not
      # governed (governed_fts_tables: the contentless shape only — a
      # legacy contentful file keeps the old untouched path, like every
      # other recipe of this family).
      def fts_governor(fulltext, table, progress: nil)
        return nil unless governed_fts_tables(fulltext).include?(table)

        FtsGovernor.new(fulltext: fulltext, table: table, progress: progress)
      end

      # The governor's decision over a decoded FtsStructure::Structure:
      # { level:, segments: } for the FIRST level past +level_limit+,
      # else { total: } when the total passes +total_limit+, else nil.
      # AT a limit is fine — only past it fires. A nil structure (no
      # record yet) is no pressure.
      def governor_pressure(structure, level_limit:, total_limit:)
        return nil if structure.nil?

        structure.levels.each_with_index do |level, index|
          count = level[:segments].size
          return { level: index, segments: count } if count > level_limit
        end
        return { total: structure.total_segments } if structure.total_segments > total_limit

        nil
      end

      # Holds the crisis-distance invariant over one governed batch loop
      # (class note: the governor). The loop calls #tick! after every
      # batch; every +cadence+ ticks the live structure is read, and
      # pressure is relieved in bounded merge chunks right there, between
      # batches — never inside one. Limits are parameters (the constants
      # are the defaults) so the decision is testable at small scale.
      # Inside a wrapping transaction (rebuild!'s streaming pass, the small
      # slice's atomic swap) the chunks still run — they keep the structure
      # bounded either way — but the checkpoint is skipped: a checkpoint
      # cannot reclaim an open transaction's frames.
      class FtsGovernor
        attr_reader :table, :batches, :checks, :relief_chunks

        def initialize(fulltext:, table:, progress: nil, cadence: GOVERNOR_CHECK_EVERY_BATCHES,
                       level_limit: GOVERNOR_LEVEL_LIMIT, total_limit: FtsStructure::SEGMENT_WARN)
          @fulltext = fulltext
          @table = table
          @progress = progress
          @cadence = cadence
          @level_limit = level_limit
          @total_limit = total_limit
          @batches = 0
          @checks = 0
          @relief_chunks = 0
        end

        def tick!
          @batches += 1
          check! if (@batches % @cadence).zero?
        end

        # Read the structure; relieve any pressure. Returns the chunks run.
        def check!
          @checks += 1
          found = pressure
          found ? relieve!(found) : 0
        end

        # Bounded chunks until both limits hold again or the engine reports
        # a no-op (nothing left it will merge at this grain), then a WAL
        # checkpoint when no transaction holds the frames. The loop TICKS
        # and checkpoints every 25 chunks (the consolidate_merges! cadence):
        # the first relief against a debt-laden standing index can run
        # thousands of chunks, and a long silent relief would be the very
        # single-announcement opacity the governor exists to end.
        def relieve!(found)
          @progress&.stage("fts governor: #{@table} — #{describe(found)}, consolidating")
          chunks = 0
          loop do
            chunks += 1
            if (chunks % 25).zero?
              @progress&.stage("fts governor: #{@table} — relief chunk #{chunks}")
              Indexer.checkpoint_wal!(@fulltext, progress: @progress) unless @fulltext.in_transaction?
            end
            break if Indexer.merge_chunk!(@fulltext, @table) < MERGE_NOOP_LINE
            break if pressure.nil?
          end
          @relief_chunks += chunks
          Indexer.checkpoint_wal!(@fulltext, progress: @progress) unless @fulltext.in_transaction?
          chunks
        end

        private

        def pressure
          Indexer.governor_pressure(FtsStructure.read(@fulltext, @table),
                                    level_limit: @level_limit, total_limit: @total_limit)
        end

        def describe(found)
          return "level #{found[:level]} at #{found[:segments]} segments" if found.key?(:level)

          "#{found[:total]} segments total (line #{@total_limit})"
        end
      end
    end
  end
end
