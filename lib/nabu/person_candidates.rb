# frozen_string_literal: true

require_relative "name_words"
require_relative "source_passage_walk"
require_relative "store/links_journal_bulk"

module Nabu
  # The person-name CANDIDATE producer for the links journal: a
  # mechanical recipe over a source's OWN case-preserving passage text —
  # no external list, no person authority. A word qualifies when it
  # occurs at least MIN_OCCURRENCES times in the source and at least
  # MIN_CAPITALIZED_SHARE of those occurrences are capitalized (the
  # editions capitalize proper names; Latin and Greek epigraphy is where
  # the recipe was verified). Each passage holding a qualifying word
  # CAPITALIZED gets one kind=person-name-candidate edge to the word's
  # own claim urn, urn:nabu:person-candidate:<folded form>.
  #
  # == Candidates are not persons
  #
  # A candidate is a NAME FORM (inflected as written: "Optatae" and
  # "Optatus" are two forms), never a person record: it lives in its own
  # edge kind and urn namespace, never in the person index, and its edge
  # detail says so. Divine names, epithets and formula words
  # ("Dis Manibus") pass the recipe too — candidates are review fuel.
  # The person-index mine (Nabu::PersonMine) stays census-only; nothing
  # here reads or writes an authority.
  #
  # == Exclusions (all censused per distinct form, none silent)
  #
  # - short: under MIN_LETTERS letters (praenomen sigla "C", "M");
  # - digits: a word carrying a digit (no name);
  # - numeral: an all-capitals Roman numeral ("LXX") — always
  #   capitalized, never a name;
  # - caseless: a script without case (Hebrew, Han) carries no signal;
  # - rare: under MIN_OCCURRENCES; lowercase: under the share.
  #
  # == Shape
  #
  # One scan (Nabu::SourcePassageWalk, the windowed rowid walk): pass 1 tallies every
  # form's occurrences and capitalized occurrences and retains, per
  # passage, the forms it holds capitalized (integer ids, no text); the
  # write derives the qualifying set and emits edges from the retained
  # lists, re-reading only urns. Producer discipline: scope = the source
  # slug, reruns supersede, one edge per (passage, form).
  class PersonCandidates
    PRODUCER = "person-candidates"
    KIND = "person-name-candidate"
    TO_PREFIX = "urn:nabu:person-candidate:"
    CODE_VERSION = "person-candidates/1 nabu/#{VERSION}".freeze

    PAGE = 1_000
    WINDOW = SourcePassageWalk::WINDOW
    WRITE_BATCH = 2_000

    # const: the recipe (mechanical, verified on Latin/Greek epigraphy) —
    # not tuned per source.
    MIN_OCCURRENCES = 3
    MIN_CAPITALIZED_SHARE = 0.9
    MIN_LETTERS = 2

    CAPITALIZED = /\A[\p{Lu}\p{Lt}]/
    # A well-formed capital Roman numeral — the grammar, widened to the
    # inscriptional additive fours (IIII, XXXX, CCCC: EDH's 2,510
    # "IIII"), so DIVI or MILL — words spelled in numeral letters — stay
    # words.
    ROMAN_NUMERAL = /\A(?=[IVXLCDM])M{0,4}(?:CM|CD|D?C{0,4})(?:XC|XL|L?X{0,4})(?:IX|IV|V?I{0,4})\z/
    DIGIT = /\p{N}/

    Candidate = Data.define(:key, :surface, :occurrences, :capitalized, :capitalized_share)
    Census = Data.define(:source, :passages, :words, :forms, :candidates, :excluded, :candidate_edges, :seconds)
    Result = Data.define(:census, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :seconds)

    def initialize(catalog:, journal: nil, progress: nil, window: WINDOW)
      @catalog = catalog
      @journal = journal
      @progress = progress
      @window = window
    end

    # The recipe's yield for +source+ — every qualifying form with its
    # counts, every exclusion class counted. Writes nothing.
    def census(source:)
      scan_source(source).first
    end

    # The census, then one edge per (passage, qualifying form held
    # capitalized there), under the producer discipline.
    def apply!(source:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      report, retained = scan_source(source)
      by_id = report.candidates.to_h { |candidate| [@ids.fetch(candidate.key), candidate] }
      @progress&.stage("person-candidates: writing #{report.candidate_edges} candidate edges for #{source} " \
                       "(#{report.candidates.size} name forms)")
      counts = { inserted: 0, refreshed: 0 }
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: source)
        run_id = Store::LinksJournal.record_run!(
          @journal, producer: PRODUCER, scope: source, code_version: CODE_VERSION,
                    params: { kind: KIND, min_occurrences: MIN_OCCURRENCES,
                              min_capitalized_share: MIN_CAPITALIZED_SHARE, min_letters: MIN_LETTERS }
        )
        write_pass(retained, by_id, source, run_id, counts)
      end
      Result.new(census: report, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    private

    # → [Census, [[passage id, [form ids held capitalized]], …]].
    def scan_source(source)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @progress&.stage("person-candidates: scanning #{source}'s passage text " \
                       "(census — the recipe: ≥#{MIN_OCCURRENCES} occurrences, " \
                       "≥#{(MIN_CAPITALIZED_SHARE * 100).round}% capitalized)")
      @ids = {}
      totals = []
      capitals = []
      surfaces = []
      excluded = Hash.new { |hash, key| hash[key] = Set.new }
      retained = []
      passages = 0
      words = 0
      SourcePassageWalk.each(@catalog, source, window: @window) do |row|
        passages += 1
        held = nil
        NameWords.surface(row[:text]).each do |word|
          words += 1
          next unless (key = eligible(word, excluded))

          id = (@ids[key] ||= @ids.size)
          totals[id] = (totals[id] || 0) + 1
          next unless CAPITALIZED.match?(word)

          capitals[id] = (capitals[id] || 0) + 1
          (surfaces[id] ||= Hash.new(0))[word] += 1
          (held ||= []) << id unless held&.include?(id)
        end
        retained << [row[:id], held] if held
        @progress&.load_tick(passages, 0) if (passages % PAGE).zero?
      end
      candidates = qualify(totals, capitals, surfaces, excluded)
      qualified = candidates.to_set { |candidate| @ids.fetch(candidate.key) }
      edges = retained.sum { |_id, held| held.count { |id| qualified.include?(id) } }
      census = Census.new(source: source, passages: passages, words: words, forms: @ids.size,
                          candidates: candidates, excluded: excluded.transform_values(&:size),
                          candidate_edges: edges,
                          seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      [census, retained]
    end

    # The folded form of +word+, or nil (its exclusion class recorded).
    def eligible(word, excluded)
      key = NameWords.fold(word)
      reason = if word.scan(/\p{L}/).size < MIN_LETTERS then :short
               elsif DIGIT.match?(word) then :digits
               elsif ROMAN_NUMERAL.match?(word) then :numeral
               elsif word.downcase == word.upcase then :caseless
               end
      return key unless reason

      excluded[reason] << key
      nil
    end

    # The recipe applied; candidates ranked by occurrences, then form.
    def qualify(totals, capitals, surfaces, excluded)
      candidates = @ids.filter_map do |key, id|
        total = totals[id]
        cap = capitals[id] || 0
        if total < MIN_OCCURRENCES
          excluded[:rare] << key
          next
        end
        share = cap.fdiv(total)
        if share < MIN_CAPITALIZED_SHARE
          excluded[:lowercase] << key
          next
        end
        surface = surfaces[id].max_by { |form, count| [count, form] }.first
        Candidate.new(key: key, surface: surface, occurrences: total, capitalized: cap,
                      capitalized_share: share)
      end
      candidates.sort_by { |candidate| [-candidate.occurrences, candidate.key] }
    end

    def write_pass(retained, by_id, source, run_id, counts)
      written = 0
      retained.each_slice(WRITE_BATCH) do |slice|
        urns = @catalog[:passages].where(id: slice.map(&:first)).select_hash(:id, :urn)
        edges = []
        slice.each do |passage_id, held|
          next unless (urn = urns[passage_id])

          held.each do |id|
            next unless (candidate = by_id[id])

            edges << [urn, "#{TO_PREFIX}#{candidate.key}", nil, detail(candidate, source)]
          end
        end
        Store::LinksJournal.write_edges!(@journal, edges, kind: KIND, run_id: run_id)
                           .each { |outcome, n| counts[outcome] += n }
        @progress&.load_tick(written, 0) if (written / PAGE) < ((written += edges.size) / PAGE)
      end
    end

    def detail(candidate, source)
      "name candidate «#{candidate.surface}» — #{candidate.capitalized}/#{candidate.occurrences} " \
        "occurrences capitalized in #{source} (not a person record)"
    end
  end
end
