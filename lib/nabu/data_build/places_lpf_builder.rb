# frozen_string_literal: true

require "csv"
require "digest"
require "json"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "../place_refs"
require_relative "builder"

module Nabu
  module DataBuild
    # The mul/places-lpf builder (P73-5) — the referenced-places gazetteer
    # in the shape the outside world asks for: a Linked Places Format v1.3
    # FeatureCollection (places.lpf.geojson) plus the LP-TSV v0.5 sidecar
    # (places.tsv) the World Historical Gazetteer uploads.
    #
    # == The grain: one Feature per published CLAIM
    #
    # Features are minted at (namespace, id) claim grain — the same slice
    # mul/place-refs publishes (license classes open+attribution, cells
    # parsed through Nabu::PlaceRefs) — NOT at merged-place grain: merging
    # pleiades/tm/cigs identities is entity resolution, and the honest v1
    # carries the merge evidence as closeMatch links[] from
    # place_crosswalk instead of asserting it. Per feature: @id points at
    # the upstream gazetteer record (or the nabu-places registry for cigs/
    # np mints), title and Point geometry come from place_index (never
    # invented — a claim without an index row falls back to its most
    # attested verbatim name, geometry absent), names[] carries every
    # distinct attested spelling cited to its corpus, when aggregates the
    # referencing documents' date spans, and fclasses maps the index's
    # place types through the keyword table below (unmapped types are
    # censused and default to S — a generic spot).
    #
    # == The P69-2 disposition (recorded here)
    #
    # The GeoNames SE/NO namespace rider ("adopt WITH the nabu-data phase
    # if the LPF packet wants it") resolves to NOT WANTED: geonames claims
    # already publish at document grain in mul/place-refs, and a modern
    # gazetteer's records are not LPF attested-toponym material — a
    # geonames-only claim features here with its attested names and no
    # invented geometry, so no GeoNames slice enters place_index.
    class PlacesLpfBuilder
      LPF_FILENAME = "places.lpf.geojson"
      TSV_FILENAME = "places.tsv"
      TSV_COLUMNS = %w[id title title_source fclasses start end lon lat matches].freeze

      LPF_CONTEXT = "https://raw.githubusercontent.com/LinkedPasts/linked-places-format/main/linkedplaces-context-v1.1.jsonld"

      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze

      # Claim namespace → the URI of the published record LPF's @id wants.
      ID_URLS = {
        "pleiades" => ->(id) { "https://pleiades.stoa.org/places/#{id}" },
        "tm" => ->(id) { "https://www.trismegistos.org/place/#{id}" },
        "geonames" => ->(id) { "https://www.geonames.org/#{id}" },
        "cigs" => ->(id) { "https://github.com/arvicco/nabu-places#cigs-#{id}" },
        "np" => ->(id) { "https://github.com/arvicco/nabu-places#np-#{id}" }
      }.freeze

      # Keyword → GeoNames-style feature class (the LPF fclasses
      # vocabulary). Matched against each place-type string, first hit
      # wins; unmapped types are censused in nabu.eval and default to S.
      FCLASS_KEYWORDS = {
        "A" => %w[region province pagus nome district administrative state],
        "P" => %w[settlement village city town polis kome municipium colonia oppidum
                  civitas vicus chorion epoikion demos metropolis quarter urban],
        "H" => %w[river lake spring water harbor harbour port canal well bath oasis],
        "T" => %w[mountain hill promontory pass valley cape rock],
        "R" => %w[road street bridge],
        "L" => %w[area estate fundus kleros field park island],
        "S" => %w[fort temple sanctuary church monastery cemetery tomb villa building
                  site station theatre amphitheatre mine quarry lighthouse findspot
                  tell ruin monument basilica plaza camp tower wall production]
      }.freeze

      OVERVIEW =
        "Every place the documents of Nabu's catalog reference, published in the format the " \
        "digital-gazetteer world exchanges: Linked Places Format (LPF) GeoJSON plus the LP-TSV " \
        "table the World Historical Gazetteer accepts as an upload. Each place carries the " \
        "spellings ancient documents actually attest (cited to their corpora), coordinates and " \
        "a title where the underlying gazetteers record them, the span of years the referencing " \
        "documents date to, and cross-gazetteer closeMatch links — so a historical-GIS project " \
        "can put these corpora on a map without re-solving any of it."

      def initialize(registry: nil)
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "mul/places-lpf needs the catalog open — the projection lives there" if catalog.nil?

        places, census = collect_places(catalog)
        index = index_for(catalog, places.keys)
        crosswalk = crosswalk_for(catalog, places.keys)
        feature_list, tsv_rows, unmapped = render(places, index, crosswalk)
        write_lpf(out_dir, feature_list)
        write_tsv(out_dir, tsv_rows)
        BuildResult.new(
          resources: resources(feature_list.size),
          recipe: recipe(feature_list),
          citations: citations(census[:slugs].keys.sort),
          evaluation: evaluation(feature_list, census, unmapped),
          overview: OVERVIEW
        )
      end

      private

      # {claim => {names: {[toponym, slug] => count}, not_before:, not_after:}}
      # over the published axis slice (the mul/place-refs license discipline).
      def collect_places(catalog)
        sources = catalog[:sources].select_hash(:id, %i[slug license_class])
        places = Hash.new { |hash, key| hash[key] = { names: Hash.new(0), not_before: nil, not_after: nil } }
        census = { excluded: Hash.new(0), slugs: {} }
        each_axis_row(catalog) do |row|
          slug, license_class = sources[row[:source_id]]
          unless PUBLISHABLE_LICENSE_CLASSES.include?(license_class)
            census[:excluded][license_class] += 1
            next
          end

          claims = Nabu::PlaceRefs.ids(row[:place_ref])
          next if claims.empty?

          census[:slugs][slug] = true
          claims.each { |namespace, id| accumulate(places["#{namespace}:#{id}"], row, slug) }
        end
        [places, census]
      end

      def each_axis_row(catalog, &)
        catalog[:document_axes]
          .exclude(place_ref: nil)
          .join(:documents, id: :document_id)
          .where(withdrawn: false)
          .select(Sequel[:documents][:source_id], Sequel[:document_axes][:place_ref],
                  Sequel[:document_axes][:place_name], Sequel[:document_axes][:not_before],
                  Sequel[:document_axes][:not_after])
          .order(Sequel[:documents][:urn], Sequel[:document_axes][:id])
          .paged_each(&)
      end

      def accumulate(place, row, slug)
        name = row[:place_name].to_s.strip
        place[:names][[name, slug]] += 1 unless name.empty?
        place[:not_before] = [place[:not_before], row[:not_before]].compact.min if row[:not_before]
        return unless row[:not_after]

        place[:not_after] = [place[:not_after], row[:not_after]].compact.max
      end

      # {claim => index row} for the claims' (gazetteer, id) pairs.
      def index_for(catalog, claims)
        by_gazetteer = claims.group_by { |claim| claim.split(":", 2).first }
        rows = {}
        by_gazetteer.each do |gazetteer, members|
          ids = members.map { |claim| claim.split(":", 2).last }
          catalog[:place_index].where(gazetteer: gazetteer, place_id: ids).each do |row|
            rows["#{gazetteer}:#{row[:place_id]}"] = row
          end
        end
        rows
      end

      # {claim => [closeMatch identifier, ...]} from place_crosswalk, both
      # directions, only toward namespaces with a public URI.
      def crosswalk_for(catalog, claims)
        wanted = claims.to_h { |claim| [claim, true] }
        links = Hash.new { |hash, key| hash[key] = [] }
        catalog[:place_crosswalk].each do |row|
          a = "#{row[:gazetteer_a]}:#{row[:id_a]}"
          b = "#{row[:gazetteer_b]}:#{row[:id_b]}"
          links[a] << b if wanted[a]
          links[b] << a if wanted[b]
        end
        links.transform_values { |list| list.uniq.filter_map { |claim| claim_uri(claim) } }
      end

      def claim_uri(claim)
        namespace, id = claim.split(":", 2)
        ID_URLS[namespace]&.call(id)
      end

      def render(places, index, crosswalk)
        unmapped = Hash.new(0)
        feature_list = []
        tsv_rows = []
        places.keys.sort.each do |claim|
          feature = feature_for(claim, places[claim], index[claim], crosswalk[claim] || [], unmapped)
          feature_list << feature
          tsv_rows << tsv_row(claim, feature, places[claim], index[claim])
        end
        [feature_list, tsv_rows, unmapped]
      end

      def feature_for(claim, place, index_row, links, unmapped)
        title = index_row&.fetch(:title, nil) || top_name(place)
        feature = {
          "@id" => claim_uri(claim),
          "type" => "Feature",
          "properties" => { "title" => title, "fclasses" => fclasses(index_row, unmapped),
                            "nabu_ref" => claim },
          "names" => names_block(place)
        }
        feature["geometry"] = geometry(index_row)
        feature["when"] = when_block(place) if place[:not_before] || place[:not_after]
        feature["links"] = links.map { |uri| { "type" => "closeMatch", "identifier" => uri } } unless links.empty?
        feature
      end

      def top_name(place)
        best = place[:names].max_by { |(_name, _slug), count| count }
        best ? best.first.first : "(unnamed)"
      end

      def names_block(place)
        by_toponym = Hash.new { |hash, key| hash[key] = [] }
        place[:names].each_key { |(name, slug)| by_toponym[name] << slug }
        by_toponym.sort.map do |toponym, slugs|
          { "toponym" => toponym, "citations" => slugs.uniq.sort.map { |slug| { "label" => slug } } }
        end
      end

      def fclasses(index_row, unmapped)
        types = index_row ? JSON.parse(index_row[:place_types_json].to_s) : []
        classes = types.filter_map { |type| fclass_for(type, unmapped) }.uniq
        classes.empty? ? ["S"] : classes
      rescue JSON::ParserError
        ["S"]
      end

      def fclass_for(type, unmapped)
        folded = type.to_s.downcase
        FCLASS_KEYWORDS.each do |fclass, keywords|
          return fclass if keywords.any? { |keyword| folded.include?(keyword) }
        end
        unmapped[type] += 1
        nil
      end

      def geometry(index_row)
        return nil if index_row.nil? || index_row[:lat].nil? || index_row[:lon].nil?

        { "type" => "Point", "coordinates" => [index_row[:lon], index_row[:lat]] }
      end

      def when_block(place)
        span = {}
        span["start"] = { "in" => lpf_year(place[:not_before]) } if place[:not_before]
        span["end"] = { "in" => lpf_year(place[:not_after]) } if place[:not_after]
        { "timespans" => [span] }
      end

      # LPF/ISO 8601 year: zero-padded to four digits, sign preserved.
      def lpf_year(year)
        year.negative? ? format("-%04d", year.abs) : format("%04d", year)
      end

      def write_lpf(out_dir, feature_list)
        document = { "type" => "FeatureCollection", "@context" => LPF_CONTEXT,
                     "features" => feature_list }
        File.write(File.join(out_dir, LPF_FILENAME), "#{JSON.pretty_generate(document)}\n")
      end

      def tsv_row(claim, feature, place, index_row)
        matches = (feature["links"] || []).map { |link| link["identifier"] }.join(";")
        [claim, feature["properties"]["title"],
         index_row ? claim.split(":", 2).first : "attested",
         feature["properties"]["fclasses"].join(";"),
         place[:not_before], place[:not_after],
         index_row&.fetch(:lon, nil), index_row&.fetch(:lat, nil), matches]
      end

      def write_tsv(out_dir, rows)
        CSV.open(File.join(out_dir, TSV_FILENAME), "w", col_sep: "\t") do |tsv|
          tsv << TSV_COLUMNS
          rows.each { |row| tsv << row }
        end
      end

      def resources(count)
        [
          Resource.new(name: "places_lpf", path: LPF_FILENAME, rows: count,
                       format: "geojson", mediatype: "application/geo+json"),
          Resource.new(name: "places_tsv", path: TSV_FILENAME, rows: count,
                       format: "tsv", mediatype: "text/tab-separated-values")
        ]
      end

      def recipe(feature_list)
        digest = Digest::SHA256.hexdigest(JSON.generate(feature_list))
        "places-lpf v1: LPF v1.3 FeatureCollection + LP-TSV v0.5 at claim grain over the " \
          "published axis slice (license classes #{PUBLISHABLE_LICENSE_CLASSES.join('+')}), " \
          "titles/coords from place_index, closeMatch from place_crosswalk; " \
          "collection sha256=#{digest}"
      end

      def citations(published_slugs)
        registry = @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
        corpus_citations = published_slugs.filter_map do |slug|
          entry = registry[slug]
          next nil if entry.nil?

          manifest = entry.manifest
          Citation.new(key: slug, type: "misc",
                       fields: { "title" => manifest.name, "howpublished" => manifest.upstream_url,
                                 "note" => "license: #{manifest.license}" })
        end
        corpus_citations + [lpf_citation]
      end

      def lpf_citation
        Citation.new(
          key: "linked-places-format", type: "misc",
          fields: {
            "title" => "Linked Places Format v1.3",
            "howpublished" => "https://github.com/LinkedPasts/linked-places-format",
            "note" => "the interchange format this dataset renders; the spec repo carries no " \
                      "license statement (noted at the P73 survey)"
          }
        )
      end

      def evaluation(feature_list, census, unmapped)
        {
          "features" => feature_list.size,
          "with_geometry" => feature_list.count { |feature| feature["geometry"] },
          "with_when" => feature_list.count { |feature| feature.key?("when") },
          "with_links" => feature_list.count { |feature| feature.key?("links") },
          "excluded_rows" => census[:excluded].sort_by { |reason, _| reason.to_s }.to_h,
          "unmapped_place_types" => unmapped.sort_by { |_, count| -count }.first(20).to_h
        }
      end
    end
  end
end
