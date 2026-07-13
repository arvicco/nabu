# frozen_string_literal: true

require_relative "query/cognates"

module Nabu
  # Producer #3 for the links journal (P16-2; architecture §15): the
  # whole-work cognate map — the interactive Query::Cognates join (P15-3) run
  # over a registered alignment WORK, its (verse, root) groups persisted as
  # kind=cognate edges between the aligned witness PASSAGES that meet at a
  # reconstruction root. The scope is the work id ("nt") — the natural rerun/
  # supersede unit — not the slug/prefix grammar (an alignment work IS the
  # cognate engine's universe).
  #
  # == Edge shape
  #
  # One edge per unordered cross-language passage pair per verse-root meet
  # cluster: at a verse where got 𐌲𐌿𐌸 and chu богъ reach the same root, the
  # Gothic and OCS passage urns are linked. Witnesses per verse are few
  # (one passage per witness document), so pairwise is bounded and each edge
  # is a genuine binary assertion — never within one language (two codices of
  # one language sharing a word is transmission, not comparison; the engine
  # already enforces ≥2 distinct languages). Direction carries no discovery
  # semantics here (the join finds both ends at once), so it is normalized:
  # from_urn = the lexicographically smaller urn, deterministic across reruns.
  #
  # == The meet-provenance verdict (argued)
  #
  # The meet — WHICH root, on WHICH shelf, at WHICH verse — is the edge's
  # meaning, and it differs per edge: params_json is run-grain (one row for
  # the whole work — storing meets there loses them), and score is a float.
  # So the meet rides the journal's `detail` column (nullable, added by the
  # journal's own forward-only migration 002 — see db/links_migrate):
  # "MARK 2.1 · *kaisaraz [gem-pro]". The SHELF is deliberately in every
  # edge (design §6: a gem-pro meet for a Slavic witness reads as a
  # borrowing, not common descent; ine-pro meets are the inheritance
  # signal). A pair meeting at SEVERAL roots (or refs — a sentence can span
  # verses) keeps ONE edge whose detail lists every meet and whose score is
  # the distinct-root count.
  #
  # == What the engine's honesty rules mean for the journal
  #
  # Common-word suppression stays ON by default (an edge is an assertion;
  # ὁ-grade noise would flood every verse) — +all+ lifts it, and the flag is
  # recorded in params_json so the run is honest about what it kept. The
  # suppressed-group count rides the Result into the summary — pruning
  # named, never silent.
  class BatchCognates
    PRODUCER = "cognates"
    KIND = "cognate"
    # Bump when the join/crosswalk machinery changes meaning.
    CODE_VERSION = "cognates-batch/1 nabu/#{VERSION}".freeze

    # What a batch run did. +group_count+ = (verse, root) groups that
    # produced edges' raw material; +suppressed+ = groups the common-word
    # rule dropped (the engine's count, surfaced so the summary names it).
    Result = Data.define(:work, :langs, :run_id, :group_count, :suppressed,
                         :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :elapsed)

    def initialize(catalog:, fulltext:, registry:, journal:)
      @catalog = catalog
      @fulltext = fulltext
      @registry = registry
      @journal = journal
    end

    # Map the whole work named by +work_id+. Raises Query::Cognates::Error
    # for an unknown work / missing index (caller-fixable, the engine's own
    # contract).
    def run(work_id, langs: nil, all: false)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      work = @registry.work(work_id) or
        raise Query::Cognates::Error,
              "cognates --batch takes a registered work id " \
              "(#{@registry.works.map(&:id).join(', ')}) — per-ref runs are interactive"
      mined = Query::Cognates.new(catalog: @catalog, fulltext: @fulltext, registry: @registry)
                             .run(work.id, langs: langs, all: all, long: true)
      pairs = pair_meets(mined.groups)
      counts = { inserted: 0, refreshed: 0 }
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: work.id)
        run_id = record_run(work.id, langs: langs, all: all)
        write_pairs(pairs, run_id: run_id, counts: counts)
      end
      Result.new(work: work.id, langs: langs, run_id: run_id,
                 group_count: mined.groups.size, suppressed: mined.suppressed,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 elapsed: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    private

    def record_run(scope, langs:, all:)
      params = { kind: KIND, langs: langs, all: (true if all) }.compact
      Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: scope,
                                                params: params, code_version: CODE_VERSION)
    end

    # { [urn_lo, urn_hi] => { refs: Set, meets: Set } }: every cross-language
    # passage pair of every group, meets accumulated so a pair sharing
    # several roots (or spanning refs) collapses into one edge honestly.
    # P17-3: the meet string appends the crosswalk's per-edge loan verdict —
    # "*hlaibaz [gem-pro] (loan: chu)" names the witness languages whose
    # descent from the root is FLAGGED borrowed (the edge-grain fact the
    # shelf heuristic could only guess); unflagged/NULL stay unmarked.
    def pair_meets(groups)
      pairs = Hash.new { |hash, key| hash[key] = { refs: Set.new, meets: Set.new } }
      groups.each do |group|
        # Root.headword already carries the reconstruction asterisk.
        meet = "#{group.root.headword} [#{group.root.shelf}]#{loan_marker(group)}"
        by_language = group.witnesses.group_by(&:language)
                           .transform_values { |words| words.flat_map(&:passage_urns).uniq }
        by_language.keys.sort.combination(2) do |lang_a, lang_b|
          by_language.fetch(lang_a).product(by_language.fetch(lang_b)) do |one, other|
            slot = pairs[[one, other].minmax]
            slot[:refs] << group.ref
            slot[:meets] << meet
          end
        end
      end
      pairs
    end

    def loan_marker(group)
      flagged = group.witnesses.select(&:borrowed).map(&:language).uniq.sort
      flagged.empty? ? "" : " (loan: #{flagged.join(',')})"
    end

    def write_pairs(pairs, run_id:, counts:)
      pairs.each do |(from_urn, to_urn), slot|
        detail = "#{slot[:refs].sort.join(', ')} · #{slot[:meets].sort.join(', ')}"
        outcome = Store::LinksJournal.write_edge!(
          @journal, from_urn: from_urn, to_urn: to_urn, kind: KIND,
                    score: slot[:meets].size.to_f, detail: detail, run_id: run_id
        )
        counts[outcome == :inserted ? :inserted : :refreshed] += 1
      end
    end
  end
end
