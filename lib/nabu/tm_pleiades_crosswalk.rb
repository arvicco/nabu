# frozen_string_literal: true

require "json"
require "zlib"

require_relative "pleiades"
require_relative "place_refs"

module Nabu
  # The Trismegistos-place → Pleiades crosswalk, DERIVED in-house from two
  # held, openly licensed files (pure derived data — place_crosswalk is
  # dropped and re-derived by every rebuild):
  #
  #   1. EDH's own geography file, canonical/edh/geography/edhGeographicData.json
  #      (the edh fetch's declared sidecar — Adapters::Edh::GEOGRAPHY). A
  #      GeoJSON FeatureCollection, one feature per EDH findspot record
  #      (29,861 on the 2021-12-16 file), each carrying `trismegistos_geo_uri`
  #      and, when EDH matched it, `pleiades_uri`: EDH maintains this
  #      TM↔Pleiades pairing itself, for its own findspots.
  #   2. The Pleiades dump we already hold (canonical/pleiades/), whose
  #      places' `references` cite their Trismegistos place record
  #      (`…trismegistos.org/place/<id>`) — the gazetteer's own backlinks.
  #
  # Both files are read through Nabu::PlaceRefs (the one place-ref reader),
  # never an inline regex.
  #
  # == The merge rule (one row per TM place; ambiguity is withheld, never guessed)
  #
  #   EDH side   — EDH's features vote: the PLURALITY pleiades id among the
  #                features carrying a given TM id (the file has per-findspot
  #                noise: 342 TM ids are split across several Pleiades ids on
  #                the real file). A tie is broken only by the dump's own
  #                claim naming one of the tied ids; an uncorroborated tie
  #                means EDH asserts nothing decisive for that TM id.
  #   dump side  — a TM id cited by exactly ONE Pleiades place is a claim; a
  #                TM id cited by several places (Assyria kingdom + region,
  #                Baetica twice …) is ambiguous and asserts nothing.
  #   precedence — where both sides claim, EDH WINS (the precedence a manual
  #                spot-check of the real conflicts settled on; the
  #                disagreement count is censused on every run);
  #                the dump fills every TM id EDH leaves unclaimed. A TM id
  #                neither side claims decisively is WITHHELD (censused).
  #
  # Each row keeps its provenance in place_crosswalk.source: "edh" for an
  # EDH-decided row, "pleiades" for a dump-filled one — the per-source slice
  # contract (cigs, wikidata) with this builder owning both tm→pleiades
  # slices, re-derived wholesale on every run.
  #
  # == Licenses (grantor / date / terms)
  #
  #   EDH geography — Epigraphic Database Heidelberg (Heidelberg Academy of
  #     Sciences and Humanities), file dated 2021-12-16, licensed CC BY-SA 4.0
  #     (the EDH /data page's blanket grant, the same terms as every EDH
  #     dump). Internal registry use (this table, the place desk, search
  #     filters) is unencumbered; ANY future public export of rows with
  #     source "edh" must carry CC BY-SA 4.0 and attribute the Epigraphic
  #     Database Heidelberg.
  #   Pleiades dump — the Pleiades project (pleiades.stoa.org), CC BY 3.0
  #     (downloads page: "Creative Commons Attribution 3.0 License (cc-by)");
  #     a public export of "pleiades" rows attributes Pleiades.
  #
  # == Wiring (the place_index_producer seam — both inputs trigger it)
  #
  # Producer runs as Adapters::Edh's place_index_producer (after every edh
  # sync, and at rebuild's place-index replay); PleiadesProducer replaces
  # Adapters::Pleiades's (the place index AND this crosswalk from ONE dump
  # load). Each locates the OTHER input as a sibling under the canonical
  # root — Config#source_workdir is canonical/<slug> for every non-local
  # slug, so File.dirname(workdir) IS canonical/.
  module TmPleiadesCrosswalk
    GEOGRAPHY_SUBDIR = "geography"
    GEOGRAPHY_FILENAME = "edhGeographicData.json"
    EDH_SOURCE = "edh"
    PLEIADES_SOURCE = "pleiades"
    GAZETTEER_A = "tm"
    GAZETTEER_B = "pleiades"

    # One crosswalk row: tm place id → pleiades place id, with provenance.
    Pair = Data.define(:tm, :pleiades, :source)

    # The merge outcome: +pairs+ (sorted by numeric tm id), the counts of
    # TM ids both sides claim alike (+agreements+) or differently
    # (+disagreements+ — EDH won each), and the +withheld+ ambiguous TM ids.
    Derivation = Data.define(:pairs, :agreements, :disagreements, :withheld)

    # The sync tail's census (format_sync_place_index): +places+ is the
    # place-index count (nil on the edh side, which derives no index slice).
    Census = Data.define(:places, :seconds, :crosswalk_pairs)

    module_function

    # The sidecar path under the edh workdir, or nil before it is fetched.
    def geography_path(edh_workdir)
      path = File.join(edh_workdir, GEOGRAPHY_SUBDIR, GEOGRAPHY_FILENAME)
      File.file?(path) ? path : nil
    end

    # tm id → every pleiades id EDH's features assert for it, one entry per
    # feature (the multiplicity IS the vote). Features lacking either uri
    # claim nothing.
    def edh_claims(path)
      features = JSON.parse(File.read(path, encoding: "UTF-8")).fetch("features", [])
      features.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |feature, claims|
        props = feature.is_a?(Hash) ? feature["properties"] || {} : {}
        tm = first_id(props["trismegistos_geo_uri"], "tm")
        pleiades = first_id(props["pleiades_uri"], "pleiades")
        claims[tm] << pleiades if tm && pleiades
      end
    end

    # tm id → the distinct Pleiades places whose references cite it.
    def pleiades_claims(entries)
      entries.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |entry, claims|
        next unless entry.is_a?(Hash) && entry["id"]

        place = entry["id"].to_s
        Array(entry["references"]).each do |reference|
          next unless reference.is_a?(Hash)

          text = reference.values_at("accessURI", "shortTitle", "citationDetail").join(" ")
          PlaceRefs.ids_in(text, "tm").each do |tm|
            key = canonical_id(tm)
            claims[key] << place unless claims[key].include?(place)
          end
        end
      end
    end

    # The merge rule (module note) over the two claim maps.
    def derive(edh:, pleiades:)
      pairs = []
      withheld = []
      agreements = disagreements = 0
      (edh.keys | pleiades.keys).sort_by(&:to_i).each do |tm|
        dump = pleiades.fetch(tm, [])
        dump_claim = dump.size == 1 ? dump.first : nil
        edh_claim = edh_decision(edh.fetch(tm, []), dump)
        if edh_claim
          if dump_claim
            dump_claim == edh_claim ? agreements += 1 : disagreements += 1
          end
          pairs << Pair.new(tm: tm, pleiades: edh_claim, source: EDH_SOURCE)
        elsif dump_claim
          pairs << Pair.new(tm: tm, pleiades: dump_claim, source: PLEIADES_SOURCE)
        else
          withheld << tm
        end
      end
      Derivation.new(pairs: pairs, agreements: agreements, disagreements: disagreements, withheld: withheld)
    end

    # Supersede this builder's two tm→pleiades slices wholesale and insert
    # the derivation. Returns the row count, or nil on a catalog that
    # predates migration 026.
    def write!(catalog, derivation)
      return nil unless catalog.table_exists?(:place_crosswalk)

      rows = derivation.pairs.map do |pair|
        { source: pair.source, gazetteer_a: GAZETTEER_A, id_a: pair.tm,
          gazetteer_b: GAZETTEER_B, id_b: pair.pleiades }
      end
      catalog.transaction do
        catalog[:place_crosswalk].where(source: [EDH_SOURCE, PLEIADES_SOURCE],
                                        gazetteer_a: GAZETTEER_A, gazetteer_b: GAZETTEER_B).delete
        rows.each_slice(1_000) { |slice| catalog[:place_crosswalk].multi_insert(slice) }
      end
      rows.size
    end

    # Derive from whatever of the two inputs is on disk (+entries+: the
    # already-parsed dump, or nil). Neither present → nil, superseding
    # nothing (the parse-only-before-first-fetch no-op).
    def derive_and_write!(catalog, geography_path:, entries:)
      return nil if geography_path.nil? && entries.nil?

      derivation = derive(edh: geography_path ? edh_claims(geography_path) : {},
                          pleiades: entries ? pleiades_claims(entries) : {})
      write!(catalog, derivation)
    end

    # EDH's plurality claim for one TM id, or nil (no votes / an
    # uncorroborated tie — module note).
    def edh_decision(votes, dump)
      return nil if votes.empty?

      tally = votes.tally
      top = tally.values.max
      leaders = tally.select { |_, count| count == top }.keys
      return leaders.first if leaders.size == 1

      corroborated = leaders & dump
      corroborated.size == 1 ? corroborated.first : nil
    end

    def first_id(uri, namespace)
      id = PlaceRefs.ids_in(uri.to_s, namespace).first
      id && canonical_id(id)
    end

    # Ids are numeric on both sides; leading zeros fold (TM "0123" = 123).
    def canonical_id(id) = id.sub(/\A0+(?=\d)/, "")

    # The edh-side producer (Adapters::Edh.place_index_producer): crosswalk
    # only — loads the sibling Pleiades dump when it is on disk.
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def run(_slug, workdir:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        dump = Nabu::Pleiades.dump_path(File.join(File.dirname(workdir), "pleiades"))
        count = TmPleiadesCrosswalk.derive_and_write!(
          @catalog, geography_path: TmPleiadesCrosswalk.geography_path(workdir),
                    entries: dump && Nabu::Pleiades.dump_entries(dump)
        )
        return nil if count.nil?

        Census.new(places: nil, crosswalk_pairs: count,
                   seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end

    # The pleiades-side producer (Adapters::Pleiades.place_index_producer):
    # the P45-6 place index exactly as before, plus the crosswalk, off ONE
    # dump parse (the ~3 s / ~3.9 GB load is paid once).
    class PleiadesProducer < Store::PlaceIndex::Producer
      def run(_slug, workdir:)
        path = Nabu::Pleiades.dump_path(workdir)
        return nil if path.nil?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        entries = Nabu::Pleiades.dump_entries(path)
        resolver = Nabu::Pleiades.from_entries(entries)
        Store::PlaceIndex.derive!(@catalog, places: resolver.each_place)
        edh = TmPleiadesCrosswalk.geography_path(File.join(File.dirname(workdir), "edh"))
        count = TmPleiadesCrosswalk.derive_and_write!(@catalog, geography_path: edh, entries: entries)
        Census.new(places: resolver.size, crosswalk_pairs: count,
                   seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end
  end
end
