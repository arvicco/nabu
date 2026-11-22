# frozen_string_literal: true

require "digest"
require "json"
require_relative "batch_parallels"
require_relative "reuse_census"
require_relative "reuse_pool"
require_relative "query/parallels_postings"
require_relative "store/reuse_postings"
require_relative "store/links_journal_first_found"

module Nabu
  # The parallels batch producer on the POSTINGS engine (the reuse-batch
  # redesign; architecture §15) — opt-in (`parallels --batch SCOPE
  # --engine postings`), the FTS-probe BatchParallels staying the default.
  #
  # == Why
  #
  # BatchParallels loops the interactive engine: every anchor probes each
  # of its grams as its own FTS phrase query — O(anchors × grams)
  # round-trips, measured at ~7 weeks for the kanripo + cbeta legs (the
  # run was killed at chunk 4/915). A spike profiled it (FTS probes = 92% of
  # engine time) and proved the flip: one census builds the scope's
  # gram-postings (Nabu::ReuseCensus → Store::ReusePostings), and scoring
  # reads them — ≈14 ms/anchor in memory, the kanripo leg ≈4 h, with EXACT
  # parity on a 1,000-anchor slice (9,739/9,739 edges, no score diff
  # >1e-4).
  #
  # == The shape
  #
  # - The anchors and chunks are the base class's: the same scope grammar,
  #   the same urn-ordered keyset chunks and cursor, the same open_run /
  #   resume / supersede machinery, the same ChunkReport.
  # - Each chunk is cut into SLICE-anchor tasks for a fork pool
  #   (Nabu::ReusePool). A worker holds a read-only postings Reader and the
  #   engine subclass (Query::ParallelsPostings): it prefetches the slice's
  #   keys in a few lookups and returns each anchor's candidate POOL —
  #   ids, scores, matched gram positions — scored by the inherited
  #   Query::Parallels code.
  # - ONE committer (this process) receives slices in task order, resolves
  #   each slice's pool candidates against the catalog in one CatalogJoin
  #   query per 5,000 ids (the visibility + passage→document map, sized to
  #   the slice so memory stays flat at any chunk size), assembles each
  #   anchor's document-grain hits with the inherited assemble, and at the
  #   chunk's last slice writes its edges, its chunk row and the cursor in ONE journal
  #   transaction through the bulk first-found writer
  #   (LinksJournal.write_edges_first_found! — write_edge!'s first_in_run
  #   rule, deterministic on the sorted pair). Resume and supersede are
  #   therefore exactly the base contract.
  #
  # == Provenance
  #
  # The run row records every effective parameter (the base Settings) plus
  # +engine+ "postings" and +postings+ — the store build it scored from
  # (name and stamp digest), so resume refuses a rebuilt store — and its own
  # code marker (CODE_VERSION). Workers are an execution detail and are not
  # recorded (they cannot change an edge).
  #
  # == Refusals
  #
  # No store for (scope, lang, gram size) → refuse, naming the build
  # command; a stale store (Nabu::ReuseCensus#staleness — any moved input)
  # → refuse with the reasons. A postings run never silently falls back to
  # the FTS engine: that is the 7-week path.
  class BatchParallelsPostings < BatchParallels
    ENGINE = "postings"
    CODE_VERSION = "parallels-batch/2+postings/1 nabu/#{VERSION}".freeze
    # Anchors per worker task (the pool grain; the commit grain stays the
    # run's chunk). Bounds a worker's prefetched postings and the
    # committer's resolved candidate map (≤ SLICE × candidate_pool rows) at
    # any chunk size.
    SLICE = 200

    # The base Settings plus the store build scored from.
    EngineSettings = Data.define(*BatchParallels::Settings.members, :postings) do
      def params
        BatchParallels::Settings.new(**to_h.except(:postings)).params.merge(engine: ENGINE, postings: postings)
      end
    end

    # +slice+ is the worker task grain (SLICE; tests shrink it to cut a
    # chunk into many tasks).
    def initialize(catalog:, fulltext:, journal:, root:, workers: 1, slice: SLICE)
      super(catalog: catalog, fulltext: fulltext, journal: journal)
      @root = root
      @workers = workers
      @slice = slice
    end

    def run(scope, profile: nil, lang: nil, license: nil, min_score: nil, per_anchor: nil, gram_size: nil,
            candidate_pool: nil, chunk_size: nil, restart: false, progress: nil, on_chunk: nil)
      started = clock
      base = Settings.resolve(profile: profile, lang: lang, license: license, min_score: min_score,
                              per_anchor: per_anchor, gram_size: gram_size, candidate_pool: candidate_pool,
                              chunk_size: chunk_size)
      @manifest = current_store!(scope, base)
      settings = EngineSettings.new(**base.to_h, postings: store_identity(@manifest))
      state = tally = nil
      atomically(chunked: !chunk_size.nil?) do
        state = @journal.transaction { open_run(scope, settings, restart: restart) }
        tally = mine(scope, settings, state, started: started, progress: progress, on_chunk: on_chunk)
        Store::LinksJournal.finish_run!(@journal, state.run_id)
      end
      result(scope, settings, state, tally, started)
    end

    private

    # The base mints (or resumes) the run row; a fresh row is re-stamped
    # with THIS engine's code marker in the same transaction.
    def open_run(scope, settings, restart:)
      state = super
      @journal[:link_runs].where(id: state.run_id).update(code_version: CODE_VERSION) unless state.resumed
      state
    end

    def resumable?(prior, settings)
      prior[:code_version] == CODE_VERSION &&
        JSON.parse(prior[:params_json]) == JSON.parse(JSON.generate(settings.params))
    end

    # The stamped store this run scores from: the (scope, lang, gram size)
    # build, else the scope's lang-agnostic one (a superset), checked
    # current.
    def current_store!(scope, settings)
      names = [Store::ReusePostings.build_name(scope: scope, lang: settings.lang, gram_size: settings.gram_size),
               Store::ReusePostings.build_name(scope: scope, gram_size: settings.gram_size)].uniq
      manifest = names.lazy.filter_map { |name| Store::ReusePostings.open(@root, name)&.manifest }
                           .find { |found| compatible?(found, scope, settings) }
      unless manifest
        raise Nabu::Error, "parallels --batch #{scope} --engine postings: no gram-postings store for this " \
                           "scope at gram size #{settings.gram_size}#{" [#{settings.lang}]" if settings.lang} — " \
                           "build it first: nabu reuse build #{scope} --gram-size #{settings.gram_size}" \
                           "#{" --lang #{settings.lang}" if settings.lang}"
      end
      reasons = ReuseCensus.new(catalog: @catalog, fulltext: @fulltext, root: @root).staleness(manifest)
      return manifest if reasons.empty?

      raise Nabu::Error, "parallels --batch #{scope} --engine postings: the gram-postings store " \
                         "#{manifest.name} is stale (#{reasons.join('; ')}) — rebuild it: nabu reuse build #{scope}"
    end

    def compatible?(manifest, scope, settings)
      stamp = manifest.provenance
      stamp["scope"] == scope && stamp["gram_size"] == settings.gram_size &&
        (stamp["lang"].nil? || stamp["lang"] == settings.lang)
    end

    def store_identity(manifest)
      "#{manifest.name}##{Digest::SHA256.hexdigest(JSON.generate(manifest.provenance))[0, 12]}"
    end

    # The base loop's shape over the pool: chunk → SLICE tasks → workers →
    # in-order slices → one committed transaction per chunk.
    def mine(scope, settings, state, started:, progress:, on_chunk:)
      remaining = anchors_after(scope, lang: settings.lang, cursor: state.cursor).count
      planned = settings.chunk_size ? remaining.fdiv(settings.chunk_size).ceil : [remaining, 1].min
      tally = { anchors: 0, inserted: 0, refreshed: 0, candidates: 0, chunks: state.chunks_done + planned,
                chunks_mined: 0, remaining: remaining, started: started }
      cutoff = Query::ParallelsPostings.cutoff(@catalog)
      lane = !@manifest.provenance["lane"].nil?
      committer = Query::ParallelsPostings.new(catalog: @catalog, cutoff: cutoff, lane: lane)
      chunk = nil
      scoring_pool(settings, cutoff: cutoff, lane: lane).map(tasks(scope, settings, state)) do |task, pools|
        chunk ||= { started: clock, edges: [], candidates: 0, anchors: 0 }
        collect_slice(committer, task, pools, settings, chunk: chunk, tally: tally, progress: progress)
        next unless task[:last]

        report = @journal.transaction { commit_chunk(task, chunk, run_id: state.run_id, tally: tally) }
        chunk = nil
        tally[:chunks_mined] += 1
        on_chunk&.call(report)
      end
      tally
    end

    def scoring_pool(settings, cutoff:, lane:)
      manifest = @manifest
      ReusePool.new(
        workers: @workers,
        setup: lambda { |_index|
          Query::ParallelsPostings.new(cutoff: cutoff, lane: lane, reader: Store::ReusePostings::Reader.new(manifest))
        },
        work: lambda { |engine, task|
          engine.prefetch!(task[:anchors], gram_size: settings.gram_size)
          pools = task[:anchors].map do |anchor|
            engine.pool_for(anchor, gram_size: settings.gram_size, stop_tokens: settings.stop_tokens,
                                    limit: settings.per_anchor, pool: settings.candidate_pool)
          end
          [task, pools]
        },
        finish: :close.to_proc
      )
    end

    # The run's tasks, lazily: each chunk (the base keyset grain) as SLICE
    # anchor tuples [urn, passage_id, document_id, text], the last slice
    # of a chunk flagged.
    def tasks(scope, settings, state)
      Enumerator.new do |yielder|
        cursor = state.cursor
        chunk = state.chunks_done
        loop do
          urns = next_chunk(scope, settings, cursor)
          break if urns.empty?

          chunk += 1
          slices = load_anchors(urns).each_slice(@slice).to_a
          slices.each_with_index do |anchors, i|
            yielder << { chunk: chunk, anchors: anchors, last: i == slices.size - 1, first_urn: urns.first,
                         last_urn: urns.last }
          end
          cursor = urns.last
        end
      end
    end

    # The anchor rows for +urns+, in urn order — Query::Parallels#load_anchor's
    # columns (catalog passage text_search; passage-level visibility).
    def load_anchors(urns)
      rows = urns.each_slice(Query::ParallelsPostings::RESOLVE_SLICE).flat_map do |slice|
        @catalog[:passages].where(urn: slice, withdrawn: false)
                           .select_map(%i[urn id document_id text_search])
      end
      by_urn = rows.to_h { |row| [row.first, row] }
      urns.filter_map { |urn| by_urn[urn] }
    end

    # One delivered slice: resolve its pool candidates (one CatalogJoin
    # query per RESOLVE_SLICE ids), assemble each anchor's hits, and queue
    # the edges clearing the floor — in anchor order, the first-found order
    # the commit preserves.
    def collect_slice(committer, task, pools, settings, chunk:, tally:, progress:)
      resolved = committer.resolve(pools.flat_map(&:first), lang: settings.lang, license: settings.license)
      task[:anchors].zip(pools).each do |anchor, pool_entry|
        hits = committer.hits(anchor, pool_entry, resolved: resolved, limit: settings.per_anchor,
                                                  gram_size: settings.gram_size, pool: settings.candidate_pool)
        chunk[:candidates] += hits.size
        hits.each { |hit| chunk[:edges] << [anchor[0], hit.urn, hit.score, nil] if hit.score >= settings.min_score }
        chunk[:anchors] += 1
        tally[:anchors] += 1
        progress&.call(tally[:anchors], tally[:remaining], tally[:inserted] + tally[:refreshed])
      end
    end

    # The chunk's edges, chunk row and cursor — one transaction (the
    # caller's), the base contract.
    def commit_chunk(task, chunk, run_id:, tally:)
      counts = Store::LinksJournal.write_edges_first_found!(@journal, chunk[:edges], kind: KIND, run_id: run_id,
                                                                                     chunk: task[:chunk])
      seconds = clock - chunk[:started]
      Store::LinksJournal.record_chunk!(@journal, run_id: run_id, chunk: task[:chunk], first_urn: task[:first_urn],
                                                  last_urn: task[:last_urn], anchors: chunk[:anchors],
                                                  candidates: chunk[:candidates], edges_inserted: counts[:inserted],
                                                  edges_refreshed: counts[:refreshed], seconds: seconds)
      tally[:inserted] += counts[:inserted]
      tally[:refreshed] += counts[:refreshed]
      tally[:candidates] += chunk[:candidates]
      ChunkReport.new(run_id: run_id, chunk: task[:chunk], chunks: tally[:chunks], first_urn: task[:first_urn],
                      last_urn: task[:last_urn], anchors: chunk[:anchors], candidates: chunk[:candidates],
                      edges_inserted: counts[:inserted], edges_refreshed: counts[:refreshed],
                      seconds: seconds, run_seconds: clock - tally[:started])
    end
  end
end
