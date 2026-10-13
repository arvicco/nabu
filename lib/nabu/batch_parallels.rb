# frozen_string_literal: true

require "json"
require_relative "query/catalog_join"
require_relative "query/scope"
require_relative "query/parallels"
require_relative "duration_format"

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
  # of A is kept as found — LinksJournal.write_edge! first_in_run). Across
  # runs the journal enforces the same pair-per-kind invariant by refreshing
  # an existing edge in place. A rerun of a FINISHED (producer, scope)
  # SUPERSEDES the prior run — its edges, chunk rows and run row are
  # replaced — so reruns are idempotent and the journal always holds the
  # current mining of a scope.
  #
  # == Profiles, chunks, resume (P122-2)
  #
  # The knobs resolve argument > profile (config/reuse_profiles.yml) >
  # engine default (Settings.resolve), and the run row records the profile
  # name plus EVERY effective parameter — engine defaults included,
  # resolved — so an edge is honest about the tuning that minted it.
  #
  # Without +chunk_size+ a run is one transaction (supersede + mine + run
  # row atomic, the P16-1 contract; a kill leaves nothing behind). With it,
  # the scope's anchors are mined in urn-ordered chunks keyset-paged from
  # the catalog (never the whole anchor list in memory); each chunk's edges,
  # its link_run_chunks row and the run's cursor commit together, so a
  # killed run loses at most the chunk in flight. Rerunning the same scope
  # under the same effective params and code version RESUMES an unfinished
  # run at its cursor — finished chunks are never re-mined — and, because
  # the first-found rule rides the journal rather than process memory,
  # resume yields exactly the uninterrupted run's edges. Different params
  # are refused unless +restart+ (which supersedes the unfinished run).
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
    # the code that minted them. /2 (P122-2): Han grams probe the CJK lane,
    # and the gram size became a recorded run parameter (it left the marker).
    CODE_VERSION = "parallels-batch/2 nabu/#{VERSION}".freeze

    # The EFFECTIVE parameters of one run. #params is the provenance hash
    # (link_runs.params_json): nil knobs drop, an empty stop list drops.
    Settings = Data.define(:profile, :lang, :license, :min_score, :per_anchor, :gram_size,
                           :candidate_pool, :stop_tokens, :chunk_size) do
      # Explicit argument > profile > engine default, knob by knob.
      def self.resolve(profile: nil, lang: nil, license: nil, min_score: nil, per_anchor: nil,
                       gram_size: nil, candidate_pool: nil, chunk_size: nil)
        per = per_anchor || profile&.per_anchor || DEFAULT_PER_ANCHOR
        new(profile: profile&.name, lang: lang || profile&.lang, license: license,
            min_score: min_score || profile&.min_score || DEFAULT_MIN_SCORE, per_anchor: per,
            gram_size: gram_size || profile&.gram_size || Query::Parallels::GRAM_SIZE,
            candidate_pool: candidate_pool || profile&.candidate_pool || Query::Parallels.candidate_cap(per),
            stop_tokens: profile&.stop_tokens || [], chunk_size: chunk_size)
      end

      def params
        { kind: KIND, profile: profile, min_score: min_score, per_anchor: per_anchor, lang: lang,
          license: license, gram_size: gram_size, candidate_pool: candidate_pool,
          stop_tokens: stop_tokens.empty? ? nil : stop_tokens, chunk_size: chunk_size }.compact
      end
    end

    # What a batch run did. +edges_written+ are new edges; +edges_refreshed+
    # existing pairs re-found (cross-run overlap) and updated in place;
    # +superseded_runs+/+superseded_edges+ what a rerun replaced. +elapsed+ in
    # seconds. +min_score+/+per_anchor+ ride along so the summary names its
    # thresholds. P122-2: +anchor_count+/+candidates+ count THIS invocation's
    # anchors and engine hits; +chunks+ is the run's chunk total and
    # +chunks_mined+ how many this invocation committed; +resumed+ says it
    # continued an unfinished run.
    Result = Data.define(:scope, :lang, :run_id, :anchor_count, :edges_written,
                         :edges_refreshed, :superseded_runs, :superseded_edges,
                         :min_score, :per_anchor, :elapsed, :profile, :gram_size,
                         :candidates, :chunks, :chunks_mined, :resumed)

    # One committed chunk, handed to +on_chunk+ AFTER its transaction
    # commits (chunk_line renders it). +seconds+ is the chunk's wall time,
    # +run_seconds+ this invocation's so far.
    ChunkReport = Data.define(:run_id, :chunk, :chunks, :first_urn, :last_urn, :anchors, :candidates,
                              :edges_inserted, :edges_refreshed, :seconds, :run_seconds)

    # The open run this invocation mines into.
    RunState = Data.define(:run_id, :cursor, :chunks_done, :superseded, :resumed)

    class << self
      include DurationFormat

      # The log-friendly per-chunk progress line: one line, fixed field
      # order, greppable while the run is live.
      def chunk_line(report)
        "chunk #{report.chunk}/#{report.chunks} · #{report.anchors} anchors · " \
          "#{report.candidates} candidates · #{report.edges_inserted} edges minted · " \
          "#{report.edges_refreshed} refreshed · #{format_duration(report.seconds)} · " \
          "run #{format_duration(report.run_seconds)}"
      end
    end

    def initialize(catalog:, fulltext:, journal:)
      @catalog = catalog
      @fulltext = fulltext
      @journal = journal
    end

    # Mine the slice named by +scope+; persist edges into the journal.
    # +profile+ is a ReuseProfiles::Profile (or nil); the other knobs
    # override it. +progress+ (nil-safe) is called with (anchors_done,
    # anchors_total, edges_so_far) after every anchor; +on_chunk+ with a
    # ChunkReport after every committed chunk — formatting stays with the
    # caller.
    def run(scope, profile: nil, lang: nil, license: nil, min_score: nil, per_anchor: nil, gram_size: nil,
            candidate_pool: nil, chunk_size: nil, restart: false, progress: nil, on_chunk: nil)
      started = clock
      settings = Settings.resolve(profile: profile, lang: lang, license: license, min_score: min_score,
                                  per_anchor: per_anchor, gram_size: gram_size,
                                  candidate_pool: candidate_pool, chunk_size: chunk_size)
      state = tally = nil
      atomically(chunked: !chunk_size.nil?) do
        state = @journal.transaction { open_run(scope, settings, restart: restart) }
        tally = mine(scope, settings, state, started: started, progress: progress, on_chunk: on_chunk)
        Store::LinksJournal.finish_run!(@journal, state.run_id)
      end
      result(scope, settings, state, tally, started)
    end

    private

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Unchunked: ONE transaction around the whole run (the inner chunk
    # transactions join it). Chunked: each chunk commits on its own.
    def atomically(chunked:, &)
      chunked ? yield : @journal.transaction(&)
    end

    def result(scope, settings, state, tally, started)
      Result.new(scope: scope, lang: settings.lang, run_id: state.run_id, anchor_count: tally[:anchors],
                 edges_written: tally[:inserted], edges_refreshed: tally[:refreshed],
                 superseded_runs: state.superseded[0], superseded_edges: state.superseded[1],
                 min_score: settings.min_score, per_anchor: settings.per_anchor, elapsed: clock - started,
                 profile: settings.profile, gram_size: settings.gram_size, candidates: tally[:candidates],
                 chunks: tally[:chunks], chunks_mined: tally[:chunks_mined], resumed: state.resumed)
    end

    # Resume the unfinished run of this scope when its effective params and
    # code version match; refuse a mismatch unless +restart+; otherwise
    # supersede and record a fresh running row.
    def open_run(scope, settings, restart:)
      prior = Store::LinksJournal.unfinished_run(@journal, producer: PRODUCER, scope: scope)
      if prior && !restart
        return resumed_state(prior) if resumable?(prior, settings)

        raise Nabu::Error, "parallels --batch #{scope}: run #{prior[:id]} is unfinished " \
                           "(#{prior[:chunks_done]} chunk(s) committed) under different parameters or code — " \
                           "rerun with the same profile and flags to resume it, or pass --restart to supersede it"
      end
      superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: scope)
      run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: scope, params: settings.params,
                                                         code_version: CODE_VERSION, status: "running",
                                                         chunk_size: settings.chunk_size)
      RunState.new(run_id: run_id, cursor: nil, chunks_done: 0, superseded: superseded, resumed: false)
    end

    def resumable?(prior, settings)
      prior[:code_version] == CODE_VERSION &&
        JSON.parse(prior[:params_json]) == JSON.parse(JSON.generate(settings.params))
    end

    def resumed_state(prior)
      RunState.new(run_id: prior[:id], cursor: prior[:cursor_urn], chunks_done: prior[:chunks_done],
                   superseded: [0, 0], resumed: true)
    end

    # Every visible passage of the slice past +cursor+. +lang+ scopes the
    # ANCHORS (a translation-bearing source rides the same urn prefix as its
    # base text — the formulas lesson) and is passed through to the engine's
    # candidate filter too.
    def anchors_after(scope, lang:, cursor:)
      dataset = scoped_passages(scope, lang: lang)
      cursor ? dataset.where(Sequel[:passages][:urn] > cursor) : dataset
    end

    # The next chunk, urn-ordered for determinism and keyset-paged (urn >
    # cursor, LIMIT chunk_size) so a huge scope never materializes its whole
    # anchor list. Unchunked: every remaining anchor.
    def next_chunk(scope, settings, cursor)
      dataset = anchors_after(scope, lang: settings.lang, cursor: cursor).order(Sequel[:passages][:urn])
      dataset = dataset.limit(settings.chunk_size) if settings.chunk_size
      dataset.select_map(Sequel[:passages][:urn])
    end

    def mine(scope, settings, state, started:, progress:, on_chunk:)
      remaining = anchors_after(scope, lang: settings.lang, cursor: state.cursor).count
      planned = settings.chunk_size ? remaining.fdiv(settings.chunk_size).ceil : [remaining, 1].min
      tally = { anchors: 0, inserted: 0, refreshed: 0, candidates: 0, chunks: state.chunks_done + planned,
                chunks_mined: 0, remaining: remaining, started: started }
      engine = Query::Parallels.new(catalog: @catalog, fulltext: @fulltext)
      cursor = state.cursor
      loop do
        urns = next_chunk(scope, settings, cursor)
        break if urns.empty?

        chunk = state.chunks_done + tally[:chunks_mined] + 1
        report = @journal.transaction do
          mine_chunk(engine, urns, settings, run_id: state.run_id, chunk: chunk, tally: tally, progress: progress)
        end
        tally[:chunks_mined] += 1
        on_chunk&.call(report)
        cursor = urns.last
      end
      tally
    end

    def mine_chunk(engine, urns, settings, run_id:, chunk:, tally:, progress:)
      chunk_started = clock
      counts = { inserted: 0, refreshed: 0, kept: 0, candidates: 0 }
      urns.each do |urn|
        mine_anchor(engine, urn, settings, run_id: run_id, chunk: chunk, counts: counts)
        tally[:anchors] += 1
        progress&.call(tally[:anchors], tally[:remaining],
                       tally[:inserted] + tally[:refreshed] + counts[:inserted] + counts[:refreshed])
      end
      seconds = clock - chunk_started
      Store::LinksJournal.record_chunk!(@journal, run_id: run_id, chunk: chunk, first_urn: urns.first,
                                                  last_urn: urns.last, anchors: urns.size,
                                                  candidates: counts[:candidates], edges_inserted: counts[:inserted],
                                                  edges_refreshed: counts[:refreshed], seconds: seconds)
      %i[inserted refreshed candidates].each { |key| tally[key] += counts[key] }
      ChunkReport.new(run_id: run_id, chunk: chunk, chunks: tally[:chunks], first_urn: urns.first,
                      last_urn: urns.last, anchors: urns.size, candidates: counts[:candidates],
                      edges_inserted: counts[:inserted], edges_refreshed: counts[:refreshed],
                      seconds: seconds, run_seconds: clock - tally[:started])
    end

    def mine_anchor(engine, urn, settings, run_id:, chunk:, counts:)
      result = engine.run(urn, limit: settings.per_anchor, lang: settings.lang, license: settings.license,
                               echoes: false, gram_size: settings.gram_size, stop_tokens: settings.stop_tokens,
                               candidate_pool: settings.candidate_pool)
      hits = result&.hits || []
      counts[:candidates] += hits.size
      hits.each do |hit|
        next if hit.score < settings.min_score

        outcome = Store::LinksJournal.write_edge!(@journal, from_urn: urn, to_urn: hit.urn, kind: KIND,
                                                            score: hit.score, run_id: run_id, chunk: chunk,
                                                            first_in_run: true)
        counts[outcome] += 1
      end
    end
  end
end
