# frozen_string_literal: true

require_relative "parallels"
require_relative "parallels_fuzzy"
require_relative "parallels_hub"

module Nabu
  module Query
    # The contiguity bonus (architecture §13 "Measuring the engine" — the
    # third of the parallels borrowings, measured through
    # `rake bench:parallels` before any admission). The exact tier scores
    # a candidate by the summed rarity of the anchor grams it shares, so
    # two candidates sharing the same grams at the same rarity tie —
    # whether the grams form ONE continuous shared phrase (a quotation, a
    # second edition of the same line) or lie scattered across the
    # candidate (formula fragments, coincidence). Contiguity is evidence
    # the bag of grams throws away; this technique puts it back.
    #
    # == The continuation, verified on the candidate side
    #
    # Anchor gram i CONTINUES its predecessor in a candidate when both
    # grams i−1 and i are matched AND the candidate's stored search form
    # holds the anchor's (gram_size + 1)-token phrase starting at i−1
    # verbatim — so the two grams sit side by side in the CANDIDATE too,
    # not merely at adjacent anchor positions (two FTS phrase hits prove
    # presence, never adjacency; at gram size 1 adjacent anchor words may
    # lie anywhere in the candidate). The candidate's text is read only
    # for passages holding at least one anchor-adjacent matched pair —
    # the only ones a continuation can exist for.
    #
    # == The bonus
    #
    #   score' = score + W · Σ_{continuing grams i} 1/df(gram i)
    #
    # A gram that continues a verified run counts (1 + W) times its own
    # rarity weight; a run's FIRST gram, and every scattered gram, count
    # once, exactly as today. Shape, argued: the bonus is LINEAR in the
    # run's rarity mass, so (a) at equal gram count and rarity a
    # contiguous candidate strictly outranks a scattered one; (b) it
    # scales with the evidence — a run of common grams earns little, a
    # run of rare ones much — so contiguity can never manufacture a
    # parallel out of junk; (c) it is bounded, score' ≤ (1 + W)·score, so
    # it re-orders near-ties and never swamps a rarer shared phrase by
    # more than the factor (1 + W). W = 1 by default (a continuing gram
    # counts double); the bench's CONTIGUITY_WEIGHT knob sweeps it, and
    # W = 0 reports the figures below with scoring byte-identical to the
    # exact engine's (pinned).
    #
    # == Two figures, never conflated
    #
    # Every hit reports, for its representative passage, in ANCHOR TOKENS:
    #
    # * +longest_run+ — the longest verified run of consecutive matched
    #   grams (k grams = k + gram_size − 1 tokens), i.e. the longest
    #   anchor phrase the candidate holds verbatim through matched grams.
    #   The bonus rides on runs like it.
    # * +bridged_span+ — the longest chain of such runs in which each next
    #   run follows the previous one, in the anchor AND in the candidate,
    #   after a gap of at most DAMAGE_BRIDGE tokens on each side (a
    #   substituted, lost or intruded token — damage, a lacuna mark, a
    #   variant); the span counts the bridged tokens. It is REPORTED, never
    #   scored: a bridged span is not a contiguous run, and a damaged
    #   witness earns no bonus across its damage.
    #
    # bridged_span ≥ longest_run always; they differ exactly when a bridge
    # joined two runs. 0 / 0 for a hit with no exact gram (a fuzzy-only
    # hit).
    #
    # == Composition
    #
    # The bonus acts last, on the final score of whichever tier carries it
    # (ParallelsFuzzyContiguous, ParallelsHubContiguous,
    # ParallelsFuzzyHubContiguous), and counts the RAW 1/df of a
    # continuing gram — under hub demotion a continuing hub gram earns its
    # raw rarity back as bonus (stated; the bench measures the pair).
    # Under the fuzzy fallback a fuzzy-only anchor has no exact gram, so
    # no run, and its answer is the fuzzy tier's.
    #
    # == Why a module outside Parallels
    #
    # The ParallelsFuzzy / HubDemotion argument: query/parallels.rb (and
    # the batch producer) sit inside the batch miner's links-stamp closure
    # (LinkStamps.code_files), so even a default-off flag there re-mines
    # every persisted parallels scope. This file is required only by the
    # bench; it observes the engine through its private seams (shingle,
    # fts_probe, probe_grams, document_hit).
    module ContiguityBonus
      # The default bonus weight W: a continuing gram counts double.
      # const: a scoring ratio within one tier, not a corpus claim
      CONTIGUITY_WEIGHT = 1.0

      # Tokens of damage a bridged span may cross on EACH side (one lost
      # or substituted slot — the fuzzy tier's tolerance).
      # const: an alignment tolerance, not a corpus claim
      DAMAGE_BRIDGE = 1

      # The candidate-text read's batch width (an IN-list over catalog ids).
      # const: an SQLite bound-parameter batch size, not a corpus claim
      TEXT_BATCH = 500

      attr_reader :contiguity_weight

      def initialize(contiguity_weight: CONTIGUITY_WEIGHT, **)
        unless contiguity_weight.is_a?(Numeric) && contiguity_weight.to_f.finite? && !contiguity_weight.negative?
          raise ArgumentError, "contiguity_weight must be a non-negative number, got #{contiguity_weight.inspect}"
        end

        super(**)
        @contiguity_weight = contiguity_weight.to_f
      end

      def run(urn, **)
        @candidate_tokens = {}
        super
      ensure
        @candidate_tokens = nil
      end

      private

      # -- observation seams -------------------------------------------------

      def shingle(tokens, size)
        @contig_tokens = tokens
        @contig_gram_size = size
        super
      end

      # Record each probe's df (the exact tier probes each distinct gram
      # once), so per-position rarity is re-derived with no second read.
      def fts_probe(gram)
        rows = super
        @contig_df[gram] = rows.size if @contig_df
        rows
      end

      def probe_grams(gram_index, anchor_passage_id:)
        @contig_df = {}
        scores, matched = super
        @position_weight = position_weights(gram_index)
        add_bonus!(scores, matched) if @contiguity_weight.positive?
        [scores, matched]
      ensure
        @contig_df = nil
      end

      def document_hit(doc_rows, scores, matched, tokens, gram_size)
        hit = super
        best = doc_rows.max_by { |row| scores[row.fetch(:passage_id)] }
        pid = best.fetch(:passage_id)
        positions = matched.fetch(pid, []).uniq.sort
        run, span = positions.empty? ? [0, 0] : figures(positions, candidate_tokens([pid]).fetch(pid, []))
        ContiguousHit.new(**hit.to_h, longest_run: run, bridged_span: span)
      end

      # -- the bonus -----------------------------------------------------------

      # { anchor position => 1/df } for every scored gram position — the
      # exact tier's own weight (df cap applied).
      def position_weights(gram_index)
        gram_index.each_with_object({}) do |(gram, indices), weights|
          df = @contig_df.fetch(gram, 0)
          next if df.zero? || df >= @common_gram_df

          indices.each { |index| weights[index] = 1.0 / df }
        end
      end

      def add_bonus!(scores, matched)
        pending = matched.filter_map { |pid, indices| pid if adjacent_pair?(indices) }
        return if pending.empty?

        texts = candidate_tokens(pending)
        pending.each do |pid|
          continuing = continuations(matched[pid].uniq, texts.fetch(pid, []))
          scores[pid] += @contiguity_weight * continuing.sum { |index| @position_weight.fetch(index, 0.0) }
        end
      end

      def adjacent_pair?(indices)
        set = indices.to_set
        set.any? { |index| set.include?(index + 1) }
      end

      # The matched positions i whose (gram_size + 1)-token anchor phrase
      # at i−1 the candidate holds verbatim.
      def continuations(positions, candidate)
        set = positions.to_set
        width = @contig_gram_size + 1
        phrases = candidate.each_cons(width).to_set
        positions.select { |index| set.include?(index - 1) && phrases.include?(@contig_tokens[index - 1, width]) }
                 .to_set
      end

      # { passage id => its search-form tokens } — read once per run.
      def candidate_tokens(pids)
        missing = pids.reject { |pid| @candidate_tokens.key?(pid) }
        missing.sort.each_slice(TEXT_BATCH) do |slice|
          @catalog[:passages].where(id: slice).select_map(%i[id text_search]).each do |id, text|
            @candidate_tokens[id] = gram_tokens(text.to_s)
          end
        end
        @candidate_tokens
      end

      # -- the two figures -----------------------------------------------------

      # [longest_run, bridged_span] in anchor tokens for one candidate's
      # matched +positions+ against its search-form token Array.
      def figures(positions, candidate)
        segments = verbatim_segments(positions, candidate)
        longest = segments.map { |seg| seg[:last] - seg[:first] + 1 }.max || 0
        [longest, bridged_span(segments) || longest]
      end

      # Every maximal verbatim segment the candidate shares with the
      # anchor INSIDE a stretch of anchor-consecutive matched grams, at
      # least one gram long (so every gram in it is a matched gram): the
      # anchor token interval [first, last] and the candidate interval
      # [at, ends]. A verbatim segment, not a chain of locally adjacent
      # pairs — "a b" and "b c" held apart in the candidate are two runs.
      def verbatim_segments(positions, candidate)
        where = Hash.new { |hash, key| hash[key] = [] }
        candidate.each_with_index { |token, at| where[token] << at }
        positions.slice_when { |a, b| b != a + 1 }.flat_map do |stretch|
          stretch_segments(stretch.first, stretch.last + @contig_gram_size - 1, candidate, where)
        end
      end

      def stretch_segments(first, last, candidate, where)
        (first..last).flat_map do |i|
          where.fetch(@contig_tokens[i], []).filter_map do |at|
            next if i > first && at.positive? && candidate[at - 1] == @contig_tokens[i - 1]

            length = 1
            length += 1 while i + length <= last && candidate[at + length] == @contig_tokens[i + length]
            { first: i, last: i + length - 1, at: at, ends: at + length - 1 } if length >= @contig_gram_size
          end
        end
      end

      # The longest chain of segments, each following the previous within
      # DAMAGE_BRIDGE tokens on both sides — in the anchor AND in the
      # candidate, so the chain is verified, not assumed.
      def bridged_span(segments)
        nodes = segments.sort_by { |seg| [seg[:first], seg[:at]] }
        nodes.each_with_index do |node, k|
          node[:start] = nodes.first(k).filter_map { |prior| prior[:start] if bridges?(prior, node) }
                                       .push(node[:first]).min
        end
        nodes.map { |node| node[:last] - node[:start] + 1 }.max
      end

      def bridges?(prior, node)
        (node[:first] - prior[:last] - 1).between?(0, DAMAGE_BRIDGE) &&
          (node[:at] - prior[:ends] - 1).between?(0, DAMAGE_BRIDGE)
      end
    end

    # A hit with the two contiguity figures beside the exact Hit's fields.
    ContiguousHit = Data.define(*Parallels::Hit.members, :longest_run, :bridged_span)

    # The exact engine with the contiguity bonus (bench CONTIGUITY=on).
    class ParallelsContiguous < Parallels
      include ContiguityBonus
    end

    # The fuzzy tier with the bonus on its exact grams.
    class ParallelsFuzzyContiguous < ParallelsFuzzy
      include ContiguityBonus
    end

    # Hub demotion with the bonus applied after it.
    class ParallelsHubContiguous < ParallelsHub
      include ContiguityBonus
    end

    # All three borrowings together.
    class ParallelsFuzzyHubContiguous < ParallelsFuzzyHub
      include ContiguityBonus
    end
  end
end
