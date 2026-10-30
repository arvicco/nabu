# frozen_string_literal: true

require_relative "parallels"
require_relative "parallels_fuzzy"
require_relative "parallels_hub"
require_relative "parallels_contiguity"

module Nabu
  module Query
    # Novelty weighting (architecture §13 "Measuring the engine" — the
    # fourth of the parallels borrowings, measured through
    # `rake bench:parallels` before any admission). The exact tier weighs
    # a shared gram 1/df, so every gram of equal corpus rarity weighs
    # alike — whether it is a line the anchor says ONCE (a candidate
    # sharing it is echoing THIS passage) or a stock formula the anchor's
    # own work repeats passage after passage (a framing narrative, a
    # refrain, a dating clause: a candidate sharing it shares the WORK's
    # boilerplate, not the passage's distinctive content). This technique
    # discounts the second kind.
    #
    # == What it reads, and why no index is needed
    #
    # The exact tier's probe of each anchor gram already returns every
    # passage holding it (df below the cap — a gram at the cap is dropped
    # unscored, so every scored gram's row list is COMPLETE), as catalog
    # passage ids. The anchor's own document is one indexed range read
    # (the unique (document_id, sequence) index's left prefix), cached
    # per document — the bench's document queries probe many anchors of
    # one document in a row. So the self-recurrence of every scored gram
    #
    #   s(g) = |{ passages of the anchor's document, other than the anchor,
    #             holding g }|
    #
    # is an exact count derived from rows the engine already holds: no
    # second FTS read, no new table, no migration.
    #
    # "Work" here is the DOCUMENT: the catalog holds no cross-source work
    # identity (Parallels rider ii), and the document is also the grain
    # the engine excludes and ranks at.
    #
    # == The weight
    #
    #   w'(g) = (1/df(g)) · 1 / (1 + W · s(g))
    #
    # A gram the anchor's document never repeats (s = 0) keeps its exact
    # weight; one repeated in k other passages of the document weighs
    # 1/(1 + W·k) of it. Shape, argued: (a) at equal df, a distinctive
    # line strictly outranks the document's own formula — the case the
    # technique exists for; (b) the factor lies in (0, 1], so candidates
    # are demoted, never dropped, and nothing gains; (c) it is anchor-
    # RELATIVE — a formula pervasive across OTHER documents but said once
    # here is left to 1/df (and to hub demotion, the technique for
    # corpus-wide formulae); (d) it is monotone in s, so a refrain
    # repeated twenty times weighs less than one repeated twice.
    # W = 1 by default; the bench's NOVELTY_WEIGHT knob sweeps it, and
    # W = 0 scores byte-identically to the tier beneath (pinned).
    #
    # == Composition: a ratio on the final score
    #
    # Applied to the plain engine the per-gram weight is exact. Composed
    # with the other tiers it acts LAST, as the candidate's novelty ratio
    #
    #   score' = score · Σ_g w'(g)·n(g) / Σ_g n(g)/df(g)
    #
    # over the candidate's exact grams g (n(g) the anchor positions g
    # occupies) — the share of its exact rarity mass that is novel —
    # multiplying whatever the tier beneath produced (hub-demoted score,
    # contiguity bonus, a fuzzy :all tier's added mass). A candidate
    # holding no self-recurrent gram is not touched at all (byte-identical
    # score), which includes every fuzzy-fallback-only candidate (it holds
    # no exact gram).
    #
    # == Why a module outside Parallels
    #
    # The ParallelsFuzzy / HubDemotion / ContiguityBonus argument:
    # query/parallels.rb sits inside the batch miner's links-stamp closure
    # (LinkStamps.code_files), so even a default-off flag there re-mines
    # every persisted parallels scope. This file is required only by the
    # bench; it observes the engine through its private seams (load_anchor,
    # fts_probe, probe_grams).
    module NoveltyWeighting
      # The default novelty weight W: one self-repeat halves a gram.
      # const: a scoring ratio within one tier, not a corpus claim
      NOVELTY_WEIGHT = 1.0

      attr_reader :novelty_weight

      def initialize(novelty_weight: NOVELTY_WEIGHT, **)
        unless novelty_weight.is_a?(Numeric) && novelty_weight.to_f.finite? && !novelty_weight.negative?
          raise ArgumentError, "novelty_weight must be a non-negative number, got #{novelty_weight.inspect}"
        end

        super(**)
        @novelty_weight = novelty_weight.to_f
      end

      private

      # -- observation seams -------------------------------------------------

      def load_anchor(urn)
        anchor = super
        @novelty_document_id = anchor&.fetch(:document_id)
        anchor
      end

      # Record each probe's rows (the exact tier probes each distinct gram
      # once), so the self-recurrence is counted with no second read.
      def fts_probe(gram)
        rows = super
        @novelty_rows[gram] = rows if @novelty_rows
        rows
      end

      def probe_grams(gram_index, anchor_passage_id:)
        @novelty_rows = {}
        scores, matched = super
        renovate!(scores, gram_index, @novelty_rows, anchor_passage_id) if @novelty_weight.positive?
        [scores, matched]
      ensure
        @novelty_rows = nil
      end

      # -- the weighting -------------------------------------------------------

      def renovate!(scores, gram_index, probe_rows, anchor_passage_id)
        own = anchor_document_passages
        raw = Hash.new(0.0)
        lost = Hash.new(0.0)
        gram_index.each do |gram, indices|
          rows = probe_rows.fetch(gram, [])
          df = rows.size
          next if df.zero? || df >= @common_gram_df

          pids = rows.map { |row| row.fetch(:passage_id) }
          weight = indices.size.fdiv(df)
          repeats = pids.count { |pid| pid != anchor_passage_id && own.include?(pid) }
          penalty = weight * (1.0 - (1.0 / (1.0 + (@novelty_weight * repeats))))
          pids.each do |pid|
            next if pid == anchor_passage_id

            raw[pid] += weight
            lost[pid] += penalty if repeats.positive?
          end
        end
        lost.each { |pid, mass| scores[pid] *= (raw[pid] - mass) / raw[pid] if scores.key?(pid) }
      end

      # The anchor document's passage ids — one indexed read per distinct
      # document, kept while consecutive anchors share it.
      def anchor_document_passages
        return @novelty_own if @novelty_own_document == @novelty_document_id && @novelty_own

        @novelty_own_document = @novelty_document_id
        @novelty_own = @catalog[:passages].where(document_id: @novelty_document_id).select_map(:id).to_set
      end
    end

    # The exact engine with novelty weighting (bench NOVELTY=on).
    class ParallelsNovel < Parallels
      include NoveltyWeighting
    end

    # Each other tier combination with novelty acting last on its score.
    class ParallelsFuzzyNovel < ParallelsFuzzy
      include NoveltyWeighting
    end

    class ParallelsHubNovel < ParallelsHub
      include NoveltyWeighting
    end

    class ParallelsFuzzyHubNovel < ParallelsFuzzyHub
      include NoveltyWeighting
    end

    class ParallelsContiguousNovel < ParallelsContiguous
      include NoveltyWeighting
    end

    class ParallelsFuzzyContiguousNovel < ParallelsFuzzyContiguous
      include NoveltyWeighting
    end

    class ParallelsHubContiguousNovel < ParallelsHubContiguous
      include NoveltyWeighting
    end

    # All four borrowings together.
    class ParallelsFuzzyHubContiguousNovel < ParallelsFuzzyHubContiguous
      include NoveltyWeighting
    end
  end
end
