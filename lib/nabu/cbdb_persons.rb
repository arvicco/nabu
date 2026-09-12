# frozen_string_literal: true

module Nabu
  # The CBDB person read seam (P97-2 — №R-62 option b, the thin slice):
  # BIOG_MAIN + ALTNAME_DATA + DYNASTIES from the held sqlite artifact
  # projected into the "cbdb" person-index slice. Read-only on
  # canonical; the sqlite is opened read-only and closed after the walk.
  #
  # == Name keys (the future PersonMine substrate)
  #
  # Each person contributes the Han name verbatim (fold leaves Han) and
  # the pinyin transcription folded, plus every ALTNAME_DATA row's two
  # forms — courtesy names (字), studio names (號), posthumous names:
  # the spellings texts actually cite people by. Single-character keys
  # are kept here (the miner applies its own floors).
  #
  # == Honest scope notes (the ruling's own)
  #
  # v1 reads THREE tables of CBDB's ~100; offices, kinship and place
  # associations stay in the artifact, queryable the day a ruling wants
  # them. Nothing derived here is exported — CC BY-NC-SA, class nc.
  module CbdbPersons
    AUTHORITY = "cbdb"

    # What one derivation did, for the sync tail.
    Census = Data.define(:persons, :seconds)

    module_function

    def sqlite_path(workdir)
      path = Dir.glob(File.join(workdir, "cbdb_*.sqlite3")).max
      path && File.file?(path) ? path : nil
    end

    # Stream every person as a Store::PersonIndex::Person. Loads the
    # dynasty map and the alt-name table grouped per person first (both
    # small beside BIOG_MAIN), then walks BIOG_MAIN in pages.
    def each_person(path, &)
      return enum_for(:each_person, path) unless block_given?

      db = Store.connect(path, readonly: true)
      begin
        dynasties = db[:DYNASTIES].select_hash(:c_dy, %i[c_dynasty c_dynasty_chn])
        alt_names = Hash.new { |h, k| h[k] = [] }
        db[:ALTNAME_DATA].select(:c_personid, :c_alt_name, :c_alt_name_chn).each do |row|
          alt_names[row[:c_personid]] << [row[:c_alt_name], row[:c_alt_name_chn]]
        end
        db[:BIOG_MAIN]
          .select(:c_personid, :c_name, :c_name_chn, :c_birthyear, :c_deathyear,
                  :c_index_year, :c_dy, :c_female)
          .order(:c_personid)
          .paged_each(rows_per_fetch: 5_000) do |row|
          yield build_person(row, dynasties, alt_names[row[:c_personid]])
        end
      ensure
        db.disconnect
      end
    end

    def build_person(row, dynasties, alts)
      dynasty, dynasty_han = dynasties[row[:c_dy]]
      names = [row[:c_name], row[:c_name_chn]] + alts.flatten
      Store::PersonIndex::Person.new(
        authority: AUTHORITY, person_id: row[:c_personid].to_s,
        name: presence(row[:c_name]), name_han: presence(row[:c_name_chn]),
        birth_year: year_or_nil(row[:c_birthyear]),
        death_year: year_or_nil(row[:c_deathyear]),
        index_year: year_or_nil(row[:c_index_year]),
        dynasty: presence(dynasty), dynasty_han: presence(dynasty_han),
        female: row[:c_female] == 1,
        name_keys: names.compact.map(&:strip).reject(&:empty?)
                        .map { |n| Nabu::Pleiades.name_key(n) }.uniq
      )
    end

    def presence(value)
      s = value.to_s.strip
      s.empty? ? nil : s
    end

    # CBDB writes 0 for "unknown year" — an honest nil here.
    def year_or_nil(value)
      value.nil? || value.zero? ? nil : value
    end

    # The sync/rebuild derivation seam (the chgis Producer mold): the
    # cbdb person-index slice, wholesale. No artifact → honest no-op.
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def run(_slug, workdir:)
        path = CbdbPersons.sqlite_path(workdir)
        return nil if path.nil?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        count = Store::PersonIndex.derive!(
          @catalog, persons: CbdbPersons.each_person(path), authority: AUTHORITY
        )
        return nil if count.nil?

        Census.new(persons: count,
                   seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end
  end
end
