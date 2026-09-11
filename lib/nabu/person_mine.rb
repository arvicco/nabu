# frozen_string_literal: true

module Nabu
  # PersonMine (P97-2 — №R-62 option b): the CENSUS-ONLY person-name
  # scan — the PlaceMine Han-lane scan shape over the person index's
  # name keys, tallying attestations per name so the owner can read the
  # numbers before ANY apply gate opens. №R-62's own condition: this
  # class deliberately has no write path — personal names are far more
  # ambiguous than placenames (homonymy at 600k-key scale), and edges
  # only exist after a ruling on what the census shows.
  #
  # Precision floors (censused): the 2-char minimum (a bare surname is
  # not a person claim), the ambiguity cap (a name naming more than
  # MAX_PERSONS_PER_NAME distinct persons identifies nobody), and the
  # derived stop rule (share > STOP_SHARE of scanned passages = a
  # common word wearing a name's clothes).
  class PersonMine
    PAGE = 1_000
    MIN_NAME_CHARS = 2
    MAX_PERSONS_PER_NAME = 3
    STOP_SHARE = 0.002

    HAN = /\p{Han}/

    Census = Data.define(:source, :authority, :passages, :name_hits,
                         :names_loaded, :names_non_han, :names_ambiguous,
                         :names_stopped, :seconds)

    def initialize(catalog:, authority: Store::PersonIndex::DEFAULT_AUTHORITY, progress: nil)
      @catalog = catalog
      @authority = authority
      @progress = progress
    end

    # The honest count: scan +source+'s live passages against the
    # authority's Han name keys; tally per name; derive stops. Writes
    # nothing — by design, not by flag.
    def census(source:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      names = load_names
      @progress&.stage("person-mine: scanning #{source} against #{names.size} #{@authority} " \
                       "person name keys (census only — the apply gate is closed by №R-62)")
      tally = Hash.new(0)
      passages = 0
      each_passage(source) do |row|
        passages += 1
        scan(row[:text]).each { |name| tally[name] += 1 }
        @progress&.load_tick(passages, 0) if (passages % PAGE).zero?
      end
      ceiling = [(passages * STOP_SHARE).ceil, 20].max
      stopped = tally.select { |_n, c| c > ceiling }.sort_by { |_n, c| -c }
      Census.new(
        source: source, authority: @authority, passages: passages,
        name_hits: tally.sort_by { |_n, c| -c },
        names_loaded: names.size, names_non_han: @non_han, names_ambiguous: @ambiguous,
        names_stopped: stopped,
        seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      )
    end

    private

    def load_names
      return @names if @names

      rows = @catalog[Store::PersonIndex::NAMES_TABLE]
             .where(authority: @authority)
             .select_hash_groups(:name_key, :person_id)
      @non_han = 0
      @ambiguous = 0
      @names = rows.filter_map do |name, ids|
        next unless name.length >= MIN_NAME_CHARS

        unless HAN.match?(name)
          @non_han += 1
          next
        end
        if ids.uniq.size > MAX_PERSONS_PER_NAME
          @ambiguous += 1
          next
        end
        [name, ids.uniq]
      end.to_h
      @buckets = @names.keys.group_by { |n| n[0] }
                            .transform_values { |list| list.sort_by { |n| -n.length } }
      @names
    end

    def scan(text)
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
                   .select(Sequel[:passages][:id].as(:pid), Sequel[:passages][:text])
                   .all
        break if rows.empty?

        cursor = rows.last[:pid]
        rows.each(&block)
      end
    end
  end
end
