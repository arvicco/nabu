# frozen_string_literal: true

require "json"
require_relative "pleiades"
require_relative "normalize"

module Nabu
  # The al-Ṯurayyā read seam (the chgis/nrct gazetteer-module mold): the
  # al-Ṯurayyā Gazetteer of the early Islamic world (Romanov, Seydi et
  # al., U Leipzig; georeferenced from Cornu's Atlas du monde arabo-
  # islamique à l'époque classique, IXe–Xe siècles), parsed from its
  # master GeoJSON into the "thurayya" slice of the namespaced place
  # index — the Arabic places lane's name keys. Read-only on canonical.
  #
  # == The artifact (censused 2026-10-10, upstream HEAD f244e65d)
  #
  # master/places_new_structure.geojson — the file the live map loads
  # (index.html `<link rel="points">`) — is ONE FeatureCollection of
  # 2,521 Point features. Each carries properties.althurayyaData: URI
  # (the gazetteer's own id, TRANSLIT_<lon><E|W><lat><N|S>_<class>),
  # top_type (towns/waystations/regions/villages/xroads/waters/capitals/
  # sites/metropoles/quarters), region_URI (→ master/regions.json's 26
  # region records), and names.{ara,eng}.{common, common_other, search,
  # translit, translit_other}. The legacy per-place places/*.geojson and
  # master/places.geojson are the 2016 pre-restructure layout, unread.
  #
  # == Name keys
  #
  # Every written form the record carries: the Arabic common name and its
  # "، "-separated variant list, the Arabic search form, the full
  # ŧ-transliteration and its ", "-separated variants, the simplified
  # ASCII search forms (which also carry exonyms — "Irbil, Erbil"), and
  # the occasional English common name ("Cairo"). Folded through the
  # shared Pleiades key rule (Arabic untouched, Latin case-folded).
  #
  # == Honest scope notes
  #
  # * xroads (189 features: ROUTPOINT…/ROUTEPOINTS… ids) are anonymous
  #   route-graph junctions whose "names" are placeholders (RoutPoint0107)
  #   — skipped, never indexed as toponyms.
  # * One URI repeats upstream (QAHIRA_312E300N_S: a 2017 "metropoles"
  #   record + the Cornu "quarters" record) — coalesced, first record
  #   wins the scalars, name keys and types union (the chgis rule).
  # * No time_periods: the gazetteer is one era (Cornu's 9th–10th c.
  #   atlas) and carries no per-place dates — declared, not inferred.
  # * coord_certainty is uniformly "certain" upstream (unread); the
  #   references block (896 primary-source title matches, one EI2 link)
  #   and master/routes.json (the route network) are future seams.
  module AlthurayyaIndex
    PLACES_FILE = File.join("master", "places_new_structure.geojson").freeze
    REGIONS_FILE = File.join("master", "regions.json").freeze
    GAZETTEER = "thurayya"
    SKIPPED_TYPES = %w[xroads].freeze
    NO_REGION = "NoRegion"

    # The gazetteer's URI shape (the nabu-places `thurayya:` id shape):
    # simplified-transliteration stem (A–Z, digits, hyphen), the
    # tenths-of-degree lon/lat stamp, the class letter — R region,
    # S settlement, W water, O other.
    ID_PATTERN = /\A[A-Z0-9-]+_\d{3}[EW]\d{3}[NS]_[RSWO]\z/

    VARIANT_SEPARATOR = /[,،]/

    Row = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods,
                      :name_keys, :parent)

    module_function

    def places_path(workdir)
      path = File.join(workdir, PLACES_FILE)
      File.file?(path) ? path : nil
    end

    # The derived place rows (xroads skipped, duplicate URIs coalesced),
    # upstream order; [] when the GeoJSON is absent.
    def rows(workdir)
      path = places_path(workdir)
      return [] if path.nil?

      regions = load_regions(workdir)
      built = JSON.parse(File.read(path, encoding: "UTF-8")).fetch("features").filter_map do |feature|
        build_row(feature, regions: regions)
      end
      coalesce(built)
    end

    # region_URI → display label ("Iraq_RE" → "al-ʿIrāq"); {} without
    # the file (the parent then falls back to the bare region URI).
    def load_regions(workdir)
      path = File.join(workdir, REGIONS_FILE)
      return {} unless File.file?(path)

      JSON.parse(File.read(path, encoding: "UTF-8")).transform_values { |r| r["display"] }
    end

    def build_row(feature, regions:)
      data = feature.dig("properties", "althurayyaData") || {}
      return nil if SKIPPED_TYPES.include?(data["top_type"])

      lon, lat = feature.dig("geometry", "coordinates")
      Row.new(
        id: data.fetch("URI"),
        title: title(data["names"]),
        lat: float_or_nil(lat), lon: float_or_nil(lon),
        place_types: [data["top_type"]].compact,
        time_periods: [],
        name_keys: name_forms(data["names"]).map { |n| Nabu::Pleiades.name_key(n) }.uniq,
        parent: parent(data["region_URI"], regions)
      )
    end

    # The project's full transliteration ("Baġdād"), else the Arabic.
    def title(names)
      [names.dig("eng", "translit"), names.dig("ara", "common")]
        .map { |n| Nabu::Normalize.nfc(n.to_s.strip) }.find { |n| !n.empty? }
    end

    def name_forms(names)
      raw = %w[ara eng].product(%w[common common_other search translit translit_other])
                       .flat_map { |lang, field| names.dig(lang, field).to_s.split(VARIANT_SEPARATOR) }
      raw.map { |n| Nabu::Normalize.nfc(n.strip) }.reject(&:empty?)
    end

    def parent(region_uri, regions)
      return nil if region_uri.nil? || region_uri.empty? || region_uri == NO_REGION

      Nabu::Normalize.nfc(regions.fetch(region_uri, region_uri))
    end

    def coalesce(rows)
      rows.group_by(&:id).map do |_, group|
        next group.first if group.size == 1

        group.first.with(
          place_types: group.flat_map(&:place_types).uniq,
          name_keys: group.flat_map(&:name_keys).uniq
        )
      end
    end

    def float_or_nil(value)
      Float(value.to_s, exception: false)
    end

    # The sync/rebuild derivation seam (the nrct Producer mold): the
    # thurayya place-index slice, wholesale. No GeoJSON → honest no-op.
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def run(_slug, workdir:)
        return nil if AlthurayyaIndex.places_path(workdir).nil?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        count = Store::PlaceIndex.derive!(
          @catalog, gazetteer: GAZETTEER, places: AlthurayyaIndex.rows(workdir),
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
