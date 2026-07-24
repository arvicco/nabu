# frozen_string_literal: true

require "json"
require "stringio"
require "zlib"

module Nabu
  # A pure READ seam over the Pleiades gazetteer dump (P43-3): given a
  # Pleiades place id, return the handful of facts the display surfaces need
  # — title, representative point, place types, time periods. There is NO
  # catalog table and NO migration: Pleiades is registered as a feature
  # module whose canonical asset is the numbered quarterly archival release
  # (Zenodo 4.1, 2025-05-28), and this resolver reads that dump directly,
  # like the suttacentral parallels graph is read directly by its producer.
  # A later packet consumes it on display surfaces (an isicily/itant record's
  # place metadata already carries an "ancient_ref" Pleiades id).
  #
  # == The dump shape (honest about what is verifiable offline)
  #
  # Every Pleiades PLACE is one JSON object with (the fields this seam uses):
  #   "id"          => the numeric place id (string or integer)
  #   "title"       => the place's display title
  #   "reprPoint"   => [lon, lat] — GeoJSON order (nil for a place with no
  #                    representative point)
  #   "placeTypes"  => [type strings]
  #   time periods  => carried on attestations, not a top-level field:
  #                    names[].attestations[].timePeriod AND
  #                    locations[].attestations[].timePeriod
  #
  # The per-place object above IS the dump's entry shape — a place is
  # spelled identically whether served standalone (pleiades.stoa.org/places/
  # <id>/json) or inside the dump. What is NOT verifiable offline is the
  # dump's OUTER CONTAINER (GeoJSON FeatureCollection vs a "@graph" array vs
  # JSON-lines vs a .json.gz of any of these). So #load accepts them all — a
  # bare array, an object with a "@graph"/"features"/"@graph"-style array, a
  # single place object, and gzip of any — and the real container is
  # confirmed at the owner's first sync (see Adapters::Pleiades). The test
  # fixture dump is an assembled JSON array of two real per-place documents
  # (test/fixtures/pleiades/README.md).
  class Pleiades
    # The facts one place contributes to a display surface. +lat+/+lon+ are
    # split out explicitly (the dump stores [lon, lat]; this avoids every
    # caller having to remember the GeoJSON order). +time_periods+ is the
    # distinct attestation time-period vocabulary, first-seen order.
    Place = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods)

    # Container keys a JSON-object dump might wrap its place list under. Only
    # "@graph" (JSON-LD) — NOT "features": a Pleiades place object itself
    # carries a "features" key (its own GeoJSON features), so treating a
    # top-level "features" as the place list collides with per-place data. A
    # real dump that turns out to be a GeoJSON FeatureCollection is handled at
    # first sync via .from_entries (its Feature entries need mapping first).
    GRAPH_KEY = "@graph"
    private_constant :GRAPH_KEY

    # Build a resolver from a dump file (plain JSON or gzip; any of the
    # accepted containers — class note). Indexes every place by string id.
    def self.load(dump_path)
      new(index(read_entries(dump_path)))
    end

    # Build a resolver directly from an array of place entry hashes (the
    # dump-iteration seam — a first-sync verifier can hand it whatever the
    # real container yields).
    def self.from_entries(entries)
      new(index(entries))
    end

    def self.read_entries(dump_path)
      raw = File.binread(dump_path)
      raw = Zlib::GzipReader.new(StringIO.new(raw)).read if gzip?(raw)
      unwrap(JSON.parse(raw))
    end
    private_class_method :read_entries

    # gzip magic bytes (1f 8b) — the real dump ships .json.gz.
    def self.gzip?(bytes)
      bytes.getbyte(0) == 0x1f && bytes.getbyte(1) == 0x8b
    end
    private_class_method :gzip?

    # Coerce a parsed dump to an array of place entries across the containers
    # the real release might use (class note).
    def self.unwrap(parsed)
      case parsed
      when Array then parsed
      when Hash
        return parsed[GRAPH_KEY] if parsed[GRAPH_KEY].is_a?(Array)
        return [parsed] if parsed.key?("id") # a single place object

        raise ParseError, "pleiades dump: unrecognized container (no array, no @graph, no place id) — " \
                          "confirm the release layout and map via Nabu::Pleiades.from_entries"
      else
        raise ParseError, "pleiades dump: unexpected top-level #{parsed.class}"
      end
    end
    private_class_method :unwrap

    def self.index(entries)
      entries.each_with_object({}) do |entry, by_id|
        place = build_place(entry)
        by_id[place.id] = place if place
      end
    end
    private_class_method :index

    def self.build_place(entry)
      return nil unless entry.is_a?(Hash)

      id = entry["id"]&.to_s
      return nil if id.nil? || id.empty?

      point = entry["reprPoint"]
      lon, lat = point.is_a?(Array) ? point : [nil, nil]
      Place.new(id: id, title: entry["title"], lat: lat, lon: lon,
                place_types: Array(entry["placeTypes"]), time_periods: time_periods(entry))
    end
    private_class_method :build_place

    # Distinct attestation time periods across names and locations, in
    # first-seen order (class note).
    def self.time_periods(entry)
      attestations = (Array(entry["names"]) + Array(entry["locations"]))
                     .flat_map { |item| Array(item.is_a?(Hash) ? item["attestations"] : nil) }
      attestations.filter_map { |att| att["timePeriod"] if att.is_a?(Hash) }.uniq
    end
    private_class_method :time_periods

    def initialize(by_id)
      @by_id = by_id
    end

    # The Place for +id+ (string or integer), or nil when the dump holds no
    # such place.
    def place(id)
      @by_id[id.to_s]
    end

    # How many places the dump carried.
    def size
      @by_id.size
    end
  end
end
