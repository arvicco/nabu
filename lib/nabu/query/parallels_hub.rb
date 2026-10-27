# frozen_string_literal: true

require_relative "parallels"
require_relative "parallels_fuzzy"

module Nabu
  module Query
    # Hub demotion (architecture §13 "Measuring the engine" — the second of
    # the parallels borrowings, admitted through `rake bench:parallels`).
    # The exact tier weights each shared gram 1/df, so one common gram
    # weighs little — but a stock formula (a liturgical opening, a dating
    # clause, a sutta's framing narrative) is MANY moderately common grams,
    # and every passage carrying it piles them up: the hubs of the formula
    # outrank a true parallel sharing one distinctive phrase.
    #
    # The technique splits a candidate's score in two. A gram whose df
    # reaches the HUB cutoff is ubiquitous; its mass is the candidate's hub
    # mass, and the rest its distinctive mass. The hub mass is SATURATED,
    # c·h / (h + c) with c = 1 / hub_df — monotone (more shared formula
    # still ranks higher among formula-only candidates) and strictly below
    # c, the weight of the rarest possible hub gram, so ANY distinctive
    # shared gram (df < hub_df, weight > c) outranks a pile of formula.
    # Candidates are demoted, never dropped; the evidence spans and gram
    # counts are untouched (they say WHAT matched, not how it weighs).
    #
    # The hub cutoff is corpus-relative exactly like the exact tier's df
    # cap (D36-a): max(HUB_GRAM_DF, round(HUB_GRAM_DF_RATIO × passages)),
    # snapshot per run; +hub_df:+ pins an absolute value (the bench's
    # HUB_DF knob, the tests' tiny corpora).
    #
    # == Measured, not admitted
    #
    # On the six held gold sets the technique moves recall by a few
    # partner slots either way (architecture §13): the exact tier's 1/df
    # weight already does most of the demoting, and the misses lie
    # elsewhere. It stays a bench-switchable module, both states pinned.
    #
    # == Composition with the fuzzy tier
    #
    # Demotion acts on the EXACT tier's grams only. Under the fuzzy tier's
    # measured scope (fallback) the two never meet: fuzzy fires only for an
    # anchor the exact tier scored nothing for, and there is then no exact
    # mass to demote. ParallelsFuzzyHub carries both.
    #
    # == Why a module outside Parallels
    #
    # The ParallelsFuzzy argument: query/parallels.rb sits inside the batch
    # miner's links-stamp closure (LinkStamps.code_files), so even a
    # default-off flag there re-mines every persisted parallels scope. This
    # file is required only by the bench; it observes the engine through
    # its private seams (fts_probe, probe_grams, snapshot_cutoffs).
    module HubDemotion
      # The absolute hub floor AND the unavailable-count fallback: the
      # bench-measured cutoff (cutoffs 5/10/20/50 swept; 10 the steadiest —
      # architecture §13). A gram in ten or more passages is formula.
      # census: 117962798, 2026-10-27, live catalog passage high-water mark
      # (the bench sweep's corpus)
      HUB_GRAM_DF = 10

      # The corpus-relative hub cutoff (D36-a shape): the measured floor
      # over the corpus it was measured on, so the cutoff keeps its
      # selectivity as the corpus grows.
      # const: the tuning ratio — 10 hub passages of the 117,962,798-passage
      # tuning corpus, invariant under corpus growth
      HUB_GRAM_DF_RATIO = Rational(10, 117_962_798)

      attr_reader :hub_gram_df

      def initialize(hub_df: nil, **)
        unless hub_df.nil? || (hub_df.is_a?(Integer) && hub_df.positive?)
          raise ArgumentError, "hub_df must be a positive integer, got #{hub_df.inspect}"
        end

        super(**)
        @hub_df = hub_df
      end

      private

      def snapshot_cutoffs
        super
        @hub_gram_df = @hub_df || relative_cutoff(corpus_passage_count, HUB_GRAM_DF_RATIO, HUB_GRAM_DF)
      end

      # Record every probe's rows (the exact tier probes each distinct gram
      # once), so the hub mass is re-derived with no second FTS read.
      def fts_probe(gram)
        rows = super
        @probe_rows[gram] = rows if @probe_rows
        rows
      end

      def probe_grams(gram_index, anchor_passage_id:)
        @probe_rows = {}
        scores, matched = super
        demote!(scores, hub_mass(gram_index, @probe_rows, anchor_passage_id))
        [scores, matched]
      ensure
        @probe_rows = nil
      end

      # { passage id => summed weight of its shared hub grams } — the exact
      # tier's own arithmetic (positions / df, df cap applied), restricted
      # to the grams at or above the hub cutoff.
      def hub_mass(gram_index, probe_rows, anchor_passage_id)
        mass = Hash.new(0.0)
        gram_index.each do |gram, indices|
          rows = probe_rows.fetch(gram, [])
          df = rows.size
          next if df < @hub_gram_df || df >= @common_gram_df

          weight = 1.0 / df
          rows.each do |row|
            pid = row.fetch(:passage_id)
            mass[pid] += weight * indices.size unless pid == anchor_passage_id
          end
        end
        mass
      end

      def demote!(scores, mass)
        cap = 1.0 / @hub_gram_df
        mass.each do |pid, hub|
          distinctive = [scores[pid] - hub, 0.0].max
          scores[pid] = distinctive + (cap * hub / (hub + cap))
        end
      end
    end

    # The exact engine with hub demotion (bench HUB=on).
    class ParallelsHub < Parallels
      include HubDemotion
    end

    # The fuzzy tier with hub demotion on its exact grams (bench
    # FUZZY=<scope> HUB=on).
    class ParallelsFuzzyHub < ParallelsFuzzy
      include HubDemotion
    end
  end
end
