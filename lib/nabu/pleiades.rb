# frozen_string_literal: true

require "json"
require "stringio"
require "zlib"

module Nabu
  # A pure READ seam over the Pleiades gazetteer dump (P43-3): given a
  # Pleiades place id, return the handful of facts the display surfaces need
  # — title, representative point, place types, time periods. Pleiades is
  # registered as a feature module whose canonical asset is the numbered
  # quarterly archival release (Zenodo 4.1, 2025-05-28); this class parses
  # that dump directly (the v1 path). Since P45-6 the dump is ALSO projected
  # into the derived catalog place index at sync/rebuild time
  # (Store::PlaceIndex, migration 021) and .load_default prefers it — the
  # in-memory load below survives as the derivation input and the honest
  # fallback while the index is not yet derived. Consumed since P44-2 by the
  # place desk (`nabu place`, Query::Place) and the `nabu show` findspot
  # line (Query::Show), joining on the uniform place.pleiades id the
  # epigraphic parsers capture (isicily/edh/iip/itant — .ref_id below is
  # their one shared normalization seam).
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

    # The one place-ref normalization seam (P44-2). Parsers capture ONLY the
    # Pleiades ids upstream itself asserts — a pleiades.stoa.org place URL in
    # either scheme spelling (real I.Sicily headers write both http:// and
    # https://), optionally slash-terminated, or bare digits (the oracc/EDH
    # CSV spelling) — normalized to the numeric id string, the stable join
    # key the query surfaces group on. Anything else (GeoNames, sub-resource
    # URLs, prose) is nil: no fuzzy matching, ever.
    PLACE_URL = %r{\Ahttps?://pleiades\.stoa\.org/places/(\d+)/?\z}
    private_constant :PLACE_URL

    def self.ref_id(ref)
      value = ref.to_s.strip
      return nil if value.empty?
      return value if /\A\d+\z/.match?(value)

      PLACE_URL.match(value)&.[](1)
    end

    # The dump filename `nabu sync pleiades` lands (Adapters::Pleiades::
    # FILENAME — restated so this read seam stays require-independent, the
    # Lila precedent) and its uncompressed sibling.
    DUMP_BASENAMES = ["pleiades-places.json.gz", "pleiades-places.json"].freeze
    private_constant :DUMP_BASENAMES

    # The synced dump file under +dir+ (canonical/pleiades), or nil — shared
    # by load_default and the Store::PlaceIndex::Producer derivation seam.
    def self.dump_path(dir)
      DUMP_BASENAMES.map { |name| File.join(dir, name) }.find { |candidate| File.file?(candidate) }
    end

    # Feature-detect the resolver (the `nabu place`/findspot auto-load),
    # fastest honest path first (P45-6):
    #
    # 1. a POPULATED derived place index in +catalog+ → the instant
    #    Store::PlaceIndex::Resolver (same read surface, no JSON parse);
    # 2. else the synced canonical dump → the v1 in-memory load (owner-
    #    verified cost on the real 42,242-place dump: ~3 s / ~3.9 GB peak
    #    RSS — the state between landing the dump and the sync/rebuild that
    #    derives the index);
    # 3. else nil, so a corpus without the gazetteer behaves byte-identically
    #    (the Lila.load_default shape).
    #
    # +catalog+ nil (a caller with no db handle) skips straight to 2 —
    # pre-P45-6 behavior, unchanged.
    def self.load_default(config: nil, catalog: nil)
      index = catalog && Store::PlaceIndex.resolver(catalog)
      return index if index

      config ||= Nabu::Config.load
      path = dump_path(File.join(config.canonical_dir, "pleiades"))
      path && load(path)
    end

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

    # The one exact-match relation, shared verbatim by this in-memory
    # resolver and the derived SQLite index (P45-6) so the two paths cannot
    # diverge. name_key is Unicode full case folding — the String#casecmp?
    # relation ("equal after Unicode case folding") made storable; folding
    # in Ruby, never SQL, because SQLite's lower() is ASCII-only.
    def self.name_key(name)
      name.to_s.downcase(:fold)
    end

    # Every key under which +title+ is an exact match: the whole title, plus
    # — variant-aware, the P44-3 live finding — each "/"-separated segment
    # (stripped) when Pleiades joined name variants into one compound title
    # ("Segesta/Egesta"). Space-separated words are NOT variants ("Segesta
    # Tigulliorum" only matches whole). Zero fuzz, by design.
    def self.title_keys(title)
      return [] if title.nil?

      keys = [name_key(title)]
      keys.concat(title.split("/").map { |segment| name_key(segment.strip) }) if title.include?("/")
      keys.uniq
    end

    def initialize(by_id)
      @by_id = by_id
    end

    # The Place for +id+ (string or integer), or nil when the dump holds no
    # such place.
    def place(id)
      @by_id[id.to_s]
    end

    # Every place whose title equals +name+ case-insensitively (`nabu place`
    # by name, P44-2). EXACT match only — no prefixes, no substrings, no
    # fuzz (out by design); homonym titles return every bearer, dump order.
    # A linear scan over ~42k places is microseconds next to the load.
    def titled(name)
      key = self.class.name_key(name)
      @by_id.each_value.select { |place| self.class.title_keys(place.title).include?(key) }
    end

    # Every place, dump order (the Store::PlaceIndex derivation input).
    def each_place(&block)
      return enum_for(:each_place) { @by_id.size } unless block

      @by_id.each_value(&block)
    end

    # How many places the dump carried.
    def size
      @by_id.size
    end
  end
end
