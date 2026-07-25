# frozen_string_literal: true

require "json"

module Nabu
  module Store
    # The derived Pleiades place index (P45-6, migration 021): the gazetteer
    # dump projected into catalog tables at LOAD time so reads are probes.
    # The v1 resolver (Nabu::Pleiades) re-parsed the 129 MB JSON dump on
    # every invocation that needed a place (~3 s / ~3.9 GB peak RSS on the
    # real 42,242-place dump — the accepted P44-2 cost, journaled); this is
    # the write-time-doctrine fix (architecture: anything O(corpus) runs at
    # write time), the source_stats posture applied to the gazetteer.
    #
    # == Lifecycle (the rebuildability contract)
    #
    # Derived WHOLESALE from canonical/pleiades bytes and nothing else:
    # - `nabu sync pleiades` re-derives right after the fetch/parse phase
    #   (SyncRunner#refresh_place_index, via the adapter's declared
    #   Producer — the P44-7 enrichment_producer seam shape);
    # - `nabu rebuild` (full and --incremental) re-derives via
    #   Rebuild#replay_place_index, so db/ stays a pure function of
    #   canonical/ + code.
    # derive! is idempotent (delete + insert in one transaction; the tables
    # are surrogate-key-free, so a re-derivation of the same dump is
    # row-identical — test-pinned) and supersedes wholly, never accretes.
    #
    # == The resolver (the read seam)
    #
    # Resolver duck-types the three calls every consumer makes on
    # Nabu::Pleiades — #place(id), #titled(name), #size — returning the same
    # Nabu::Pleiades::Place values, so Query::Place / Query::Show / the MCP
    # tools take either interchangeably. Matching semantics are IDENTICAL by
    # construction: both paths share Nabu::Pleiades.name_key/.title_keys
    # (Unicode case fold — whole title plus "/"-separated variant segments,
    # never fuzzy), the keys folded in Ruby at derive time because SQLite's
    # lower() is ASCII-only. Consumers obtain a Resolver only through
    # Nabu::Pleiades.load_default(catalog:), which prefers a POPULATED index
    # and falls back to the v1 dump path (dump synced, index not yet
    # derived) or nil (neither — the byte-identical degrade).
    module PlaceIndex
      TABLE = :place_index
      NAMES_TABLE = :place_index_names

      # multi_insert batch — bounds statement size on the 42k-place dump.
      INSERT_SLICE = 2_000

      module_function

      # Feature detection: a live catalog predating migration 021 has no
      # tables — every caller degrades to the v1 dump path when this is
      # false.
      def available?(db)
        !db.nil? && db.table_exists?(TABLE)
      end

      # A derived index answers reads; an empty one must NOT (no backfill in
      # the migration, so empty means "not yet derived", never "the
      # gazetteer holds no places" — the dump fallback covers the gap).
      def populated?(db)
        available?(db) && !db[TABLE].empty?
      end

      # The read-side Resolver over a populated index, or nil (absent /
      # underived — callers fall back to the dump path).
      def resolver(db)
        populated?(db) ? Resolver.new(db) : nil
      end

      # Re-derive the whole index from +places+ (an enumerable of
      # Nabu::Pleiades::Place, dump order — Nabu::Pleiades#each_place).
      # Wholesale delete + insert in one transaction; returns the place
      # count. No-op (nil) on a catalog predating the tables.
      def derive!(db, places:)
        return nil unless available?(db)

        rows, name_rows = build_rows(places)
        db.transaction do
          db[NAMES_TABLE].delete
          db[TABLE].delete
          rows.each_slice(INSERT_SLICE) { |slice| db[TABLE].multi_insert(slice) }
          name_rows.each_slice(INSERT_SLICE) { |slice| db[NAMES_TABLE].multi_insert(slice) }
        end
        rows.size
      end

      def build_rows(places)
        rows = []
        name_rows = []
        places.each_with_index do |place, position|
          rows << { pleiades_id: place.id, title: place.title, lat: place.lat, lon: place.lon,
                    place_types_json: JSON.generate(place.place_types),
                    time_periods_json: JSON.generate(place.time_periods),
                    position: position }
          Nabu::Pleiades.title_keys(place.title).each do |key|
            name_rows << { pleiades_id: place.id, name_key: key }
          end
        end
        [rows, name_rows]
      end

      # Reads the derived tables with the exact v1 resolver surface
      # (module note). Every hit rebuilds the same Nabu::Pleiades::Place
      # value the dump path would have returned.
      class Resolver
        def initialize(db)
          @db = db
        end

        # The Place for +id+ (string or integer), or nil when the index
        # holds no such place.
        def place(id)
          row = @db[TABLE].first(pleiades_id: id.to_s)
          row && build_place(row)
        end

        # Every place matching +name+ exactly (whole title or a "/"-variant
        # segment, Unicode-case-folded — the pinned P44-2/P44-3 semantics),
        # dump order. Never fuzzy: the lookup is key equality, no LIKE.
        def titled(name)
          @db[TABLE]
            .join(NAMES_TABLE, pleiades_id: :pleiades_id)
            .where(Sequel[NAMES_TABLE][:name_key] => Nabu::Pleiades.name_key(name))
            .order(Sequel[TABLE][:position])
            .select_all(TABLE)
            .map { |row| build_place(row) }
        end

        # How many places the derivation carried.
        def size
          @db[TABLE].count
        end

        private

        def build_place(row)
          Nabu::Pleiades::Place.new(
            id: row[:pleiades_id], title: row[:title], lat: row[:lat], lon: row[:lon],
            place_types: JSON.parse(row[:place_types_json]),
            time_periods: JSON.parse(row[:time_periods_json])
          )
        end
      end

      # The sync/rebuild derivation seam (the P44-7 enrichment-producer
      # shape): built by Adapters::Pleiades.place_index_producer, run by
      # SyncRunner after a pleiades load and by Rebuild/IncrementalRebuild
      # after replay. Reads the dump from the source's canonical workdir —
      # read-only on canonical, like the loader.
      class Producer
        # What one derivation did, for the CLI's report line.
        Census = Data.define(:places, :seconds)

        def initialize(catalog:)
          @catalog = catalog
        end

        # Derive from the dump under +workdir+ (canonical/pleiades). No dump
        # on disk → honest no-op (nil) — the parse-only-before-first-fetch
        # case; nothing is superseded.
        def run(_slug, workdir:)
          path = Nabu::Pleiades.dump_path(workdir)
          return nil if path.nil?

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          resolver = Nabu::Pleiades.load(path)
          PlaceIndex.derive!(@catalog, places: resolver.each_place)
          Census.new(places: resolver.size,
                     seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        end
      end
    end
  end
end
