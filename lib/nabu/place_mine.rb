# frozen_string_literal: true

module Nabu
  # Producer #9 for the links journal (P96-3 — Q9, text-mined places v0;
  # №R-15 decoupled it from ML in 2026-08): match the derived place
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
  #    excluded from apply, reported with its count so the owner can
  #    ruling-list real exceptions in config/place_stop_names.yml.
  # 4. The hand stop list (config/place_stop_names.yml) always applies.
  #
  # == Shape
  #
  # Two announced passes (the no-silent-passes rule): census (scan +
  # tally), then apply (rescan + write), each streaming passages in
  # keyset pages. Producer discipline: scope = "<source>:<gazetteer>",
  # reruns supersede, one edge per (passage, place) pair with the
  # matched name riding the detail.
  class PlaceMine
    PRODUCER = "place-mine"
    KIND = "place-candidate"
    TO_PREFIX = "urn:nabu:place:"
    CODE_VERSION = "place-mine/1 nabu/#{VERSION}".freeze

    PAGE = 1_000
    # const: precision floors/caps (class note) — census-reported, never silent
    MIN_NAME_CHARS = 2
    MAX_PLACES_PER_NAME = 3
    STOP_SHARE = 0.002

    HAN = /\p{Han}/

    STOP_NAMES_PATH = File.expand_path("../../config/place_stop_names.yml", __dir__)

    Census = Data.define(:source, :gazetteer, :passages, :name_hits, :candidate_edges,
                         :names_loaded, :names_non_han, :names_ambiguous, :names_stopped)
    Result = Data.define(:census, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges)

    def initialize(catalog:, journal:, gazetteer:, progress: nil, stop_names: nil)
      @catalog = catalog
      @journal = journal
      @gazetteer = gazetteer
      @progress = progress
      @stop_names = stop_names || self.class.hand_stop_names
    end

    def self.hand_stop_names
      return [] unless File.file?(STOP_NAMES_PATH)

      loaded = YAML.safe_load_file(STOP_NAMES_PATH)
      Array(loaded && loaded["stop_names"]).map(&:to_s)
    end

    # Pass 1 — the honest count: scan +source+'s live passages against
    # the gazetteer's Han name keys, tally hits per name, derive the
    # stop set. Writes nothing.
    def census(source:)
      names = load_names
      @progress&.stage("place-mine: scanning #{source} against #{names.size} #{@gazetteer} " \
                       "Han name keys (pass 1 — census, nothing written)")
      tally = Hash.new(0)
      passages = 0
      edges = 0
      each_passage(source) do |row|
        passages += 1
        hits = scan(row[:text], names)
        hits.each { |name| tally[name] += 1 }
        edges += hits.sum { |name| names.fetch(name).size }
        @progress&.load_tick(passages, 0) if (passages % PAGE).zero?
      end
      stopped = derive_stops(tally, passages)
      Census.new(
        source: source, gazetteer: @gazetteer, passages: passages,
        name_hits: tally.sort_by { |_n, c| -c },
        candidate_edges: edges,
        names_loaded: names.size, names_non_han: @non_han, names_ambiguous: @ambiguous,
        names_stopped: stopped
      )
    end

    # Pass 1 + pass 2: census, then write every surviving candidate edge
    # under the producer discipline.
    def apply!(source:)
      report = census(source: source)
      stopped = report.names_stopped.map(&:first) + @stop_names
      names = load_names.except(*stopped)
      @progress&.stage("place-mine: writing candidates for #{source} " \
                       "(pass 2 — #{names.size} names after stops)")
      counts = { inserted: 0, refreshed: 0 }
      run_id = superseded = nil
      scope = "#{source}:#{@gazetteer}"
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: scope)
        run_id = Store::LinksJournal.record_run!(
          @journal, producer: PRODUCER, scope: scope,
                    params: { kind: KIND, gazetteer: @gazetteer }, code_version: CODE_VERSION
        )
        write_pass(source, names, run_id, counts)
      end
      Result.new(census: report, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1])
    end

    private

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
      @buckets = build_buckets(@names)
      @names
    end

    # first character → [names, longest first] — the scan probes only
    # the bucket at each position, so the walk stays linear-ish over
    # 82k names.
    def build_buckets(names)
      names.keys.group_by { |name| name[0] }
                .transform_values { |list| list.sort_by { |n| -n.length } }
    end

    # The distinct name keys attested in +text+ (each counted once per
    # passage, overlaps allowed — attestations, not tokenization).
    def scan(text, _names)
      hits = nil
      i = 0
      len = text.length
      while i < len
        bucket = @buckets[text[i]]
        bucket&.each do |name|
          next unless text[i, name.length] == name

          (hits ||= {})[name] = true
        end
        i += 1
      end
      hits ? hits.keys : []
    end

    def derive_stops(tally, passages)
      ceiling = [(passages * STOP_SHARE).ceil, 20].max
      tally.select { |_name, count| count > ceiling }.sort_by { |_n, c| -c }
    end

    def each_passage(source, &block)
      cursor = 0
      base = @catalog[:passages]
             .join(:documents, id: Sequel[:passages][:document_id])
             .join(:sources, id: Sequel[:documents][:source_id])
             .where(Sequel[:passages][:withdrawn] => false,
                    Sequel[:documents][:withdrawn] => false,
                    Sequel[:sources][:slug] => source)
      loop do
        rows = base.where { Sequel[:passages][:id] > cursor }
                   .order(Sequel[:passages][:id])
                   .limit(PAGE)
                   .select(Sequel[:passages][:id].as(:pid), Sequel[:passages][:urn],
                           Sequel[:passages][:text])
                   .all
        break if rows.empty?

        cursor = rows.last[:pid]
        rows.each(&block)
      end
    end

    def write_pass(source, names, run_id, counts)
      written = 0
      each_passage(source) do |row|
        scan(row[:text], names).each do |name|
          names.fetch(name).each do |place_id|
            outcome = Store::LinksJournal.write_edge!(
              @journal, from_urn: row[:urn],
                        to_urn: "#{TO_PREFIX}#{@gazetteer}:#{place_id}", kind: KIND,
                        score: nil, run_id: run_id,
                        detail: "mined 「#{name}」 (#{@gazetteer})"
            )
            counts[outcome == :inserted ? :inserted : :refreshed] += 1
            written += 1
            @progress&.load_tick(written, 0) if (written % PAGE).zero?
          end
        end
      end
    end
  end
end
