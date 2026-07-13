# frozen_string_literal: true

require_relative "query/formulas"

module Nabu
  # Producer #2 for the links journal (P16-2; architecture §15): the
  # whole-tradition formula sweep — the interactive Query::Formulas miner
  # (P15-5) run once over a SCOPE (source slug or urn prefix, the shared
  # Query::Scope grammar) with its findings PERSISTED as kind=formula edges.
  # Same substrate as BatchParallels: supersede-on-rerun, params in the run
  # row, pruning named in the summary.
  #
  # == The edge-shape verdict: a star per formula (argued)
  #
  # A formula is a REFRAIN across N loci, not a pair — it does not map onto a
  # pair-shaped links table for free. The honest options, judged by what
  # `nabu links <urn>` should USEFULLY show a reader standing at one locus:
  #
  # - ALL PAIRS is O(N²): the 72-locus ὣς ἔφαθ' οἵ δ' alone would mint 2,556
  #   edges, and a reader at one locus drowns in 71 siblings that say nothing
  #   one edge couldn't.
  # - CONSECUTIVE-LOCI CHAINS are linear but useless at read time: `links`
  #   would show only the two neighboring loci, answering "where else?" with
  #   "next door".
  # - DOCUMENT-GRAIN edges lose the loci entirely: `links <passage>` at a
  #   refrain line would show nothing.
  #
  # So: a STAR. Each formula gets one hub — its first locus in urn sort order
  # (deterministic, rebuild-stable; urns are the journal's stable currency) —
  # and edges hub → every other locus. score = the slice count (how strong
  # the refrain), detail = the folded gram itself (WHICH refrain, migration
  # 002). A reader at any locus sees `← hub “saga hwaet ic hatte” ×4`: what
  # ties the line to the tradition and how strongly; one `links <hub>` away
  # is the complete fan of loci. Edges per formula = distinct loci − 1
  # (linear); a formula recurring only WITHIN one passage mints no edge
  # (nothing to link to).
  #
  # == Pruning, stated honestly (no silent caps)
  #
  # Three knobs shape what persists, all in params_json and the summary:
  # +gram_size+ / +min_count+ (the miner's own), and +max_formulas+ — the
  # top-N by rank (count × length) kept, because a journal edge is an
  # assertion (the BatchParallels stance) and the min-count tail of a big
  # tradition is thousands of barely-recurring grams. Overlapping formulas
  # (a 5-word refrain yields two 4-grams with the same loci) collapse onto
  # the same (hub, locus) pair: the pair keeps its best-ranked gram and the
  # +coalesced+ count reports what folded in — named, never silent.
  class BatchFormulas
    PRODUCER = "formulas"
    KIND = "formula"
    # Formulas persisted per run, top-ranked first: the interactive page is
    # 25 for the eye; a batch sweep keeps a deeper slice of the tradition but
    # still cuts the min-count noise tail.
    DEFAULT_MAX_FORMULAS = 200
    # Bump when the gram/ranking machinery changes meaning, so old edges are
    # honest about the code that minted them.
    CODE_VERSION = "formulas-batch/1 nabu/#{VERSION}".freeze

    # What a batch run did. +formula_count+ = formulas persisted (≤
    # +max_formulas+ of +recurring_count+ recurring grams); +coalesced+ =
    # overlapping-formula writes folded into an existing pair this run.
    Result = Data.define(:scope, :lang, :run_id, :gram_size, :min_count, :max_formulas,
                         :recurring_count, :formula_count, :edges_written, :edges_refreshed,
                         :coalesced, :superseded_runs, :superseded_edges, :elapsed)

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Mine the slice named by +scope+ and persist its formula stars. Raises
    # ArgumentError for a bad gram size (the miner's own validation).
    def run(scope, gram_size: Query::Formulas::DEFAULT_GRAM_SIZE,
            min_count: Query::Formulas::DEFAULT_MIN_COUNT,
            max_formulas: DEFAULT_MAX_FORMULAS, lang: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # long: true = the miner's full-loci second pass — the star needs every
      # locus, not the compact pass's 3 examples.
      mined = Query::Formulas.new(catalog: @catalog)
                             .run(scope, gram_size: gram_size, min_count: min_count,
                                         lang: lang, limit: max_formulas, long: true)
      counts = { inserted: 0, refreshed: 0, coalesced: 0 }
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: scope)
        run_id = record_run(scope, gram_size: gram_size, min_count: min_count,
                                   max_formulas: max_formulas, lang: lang)
        write_stars(mined.formulas, run_id: run_id, counts: counts)
      end
      Result.new(scope: scope, lang: lang, run_id: run_id, gram_size: gram_size,
                 min_count: min_count, max_formulas: max_formulas,
                 recurring_count: mined.recurring_count, formula_count: mined.formulas.size,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 coalesced: counts[:coalesced],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 elapsed: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    private

    def record_run(scope, gram_size:, min_count:, max_formulas:, lang:)
      params = { kind: KIND, gram_size: gram_size, min_count: min_count,
                 max_formulas: max_formulas, lang: lang }.compact
      Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: scope,
                                                params: params, code_version: CODE_VERSION)
    end

    # One star per formula, best-ranked formulas first (the miner's order),
    # so when overlapping formulas share a (hub, locus) pair the pair keeps
    # the higher-ranked gram and the lower-ranked write counts as coalesced.
    def write_stars(formulas, run_id:, counts:)
      seen = Set.new
      formulas.each do |formula|
        loci = formula.loci.uniq.sort
        hub = loci.first
        loci.drop(1).each do |locus|
          unless seen.add?([hub, locus].minmax)
            counts[:coalesced] += 1
            next
          end

          outcome = Store::LinksJournal.write_edge!(
            @journal, from_urn: hub, to_urn: locus, kind: KIND,
                      score: formula.count.to_f, detail: formula.gram, run_id: run_id
          )
          counts[outcome == :inserted ? :inserted : :refreshed] += 1
        end
      end
    end
  end
end
