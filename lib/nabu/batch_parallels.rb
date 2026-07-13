# frozen_string_literal: true

require_relative "query/catalog_join"
require_relative "query/scope"
require_relative "query/parallels"

module Nabu
  # Producer #1 for the links journal (P16-1; docs/intertext-design.md §7,
  # architecture §15): corpus-wide parallel mining over a SCOPE (a source slug
  # or urn prefix — the formulas scope grammar). The batch mode the design
  # named for the intertext engine: loop the interactive Query::Parallels
  # engine over every anchor passage of the slice and PERSIST the ranked hits
  # as kind=parallel edges, instead of printing them. Zero new index — each
  # anchor costs what the interactive query costs (1–111 ms measured).
  #
  # == Pruning, stated honestly (no silent caps)
  #
  # Two thresholds shape what persists, and the Result carries both so the CLI
  # summary can name them: +per_anchor+ (the top-N document-grain hits kept
  # per anchor — the engine's page limit doing batch duty) and +min_score+
  # (the rarity-score floor an edge must clear; the interactive engine prints
  # weak tail hits for the eye to judge, but a journal edge is an assertion,
  # so the floor cuts the pile of common-gram noise). Both are CLI knobs.
  #
  # == Dedup and rerun semantics
  #
  # Within a run, an unordered pair is written ONCE, in the direction the
  # probe first found it (anchor A discovering B persists A→B; B's later probe
  # of A is skipped). Across runs the journal enforces the same pair-per-kind
  # invariant by refreshing an existing edge in place (LinksJournal.write_edge!).
  # A rerun of the same (producer, scope) SUPERSEDES the prior run — its edges
  # and run row are replaced atomically (one journal transaction), so reruns
  # are idempotent and the journal always holds the current mining of a scope.
  #
  # == What does NOT persist
  #
  # Interactive `parallels <urn>` output (design §7: storing millisecond
  # recomputables is caching with staleness obligations). Lemma echoes are
  # also not persisted (a different signal, not a kind=parallel edge; the
  # engine skips computing them here via echoes: false).
  class BatchParallels
    include Query::CatalogJoin
    include Query::Scope

    PRODUCER = "parallels"
    KIND = "parallel"
    # An edge must clear this rarity score (Σ 1/df over shared grams): 0.05 ≈
    # one shared gram found in ≤20 passages — below that the "parallel" is a
    # bag of common function-word grams, not evidence worth asserting.
    DEFAULT_MIN_SCORE = 0.05
    # Document-grain hits kept per anchor (the engine's own grouping): a real
    # quotation network per verse is small; five covers the measured probes.
    DEFAULT_PER_ANCHOR = 5
    # The code marker every run records: bump the producer revision when the
    # scoring/gram machinery changes meaning, so old edges are honest about
    # the code that minted them.
    CODE_VERSION = "parallels-batch/1 nabu/#{VERSION} #{Query::Parallels::GRAM_SIZE}-gram".freeze

    # What a batch run did. +edges_written+ are new edges; +edges_refreshed+
    # existing pairs re-found (cross-run overlap) and updated in place;
    # +superseded_runs+/+superseded_edges+ what a rerun replaced. +elapsed+ in
    # seconds. +min_score+/+per_anchor+ ride along so the summary names its
    # thresholds.
    Result = Data.define(:scope, :lang, :run_id, :anchor_count, :edges_written,
                         :edges_refreshed, :superseded_runs, :superseded_edges,
                         :min_score, :per_anchor, :elapsed)

    def initialize(catalog:, fulltext:, journal:)
      @catalog = catalog
      @fulltext = fulltext
      @journal = journal
    end

    # Mine the slice named by +scope+; persist edges into the journal.
    # +progress+ (nil-safe) is called with (anchors_done, anchors_total,
    # edges_so_far) after every anchor — formatting stays in the CLI.
    def run(scope, min_score: DEFAULT_MIN_SCORE, per_anchor: DEFAULT_PER_ANCHOR,
            lang: nil, license: nil, progress: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      anchors = anchor_urns(scope, lang: lang)
      counts = { inserted: 0, refreshed: 0 }
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: scope)
        run_id = record_run(scope, min_score: min_score, per_anchor: per_anchor,
                                   lang: lang, license: license)
        mine(anchors, run_id: run_id, min_score: min_score, per_anchor: per_anchor,
                      lang: lang, license: license, counts: counts, progress: progress)
      end
      Result.new(scope: scope, lang: lang, run_id: run_id, anchor_count: anchors.size,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 min_score: min_score, per_anchor: per_anchor,
                 elapsed: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    private

    # Every visible passage urn in the slice, urn-ordered for determinism.
    # +lang+ scopes the ANCHORS (a translation-bearing source rides the same
    # urn prefix as its base text — the formulas lesson) and is passed through
    # to the engine's candidate filter too.
    def anchor_urns(scope, lang:)
      scoped_passages(scope, lang: lang)
        .order(Sequel[:passages][:urn])
        .select_map(Sequel[:passages][:urn])
    end

    def record_run(scope, min_score:, per_anchor:, lang:, license:)
      params = { kind: KIND, min_score: min_score, per_anchor: per_anchor,
                 lang: lang, license: license }.compact
      Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: scope,
                                                params: params, code_version: CODE_VERSION)
    end

    def mine(anchors, run_id:, min_score:, per_anchor:, lang:, license:, counts:, progress:)
      engine = Query::Parallels.new(catalog: @catalog, fulltext: @fulltext)
      seen = Set.new
      anchors.each_with_index do |urn, index|
        result = engine.run(urn, limit: per_anchor, lang: lang, license: license, echoes: false)
        result&.hits&.each do |hit|
          next if hit.score < min_score
          next unless seen.add?([urn, hit.urn].minmax)

          outcome = Store::LinksJournal.write_edge!(@journal, from_urn: urn, to_urn: hit.urn,
                                                              kind: KIND, score: hit.score, run_id: run_id)
          counts[outcome == :inserted ? :inserted : :refreshed] += 1
        end
        progress&.call(index + 1, anchors.size, counts[:inserted] + counts[:refreshed])
      end
    end
  end
end
