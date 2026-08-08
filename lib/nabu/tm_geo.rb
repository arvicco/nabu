# frozen_string_literal: true

require "csv"

require_relative "pleiades"

module Nabu
  # The Trismegistos Geo read seam (P63-3): parses the canonical TM_geo.csv
  # (the Manual Adapter holding, P63-1) into place rows for the namespaced
  # place index — gazetteer "tm". Read-only on canonical, like every seam.
  #
  # Field reality (measured on the owner's 2026-08-08 dump, 64,857 rows):
  # every line ends `";` (semicolon AFTER the closing quote — stripped before
  # CSV parse, the documented dump quirk); name_standard is TM's own standard
  # form ("Thebes", "Philai", "Doura"); name_latin carries " - "-separated
  # variants ("Philae - Filae"); unicode_greek/egyptian/coptic carry native-
  # script forms; coordinates is "lat,lon" on 37% of rows; country
  # "ghost name" marks attested-but-unidentified names (an honest status the
  # index keeps: place_types ["ghost name"]).
  module TmGeo
    CSV_FILENAME = "TM_geo.csv"
    GAZETTEER = "tm"

    # One index row: duck-types the Nabu::Pleiades::Place fields derive!
    # reads (id/title/lat/lon/place_types/time_periods) and carries the
    # TM-specific exact-match name keys beside them.
    Row = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods, :name_keys)

    module_function

    # The canonical CSV under +workdir+ (canonical/trismegistos-geo), or nil
    # before the first manual ingest.
    def csv_path(workdir)
      path = File.join(workdir, CSV_FILENAME)
      File.file?(path) ? path : nil
    end

    # Every dump row as a Row, file order. The title is TM's standard name
    # (falling back to the Latin form, then the calculated full_name — a row
    # is never titleless); name keys fold every attested form the dump
    # carries (standard, Latin " - " variants, Greek/Demotic/Coptic unicode)
    # through the SAME Unicode case fold the pleiades keys use — one match
    # semantics across gazetteers, never fuzzy.
    def each_row(path)
      return enum_for(:each_row, path) unless block_given?

      data = File.read(path, encoding: "UTF-8").gsub(/";[ \t]*(\r?\n)/, "\"\\1")
      CSV.parse(data, headers: true) do |record|
        yield build_row(record)
      end
    end

    def build_row(record)
      lat, lon = parse_coordinates(record["coordinates"])
      standard = blank_to_nil(record["name_standard"])
      latin_variants = (record["name_latin"] || "").split(" - ").map(&:strip).reject(&:empty?)
      names = ([standard] + latin_variants +
               [record["unicode_greek"], record["unicode_egyptian"], record["unicode_coptic"]])
              .compact.map(&:strip).reject(&:empty?)
      Row.new(
        id: record.fetch("id"),
        title: standard || latin_variants.first || record["full_name"].to_s,
        lat: lat, lon: lon,
        place_types: [blank_to_nil(record["status"]), ghost_marker(record)].compact,
        time_periods: [],
        name_keys: names.map { |n| Nabu::Pleiades.name_key(n) }.uniq
      )
    end

    def parse_coordinates(value)
      parts = value.to_s.split(",", 2).map(&:strip)
      return [nil, nil] unless parts.size == 2

      [Float(parts[0], exception: false), Float(parts[1], exception: false)]
    end

    def ghost_marker(record)
      record["country"] == "ghost name" ? "ghost name" : nil
    end

    def blank_to_nil(value)
      v = value.to_s.strip
      v.empty? ? nil : v
    end

    # The sync/rebuild derivation seam (the pleiades Producer shape): derives
    # the "tm" slice of the namespaced place index from the canonical CSV.
    # No CSV on disk → honest no-op (nil) — the pre-first-ingest case.
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def run(_slug, workdir:)
        path = TmGeo.csv_path(workdir)
        return nil if path.nil?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        count = Store::PlaceIndex.derive!(
          @catalog, gazetteer: GAZETTEER, places: TmGeo.each_row(path),
                    names_for: :name_keys.to_proc
        )
        return nil if count.nil?

        Store::PlaceIndex::Producer::Census.new(
          places: count,
          seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        )
      end
    end
  end
end
