# frozen_string_literal: true

require_relative "name_words"
require_relative "source_passage_walk"

module Nabu
  # PersonMine (P97-2 — owner ruling 2026-09-11, option b): the CENSUS-ONLY person-name
  # scan — the PlaceMine scan shape over the person index's name keys,
  # tallying attestations per name so the owner can read the numbers
  # before ANY apply gate opens. The ruling's own condition (confirmed
  # closed on the census, 2026-09-18): this class deliberately has no
  # write path — personal names are far more ambiguous than placenames
  # (homonymy at 600k-key scale), and edges only exist after a ruling on
  # what the census shows.
  #
  # == The scope: SOURCE × AUTHORITY, explicit
  #
  # A census names both halves: the source whose live passages are read
  # and the person-index authority whose keys are matched (cbdb by
  # default; edh, elephantine, … — Store::PersonIndex::AUTHORITIES).
  # Nothing pairs them implicitly.
  #
  # == Two lanes, chosen by the authority's own keys
  #
  # - :han — the original lane: Han name keys matched as exact
  #   substrings (Chinese writes without word boundaries). Chosen when
  #   at least half the authority's keys carry Han (CBDB, the NIKH
  #   slices); its non-Han keys (pinyin) are censused as off-lane.
  # - :word — the epigraphic lane (EDH's inscribed + nominative Roman
  #   names, Elephantine's Greek/Coptic/Aramaic/Egyptian/English forms):
  #   name keys matched as whole-word SEQUENCES under the shared fold
  #   (Nabu::NameWords — Leiden sigla inside a word fold out on both
  #   sides). Han-bearing keys of such an authority are off-lane.
  #
  # Precision floors (censused): the 2-char Han minimum / the 3-letter
  # word-lane minimum (a bare praenomen abbreviation is not a person
  # claim), the ambiguity cap (a name naming more than
  # MAX_PERSONS_PER_NAME distinct persons identifies nobody — note an
  # EDH person is an ATTESTATION, so a name inscribed on four stones is
  # capped), and the derived stop rule (share > STOP_SHARE of scanned
  # passages = a common word wearing a name's clothes).
  class PersonMine
    PAGE = 1_000
    MIN_NAME_CHARS = 2
    MIN_WORD_LETTERS = 3
    MAX_PERSONS_PER_NAME = 3
    STOP_SHARE = 0.002

    HAN = /\p{Han}/

    Census = Data.define(:source, :authority, :lane, :passages, :name_hits,
                         :names_loaded, :names_off_lane, :names_ambiguous,
                         :names_stopped, :seconds)

    def initialize(catalog:, authority: Store::PersonIndex::DEFAULT_AUTHORITY, progress: nil)
      @catalog = catalog
      @authority = authority
      @progress = progress
    end

    # The honest count: scan +source+'s live passages against the
    # authority's name keys in the authority's lane; tally per name;
    # derive stops. Writes nothing — by design, not by flag.
    def census(source:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      names = load_names
      @progress&.stage("person-mine: scanning #{source} against #{names.size} #{@authority} " \
                       "person name keys, #{@lane} lane (census only — the apply gate stays " \
                       "closed until an owner ruling)")
      tally = Hash.new(0)
      passages = 0
      SourcePassageWalk.each(@catalog, source) do |row|
        passages += 1
        scan(row[:text]).each { |name| tally[name] += 1 }
        @progress&.load_tick(passages, 0) if (passages % PAGE).zero?
      end
      ceiling = [(passages * STOP_SHARE).ceil, 20].max
      stopped = tally.select { |_n, c| c > ceiling }.sort_by { |_n, c| -c }
      Census.new(
        source: source, authority: @authority, lane: @lane, passages: passages,
        name_hits: tally.sort_by { |_n, c| -c },
        names_loaded: names.size, names_off_lane: @off_lane, names_ambiguous: @ambiguous,
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
      han = rows.keys.count { |name| HAN.match?(name) }
      @lane = !rows.empty? && han * 2 >= rows.size ? :han : :word
      @off_lane = 0
      @ambiguous = 0
      @names = @lane == :han ? han_names(rows) : word_names(rows)
      @lane == :han ? index_han : index_words
      @names
    end

    def han_names(rows)
      rows.filter_map do |name, ids|
        next unless name.length >= MIN_NAME_CHARS

        unless HAN.match?(name)
          @off_lane += 1
          next
        end
        capped(name, ids)
      end.to_h
    end

    # Keys regrouped by their word-lane form (two raw keys differing only
    # in sigla or spacing are one name), then floored and capped.
    def word_names(rows)
      grouped = Hash.new { |hash, key| hash[key] = [] }
      rows.each do |name, ids|
        if HAN.match?(name)
          @off_lane += 1
          next
        end
        key = NameWords.key(name)
        grouped[key].concat(ids) if key.scan(/\p{L}/).size >= MIN_WORD_LETTERS
      end
      grouped.filter_map { |key, ids| capped(key, ids) }.to_h
    end

    def capped(name, ids)
      if ids.uniq.size > MAX_PERSONS_PER_NAME
        @ambiguous += 1
        return nil
      end
      [name, ids.uniq]
    end

    def index_han
      @buckets = @names.keys.group_by { |n| n[0] }
                            .transform_values { |list| list.sort_by { |n| -n.length } }
    end

    # Every proper word-prefix of every name, so a sequence walk stops at
    # the first word no name continues with.
    def index_words
      @prefixes = Set.new
      @names.each_key do |key|
        words = key.split
        (1...words.size).each { |n| @prefixes << words.first(n).join(" ") }
      end
    end

    def scan(text)
      @lane == :han ? scan_han(text) : scan_words(text)
    end

    def scan_han(text)
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

    def scan_words(text)
      words = NameWords.folded(text)
      hits = nil
      words.each_index do |start|
        phrase = nil
        (start...words.size).each do |stop|
          phrase = phrase ? "#{phrase} #{words[stop]}" : words[stop]
          (hits ||= {})[phrase] = true if @names.key?(phrase)
          break unless @prefixes.include?(phrase)
        end
      end
      hits ? hits.keys : []
    end
  end
end
