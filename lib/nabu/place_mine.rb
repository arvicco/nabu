# frozen_string_literal: true

require_relative "name_matcher"
require_relative "places"
require_relative "store/links_journal_bulk"

module Nabu
  # Producer #9 for the links journal (P96-3, text-mined places v0;
  # an owner ruling decoupled it from ML in 2026-08): match the derived place
  # index's NAME KEYS against the PASSAGE TEXT of the metadata-less
  # corpora, emitting journaled CANDIDATE attestations — kind=
  # place-candidate edges from the passage urn to a stable place claim
  # (urn:nabu:place:<gazetteer>:<id>, the corph-eDIL forward-ref
  # argument: gazetteer id spaces are real target spaces). Candidates
  # are REVIEW FUEL for the np:/registry doctrine — they never touch
  # place_ref directly, and losing the journal costs one re-run.
  #
  # == v0 scope: the Han lane (the design honesty)
  #
  # Q9's stated hard part is precision, and precision is per-script.
  # v0 ships the HAN matcher — the chgis×kanripo flagship: gazetteer
  # names written in Han characters, matched as exact substrings of the
  # passage text (Chinese writes without word boundaries, so substring
  # IS the word-level operation; the CJK search lane's own logic).
  # Non-Han name keys are filtered out and censused honestly — the
  # Latin word-boundary lane is a recorded v1.1, not a silent absence.
  #
  # == Precision rules (all censused, none silent)
  #
  # 1. MIN_NAME_CHARS: single-character names never match (one hanzi is
  #    a word, not a toponym claim).
  # 2. AMBIGUITY CAP: a name key resolving to more than MAX_PLACES_PER_NAME
  #    distinct places is excluded (a candidate must name a place, not a
  #    class of homonyms); tallied in the census.
  # 3. THE DERIVED STOP RULE: pass 1 counts each name's passage hits;
  #    a name hitting more than STOP_SHARE of scanned passages is a
  #    common word wearing a place's clothes (州, 東… would flood) —
  #    excluded from apply, reported with its count. A genuinely
  #    geographic name lost to the ceiling gets an `allow_names:`
  #    ruling (owner-ruled 2026-09-18 — the 吐蕃/Tibet case): allow exempts
  #    the DERIVED stop only, is itself censused, and never overrides
  #    the floor, the cap, or the hand stop list.
  # 4. The hand stop list (config/place_stop_names.yml) always applies.
  # 5. THE REGISTRY'S RULINGS (owner ruling 2026-10-20): a name the
  #    nabu-places registry has ruled "region" or "rejected" for this
  #    source mints no candidate — the review board already decided it
  #    names no single locatable place. Ruled names are still SCANNED
  #    (so the derived stop ceiling and the census stay exactly what
  #    they were) and are censused with their hit counts; only their
  #    edges are withheld. The ruled names that hit ride the run row's
  #    params (ruled_out), the evidence health's registry-orphan probe
  #    reads once the edges are gone.
  #
  # == Shape
  #
  # One scan, two announced phases (the no-silent-passes rule): the census
  # scans every live passage once — an Aho-Corasick walk (NameMatcher) over
  # passage-id windows — tallying hits AND retaining each passage's hit
  # list (compact integer arrays: passage id + name indices, no text, no
  # urns); apply then derives the stops and writes the surviving names'
  # edges straight from the retained hits, re-reading only the urns of
  # the passages that hit, in bulk (LinksJournal.write_edges!). Output is
  # identical to the original census-then-rescan miner: the same edges,
  # details, insertion order and counts (pinned by
  # test/place_mine_test.rb's equivalence test). Producer discipline:
  # scope = "<source>:<gazetteer>", reruns supersede, one edge per
  # (passage, place) pair with the matched name riding the detail — when
  # two names of one place hit the same passage, the later name's detail
  # stands (the pair is refreshed, never duplicated).
  class PlaceMine
    PRODUCER = "place-mine"
    KIND = "place-candidate"
    TO_PREFIX = "urn:nabu:place:"
    CODE_VERSION = "place-mine/1 nabu/#{VERSION}".freeze

    # progress-tick cadence (passages scanned / edges written)
    PAGE = 1_000
    # passage-id span read per window: a rowid range scan, never a sort
    WINDOW = 5_000
    # retained hit passages turned into edges per bulk write
    WRITE_BATCH = 2_000
    # const: precision floors/caps (class note) — census-reported, never silent
    MIN_NAME_CHARS = 2
    MAX_PLACES_PER_NAME = 3
    STOP_SHARE = 0.002

    HAN = /\p{Han}/

    STOP_NAMES_PATH = File.expand_path("../../config/place_stop_names.yml", __dir__)

    # The registry statuses that withhold a name's candidates (rule 5).
    RULED_OUT_STATUSES = %w[region rejected].freeze

    # Both summary values carry their elapsed +seconds+ (owner rule
    # 2026-09-11: time elapsed is part of all summary reporting);
    # Result's covers both passes.
    Census = Data.define(:source, :gazetteer, :passages, :name_hits, :candidate_edges,
                         :names_loaded, :names_non_han, :names_ambiguous, :names_stopped,
                         :names_allowed, :names_ruled_out, :seconds)
    Result = Data.define(:census, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :seconds)

    # +ruled_out+ the registry's region/rejected names for the source
    # (rule 5; PlaceMine.ruled_out_names) — none by default.
    def initialize(catalog:, journal:, gazetteer:, progress: nil, stop_names: nil,
                   allow_names: nil, ruled_out: [], window: WINDOW)
      @catalog = catalog
      @journal = journal
      @gazetteer = gazetteer
      @progress = progress
      @stop_names = stop_names || self.class.hand_stop_names
      @allow_names = allow_names || self.class.hand_allow_names
      @ruled_out = ruled_out.map(&:to_s).uniq.sort
      @window = window
    end

    # The names +registry+ (Nabu::Places, a stub answering decisions_for,
    # or nil when the registry is not synced) rules region/rejected for
    # +source+, sorted — what rule 5 withholds.
    def self.ruled_out_names(registry, source)
      return [] if registry.nil?

      registry.decisions_for(source).filter_map do |name, decision|
        name if RULED_OUT_STATUSES.include?(decision.status)
      end.sort
    end

    def self.hand_stop_names
      Array(hand_rulings["stop_names"]).map(&:to_s)
    end

    # The ceiling exemptions (owner ruling 2026-09-18): ruled genuinely-geographic names
    # the derived stop must not swallow.
    def self.hand_allow_names
      Array(hand_rulings["allow_names"]).map(&:to_s)
    end

    def self.hand_rulings
      return {} unless File.file?(STOP_NAMES_PATH)

      YAML.safe_load_file(STOP_NAMES_PATH) || {}
    end

    # Pass 1 — the honest count: scan +source+'s live passages against
    # the gazetteer's Han name keys, tally hits per name, derive the
    # stop set. Writes nothing.
    def census(source:)
      scan_source(source, retain: false).first
    end

    # The census, then every surviving candidate edge written under the
    # producer discipline — from the census scan's retained hits, so the
    # passages are scanned once.
    def apply!(source:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      report, retained = scan_source(source, retain: true)
      stopped = report.names_stopped.map(&:first) + @stop_names
      names = load_names.except(*stopped, *@ruled_out)
      @progress&.stage("place-mine: writing candidates for #{source} " \
                       "(#{retained.size} passages with hits, #{names.size} names after stops)")
      counts = { inserted: 0, refreshed: 0 }
      run_id = superseded = nil
      scope = "#{source}:#{@gazetteer}"
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: scope)
        run_id = Store::LinksJournal.record_run!(
          @journal, producer: PRODUCER, scope: scope, params: run_params(report), code_version: CODE_VERSION
        )
        write_pass(retained, names, run_id, counts)
      end
      Result.new(census: report, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    # Each hitting passage's id and hit list (name indices in scan order),
    # kept as flat integer arrays — ~8 bytes per passage plus 8 per hit,
    # no strings — so a whole-source apply holds its hits in memory
    # without holding text or urns.
    class Retained
      def initialize
        @ids = []
        @hits = []
        @ends = []
      end

      def size = @ids.size

      def add(passage_id, name_indices)
        @ids << passage_id
        @hits.concat(name_indices)
        @ends << @hits.size
      end

      # Yields [passage ids, [hit index lists]] batches of +size+, in scan
      # (passage id) order.
      def each_batch(size)
        (0...@ids.size).each_slice(size) do |slots|
          lists = slots.map { |slot| @hits[(slot.zero? ? 0 : @ends[slot - 1])...@ends[slot]] }
          yield @ids.values_at(*slots), lists
        end
      end
    end

    private

    # The run row's params: the kind and gazetteer, plus — only when a
    # ruling withheld a name that hit — those names and their passage
    # hits (rule 5's evidence for the registry-orphan probe).
    def run_params(report)
      params = { kind: KIND, gazetteer: @gazetteer }
      params[:ruled_out] = report.names_ruled_out.to_h unless report.names_ruled_out.empty?
      params
    end

    # The one scan: tally every name's passage hits (the census), and —
    # when +retain+ — keep each hitting passage's hit list for the write.
    # → [Census, Retained or nil].
    def scan_source(source, retain:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      names = load_names
      @progress&.stage("place-mine: scanning #{source} against #{names.size} #{@gazetteer} " \
                       "Han name keys (census — nothing written)")
      tally = Hash.new(0)
      retained = Retained.new if retain
      passages = 0
      edges = 0
      each_passage(source) do |row|
        passages += 1
        hits = @matcher.scan(row[:text])
        unless hits.empty?
          hits.each { |name| tally[name] += 1 }
          edges += hits.sum { |name| names.fetch(name).size }
          retained&.add(row[:id], hits.map { |name| @name_index.fetch(name) })
        end
        @progress&.load_tick(passages, 0) if (passages % PAGE).zero?
      end
      stopped, allowed = derive_stops(tally, passages)
      census = Census.new(
        source: source, gazetteer: @gazetteer, passages: passages,
        name_hits: tally.sort_by { |_n, c| -c },
        candidate_edges: edges,
        names_loaded: names.size, names_non_han: @non_han, names_ambiguous: @ambiguous,
        names_stopped: stopped, names_allowed: allowed,
        names_ruled_out: tally.slice(*@ruled_out).sort_by { |name, c| [-c, name] },
        seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      )
      [census, retained]
    end

    # { name_key => [place ids] } for the gazetteer's Han-script names,
    # precision rules 1–2 + the hand stop list applied; exclusions
    # tallied for the census.
    def load_names
      return @names if @names

      rows = @catalog[:place_index_names]
             .where(gazetteer: @gazetteer)
             .select_hash_groups(:name_key, :place_id)
      @non_han = 0
      @ambiguous = 0
      @names = rows.filter_map do |name, ids|
        next unless name.length >= MIN_NAME_CHARS

        unless HAN.match?(name)
          @non_han += 1
          next
        end
        if ids.uniq.size > MAX_PLACES_PER_NAME
          @ambiguous += 1
          next
        end
        next if @stop_names.include?(name)

        [name, ids.uniq]
      end.to_h
      @name_list = @names.keys
      @name_index = @name_list.each_with_index.to_h
      @matcher = NameMatcher.new(@name_list)
      @names
    end

    # → [stopped, allowed]: names over the ceiling, minus the ruled
    # allow-list — the exemptions reported beside the stops, never
    # silently un-stopped.
    def derive_stops(tally, passages)
      ceiling = [(passages * STOP_SHARE).ceil, 20].max
      over = tally.select { |_name, count| count > ceiling }.sort_by { |_n, c| -c }
      over.partition { |name, _count| !@allow_names.include?(name) }
    end

    # The source's live passages in id order, read in id windows: a rowid
    # RANGE per window (no join, no ORDER BY sort — the keyset page with a
    # join sorted every remaining passage on each page), filtered to the
    # source's live documents in Ruby. Same rows, same order, as
    # passages ⋈ documents ⋈ sources WHERE live AND slug ORDER BY id.
    def each_passage(source)
      documents = @catalog[:documents]
                  .where(withdrawn: false, source_id: @catalog[:sources].where(slug: source).select(:id))
                  .select_map(:id)
      return if documents.empty?

      first, last = @catalog[:passages].where(document_id: documents).get { [min(id).as(:first), max(id).as(:last)] }
      return if first.nil?

      live = documents.to_set
      low = first
      while low <= last
        high = [low + @window - 1, last].min
        @catalog[:passages].where(id: low..high, withdrawn: false).order(:id)
                           .select(:id, :document_id, :text).all.each do |row|
          yield row if live.include?(row[:document_id])
        end
        low = high + 1
      end
    end

    # Pass-2 output from the retained hits: the surviving names only (the
    # derived and hand stops dropped — never looked up, the 2026-09-10
    # kanripo KeyError's lesson), each hit name's places in index order,
    # bulk-written per batch with write_edge!'s exact semantics.
    def write_pass(retained, names, run_id, counts)
      targets = @name_list.map do |name|
        next unless (places = names[name])

        [places.map { |place_id| "#{TO_PREFIX}#{@gazetteer}:#{place_id}" }, "mined 「#{name}」 (#{@gazetteer})"]
      end
      written = 0
      retained.each_batch(WRITE_BATCH) do |ids, lists|
        urns = @catalog[:passages].where(id: ids).select_hash(:id, :urn)
        edges = []
        ids.each_with_index do |id, slot|
          next unless (urn = urns[id])

          lists[slot].each do |index|
            next unless (to_urns, detail = targets[index])

            to_urns.each { |to_urn| edges << [urn, to_urn, nil, detail] }
          end
        end
        Store::LinksJournal.write_edges!(@journal, edges, kind: KIND, run_id: run_id)
                           .each { |outcome, n| counts[outcome] += n }
        @progress&.load_tick(written, 0) if (written / PAGE) < ((written += edges.size) / PAGE)
      end
    end
  end
end
