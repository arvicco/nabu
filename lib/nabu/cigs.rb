# frozen_string_literal: true

require "csv"

require_relative "pleiades"
require_relative "place_refs"

module Nabu
  # The CIGS read seam (P63-5): the Cuneiform Inscriptions Geographical Site
  # Index (Uppsala; CDLJ 2021-1 — CDLI's place authority in practice) parsed
  # from the canonical CSV into the "cigs" slice of the namespaced place
  # index PLUS crosswalk rows from its own columns. Read-only on canonical.
  #
  # Field reality (v1.7, 597 sites, retrieved 2026-08-08): site_id is a
  # short mnemonic key (GIR, NIP); anc_name/transc_name carry the ancient
  # and transcribed names; `legacy_name` is EXACTLY the CDLI house composite
  # ("Girsu (mod. Tello)") — the seed key for nabu-places' cdli section;
  # cdli_provenience_id / pleiades_url / geonames_url are full URLs;
  # lon_wgs1984 comes BEFORE lat_wgs1984.
  module CigsIndex
    CSV_FILENAME = "cigs.csv"
    GAZETTEER = "cigs"

    CDLI_PROVENIENCE = %r{cdli\.mpiwg-berlin\.mpg\.de/proveniences/(\d+)}

    # One site: the place-index fields plus name keys and the crosswalk
    # claims ([gazetteer, id] pairs) the row itself asserts.
    Row = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods,
                      :name_keys, :crosswalks)

    module_function

    def csv_path(workdir)
      path = File.join(workdir, CSV_FILENAME)
      File.file?(path) ? path : nil
    end

    # Line endings are normalized before parse: the real v1.7 file is CRLF
    # throughout EXCEPT row KRB (line 293), which ends with a bare LF —
    # Ruby's CSV auto-detects "\r\n" and then refuses the bare "\n" as an
    # in-field newline (measured 2026-08-08; the KRB fixture row is the
    # regression bytes).
    def each_row(path)
      return enum_for(:each_row, path) unless block_given?

      data = File.read(path, encoding: "UTF-8").gsub(/\r\n?/, "\n")
      CSV.parse(data, headers: true) do |record|
        yield build_row(record)
      end
    end

    def build_row(record)
      names = [record["anc_name"], record["transc_name"], record["legacy_name"]]
              .compact.map(&:strip).reject(&:empty?)
      Row.new(
        id: record.fetch("site_id"),
        title: names.first.to_s,
        lat: float_or_nil(record["lat_wgs1984"]), lon: float_or_nil(record["lon_wgs1984"]),
        place_types: [], time_periods: [],
        name_keys: names.map { |n| Nabu::Pleiades.name_key(n) }.uniq,
        crosswalks: crosswalks(record)
      )
    end

    # Only what the row ASSERTS: pleiades/geonames via the shared PlaceRefs
    # reader, the CDLI provenience id from its URL. Empty cells claim
    # nothing (the HAY fixture case).
    def crosswalks(record)
      pairs = Nabu::PlaceRefs.ids([record["pleiades_url"], record["geonames_url"]].compact.join(" "))
      if (m = record["cdli_provenience_id"].to_s.match(CDLI_PROVENIENCE))
        pairs += [["cdli-provenience", m[1]]]
      end
      pairs
    end

    def float_or_nil(value)
      Float(value.to_s.strip, exception: false)
    end

    # The sync/rebuild derivation seam: the cigs place-index slice + this
    # source's crosswalk slice, both wholesale. No CSV → honest no-op.
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def run(_slug, workdir:)
        path = CigsIndex.csv_path(workdir)
        return nil if path.nil?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rows = CigsIndex.each_row(path).to_a
        count = Store::PlaceIndex.derive!(
          @catalog, gazetteer: GAZETTEER, places: rows, names_for: :name_keys.to_proc
        )
        return nil if count.nil?

        derive_crosswalk!(rows)
        Store::PlaceIndex::Producer::Census.new(
          places: count,
          seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        )
      end

      private

      def derive_crosswalk!(rows)
        return unless @catalog.table_exists?(:place_crosswalk)

        inserts = rows.flat_map do |row|
          row.crosswalks.map do |gazetteer, id|
            { source: GAZETTEER, gazetteer_a: GAZETTEER, id_a: row.id,
              gazetteer_b: gazetteer, id_b: id }
          end
        end
        @catalog.transaction do
          @catalog[:place_crosswalk].where(source: GAZETTEER).delete
          inserts.each_slice(1_000) { |slice| @catalog[:place_crosswalk].multi_insert(slice) }
        end
      end
    end
  end
end
