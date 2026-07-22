# frozen_string_literal: true

module Nabu
  # Per-source / per-stage wall-time capture for `nabu rebuild` (P36-0, the
  # profiler that must precede any optimization — dev-loop §6b, "numbers before
  # optimization"). Observability, NOT derived data: it holds monotonic-clock
  # deltas in memory for the length of one rebuild and is never persisted (so it
  # is rebuild-safe by construction — there is nothing under db/ to regenerate).
  #
  # == The two levels
  #
  # - A per-source +:load+ roll-up (measured around the whole replay) is the
  #   authoritative per-source number — it includes adapter build, the run
  #   recorder and the quarantine-baseline bookkeeping, not just parse+insert.
  #   The corpus "load" total sums these.
  # - +:parse+ / +:insert+ are COMPONENTS of a source's :load (the parse call vs
  #   the db-write transaction, sampled per document — coarse, never per
  #   passage). They are diagnostic sub-numbers: parse+insert ≲ :load for an
  #   instrumented loader, and they are never re-summed into the grand total.
  #   NOTE :parse INCLUDES text-normalization/fold: search_form (the per-
  #   language fold, e.g. the hani trad↔simp collapse for lzh/cbeta) runs at
  #   Passage construction, which happens inside the adapter's parse call.
  #   Splitting fold out would need a per-passage timer, which the always-on
  #   budget forbids (same reason fts_lemma stays one stage) — fold-cost
  #   attribution is a benchmark-harness job, not an always-on stage.
  #   A source whose loader is not instrumented (a dossier/note shelf) still
  #   carries its :load roll-up, just no parse/insert split.
  #
  # == Corpus stages
  #
  # timeline / facets (the post-load builders) and, inside the corpus-wide
  # reindex, fts_lemma / trigram / alignment / reflex. NOTE fts_lemma is ONE
  # stage on purpose: the FTS tokenize and the lemma-index build share a single
  # streaming row scan (Indexer#insert_passage_batches feeds passages_fts and
  # passage_lemmas together), so separating "tokenize seconds" from "lemma
  # seconds" would need a per-passage timer, which the always-on budget forbids.
  #
  # Every sample is one +Process.clock_gettime(CLOCK_MONOTONIC)+ pair per stage
  # boundary (per document for parse/insert), cheap enough to keep ON always.
  class RebuildProfile
    # The scope key for a corpus-wide stage (vs a source slug).
    CORPUS = :corpus

    # Stages that are components of a source's :load and so are NOT summed into
    # the grand total (they double-count against :load).
    COMPONENT_STAGES = %i[parse insert].freeze

    # Human-facing order + labels for the corpus stages in the table.
    CORPUS_STAGE_LABELS = {
      timeline: "timeline",
      facets: "facets",
      fts_lemma: "fts+lemma reindex",
      trigram: "trigram",
      alignment: "alignment refs",
      reflex: "reflex roots"
    }.freeze

    def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @clock = clock
      @seconds = Hash.new(0.0) # [scope, stage] => accumulated wall seconds
    end

    # Time a block, accumulate its wall seconds under (scope, stage), and return
    # the block's own value (so it can wrap a builder that returns a summary).
    # A raise propagates and records nothing — a rebuild aborts on real trouble
    # and a half-run stage would be a lie.
    def measure(scope:, stage:)
      started = @clock.call
      result = yield
      add(scope: scope, stage: stage, seconds: @clock.call - started)
      result
    end

    # Fold a raw delta in (for the per-document parse/insert accumulators, which
    # time the call themselves and add the delta here).
    def add(scope:, stage:, seconds:)
      @seconds[[scope, stage]] += seconds
      self
    end

    # Seconds recorded for one (scope, stage), 0.0 if never sampled.
    def seconds(scope:, stage:) = @seconds[[scope, stage]]

    # Source slugs that recorded a :load roll-up, sorted by that roll-up desc
    # (the hotspot order — heaviest source first).
    def source_scopes
      @seconds.keys
              .select { |scope, stage| scope != CORPUS && stage == :load }
              .map { |scope, _| scope }
              .sort_by { |scope| -@seconds[[scope, :load]] }
    end

    # Corpus stages that recorded time, sorted desc.
    def corpus_stages
      CORPUS_STAGE_LABELS.keys
                         .select { |stage| @seconds.key?([CORPUS, stage]) }
                         .sort_by { |stage| -@seconds[[CORPUS, stage]] }
    end

    # Total load seconds across every source (the :load roll-ups summed).
    def load_total = source_scopes.sum { |scope| @seconds[[scope, :load]] }

    # Total for one corpus stage.
    def corpus_total(stage) = @seconds[[CORPUS, stage]]

    # The grand total: source loads + every corpus stage. Component stages
    # (parse/insert) are deliberately excluded — they are inside :load.
    def grand_total
      load_total + CORPUS_STAGE_LABELS.keys.sum { |stage| @seconds[[CORPUS, stage]] }
    end

    # Nothing measured at all (an empty rebuild) — the report suppresses itself.
    def empty? = @seconds.empty?

    # A flat, ordered list of [label, seconds, share] rows for the whole
    # rebuild, heaviest first: every source's :load, then the corpus stages.
    # +share+ is the fraction of grand_total (0.0 when the total is zero).
    def rows
      total = grand_total
      share = ->(secs) { total.zero? ? 0.0 : secs / total }
      source_rows = source_scopes.map do |scope|
        [scope, @seconds[[scope, :load]], share.call(@seconds[[scope, :load]])]
      end
      corpus_rows = corpus_stages.map do |stage|
        secs = @seconds[[CORPUS, stage]]
        [CORPUS_STAGE_LABELS[stage], secs, share.call(secs)]
      end
      (source_rows + corpus_rows).sort_by { |_, secs, _| -secs }
    end

    # The parse/insert split for a source, or nil when that loader was not
    # instrumented (no component was ever sampled for it).
    def breakdown(scope)
      parse = @seconds[[scope, :parse]]
      insert = @seconds[[scope, :insert]]
      return nil if parse.zero? && insert.zero?

      { parse: parse, insert: insert }
    end

    # The corpus-wide parse / insert / index totals — the numbers that tier the
    # P36-2 (bulk-load) vs P36-3 (parallel parse) dispatch. index_total folds
    # every corpus stage; parse/insert sum the per-source components.
    def parse_total = component_total(:parse)
    def insert_total = component_total(:insert)

    def index_total
      CORPUS_STAGE_LABELS.keys.sum { |stage| @seconds[[CORPUS, stage]] }
    end

    private

    def component_total(stage)
      @seconds.sum { |(scope, kind), secs| scope != CORPUS && kind == stage ? secs : 0.0 }
    end
  end
end
