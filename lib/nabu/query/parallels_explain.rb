# frozen_string_literal: true

require_relative "parallels"

module Nabu
  module Query
    # The parallels EXPLAIN surface: the same engine as Query::Parallels,
    # every hit additionally carrying its score's per-gram decomposition.
    #
    # Parallels scores a candidate passage as Σ (anchor positions × 1/df)
    # over the anchor grams it shares — so the score is ADDITIVE in the
    # grams, and the decomposition is exact by construction: one row per
    # distinct anchor gram (gram → document frequency → rarity weight →
    # contribution), the rows summing to the served score EXACTLY, the
    # grams that add nothing present as explicit zero rows naming why
    # (not_shared · too_common · stop). The raw material is the probe's
    # own hit counts, captured as the engine runs — no second query per
    # gram, no change to what the engine computes.
    #
    # == Why a subclass, not a flag on Parallels
    #
    # The batch miner's links stamp digests the require closure of
    # batch_parallels.rb (LinkStamps.code_files) — query/parallels.rb
    # included. An explain flag inside the engine would move that digest
    # and re-mine every persisted parallels scope at the next rebuild for
    # a change that cannot alter one edge. This file sits OUTSIDE the
    # closure (only the MCP layer requires it), observing the engine
    # through its own private seams: the shingles, the indexed grams, each
    # gram probe's row count, and the candidate rows (urn → passage id).
    class ParallelsExplain < Parallels
      # Parallels::Hit plus the decomposition rows.
      ExplainedHit = Data.define(*Parallels::Hit.members, :contributions)

      # One row of a hit's score decomposition: the folded +gram+, its first
      # anchor +position+ and anchor occurrence count (+positions+), its
      # probe document frequency +df+ (nil when never probed), the rarity
      # +weight+ (1/df, or 0 when the gram cannot score), and its
      # +contribution+ to the score (positions × weight when shared, else 0
      # — apportioned at the score's 4-place grain so the rows sum to the
      # served score exactly). +status+: shared · not_shared (scored gram
      # this passage lacks) · too_common (df at/over the corpus-relative
      # cutoff — the probe stopped there, so df reads as that floor) · stop
      # (an all-stop-token gram, never probed).
      Contribution = Data.define(:gram, :position, :positions, :df, :weight, :contribution, :status)

      # The decimal grain of a served score (Parallels#document_hit rounds
      # Hit#score to it).
      # const: a display precision, not a corpus claim
      SCORE_PLACES = 4
      UNIT = 10**SCORE_PLACES

      def run(urn, **)
        @grams = []
        @gram_index = {}
        @dfs = {}
        @pids = {}
        super
      end

      private

      # -- observation seams (each calls the engine's own method) -----------

      def shingle(tokens, size)
        @grams = super
      end

      def index_grams(grams, stop_tokens = nil)
        @gram_index = super
      end

      def fts_probe(gram)
        rows = super
        @dfs[gram] = rows.size
        rows
      end

      def candidate_rows(passage_ids, **)
        rows = super
        rows.each { |row| @pids[row.fetch(:urn)] = row.fetch(:passage_id) }
        rows
      end

      # The engine's page, each hit decomposed. +matched+ is the engine's
      # own pid → shared anchor positions map.
      def assemble(scores, matched, **)
        explainer = explain_grams
        super.map do |hit|
          rows = contributions(explainer, matched[@pids.fetch(hit.urn)], hit.score)
          ExplainedHit.new(**hit.to_h, contributions: rows)
        end
      end

      # -- the decomposition -------------------------------------------------

      # Every DISTINCT anchor gram in first-position order — probed or not —
      # with the facts its row needs: tokens, first position, occurrence
      # count, df (nil = never probed), base status, exact rarity weight
      # (Rational; 0 when the gram cannot score).
      def explain_grams
        seen = {}
        @grams.each_with_index do |gram, position|
          (seen[gram] ||= { gram: gram, position: position, positions: 0 })[:positions] += 1
        end
        seen.values.map do |entry|
          probed = @gram_index.key?(entry[:gram])
          df = @dfs[entry[:gram]]
          status = if !probed then "stop"
                   elsif df.zero? || df >= @common_gram_df then "too_common"
                   else "scored"
                   end
          entry.merge(df: probed ? df : nil, status: status,
                      weight: status == "scored" ? Rational(1, df) : 0)
        end
      end

      # One hit's rows. The exact contributions (positions × 1/df over the
      # grams this passage shares) are APPORTIONED onto the score's 4-place
      # grain by largest remainder against the served score's own units, so
      # the rows sum to Hit#score exactly — never a ±1e-4 rounding drift —
      # while each row stays within one unit of its exact value.
      def contributions(explainer, matched_indices, score)
        shared = matched_indices.to_set
        exact = explainer.map do |entry|
          entry[:weight].positive? && shared.include?(entry[:position]) ? entry[:weight] * entry[:positions] : 0
        end
        units = apportion(exact, target: (score * UNIT).round)
        rows = explainer.each_with_index.map do |entry, i|
          Contribution.new(
            gram: Grams.join(entry[:gram]), position: entry[:position], positions: entry[:positions],
            df: entry[:df], weight: entry[:weight].to_f.round(6),
            contribution: units[i].to_f / UNIT, status: row_status(entry, exact[i])
          )
        end
        rows.sort_by { |row| [-row.contribution, row.position] }
      end

      def row_status(entry, exact)
        return entry[:status] unless entry[:status] == "scored"

        exact.positive? ? "shared" : "not_shared"
      end

      # Largest-remainder apportionment: integer units per row summing to
      # +target+, each the floor or ceiling of its exact value (zero rows
      # stay zero). The residue is bounded by the row count, so one pass of
      # +1/-1 over the remainders settles it.
      def apportion(exact, target:)
        scaled = exact.map { |value| value * UNIT }
        units = scaled.map(&:floor)
        residue = target - units.sum
        order = scaled.each_index.select { |i| scaled[i].positive? }
        if residue.positive?
          largest = order.sort_by { |i| [-(scaled[i] - units[i]), i] }
          largest.cycle.first(residue).each { |i| units[i] += 1 }
        elsif residue.negative?
          smallest = order.select { |i| units[i].positive? }.sort_by { |i| [scaled[i] - units[i], i] }
          smallest.cycle.first(-residue).each { |i| units[i] -= 1 }
        end
        units
      end
    end
  end
end
