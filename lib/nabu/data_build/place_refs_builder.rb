# frozen_string_literal: true

require "digest"
require "fileutils"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "../place_refs"
require_relative "../places"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The mul/place-refs builder (P73-4) — the compiled doc→place
    # projection, published. One row per (document, namespaced claim) from
    # document_axes.place_ref: the claim in canonical namespace:id form
    # (every historical spelling — verbatim upstream URLs, multi-URL
    # fields, P63 mints — folded through Nabu::PlaceRefs, the ONE reader),
    # the verbatim upstream place name, and the basis in-band per axis
    # row: "nabu-places" when the ref is exactly what the registry's
    # matched decision applies for that (source, name), "upstream"
    # otherwise (adapter-asserted refs always win at apply time, so the
    # two labels converge exactly where the distinction is immaterial).
    #
    # == The license slice (owner ruling №R-24, 2026-08-11)
    #
    # CC BY-SA 4.0, one carve-out dataset (the share-alike lanes — edh,
    # aes, elephantine, ceipom, tla-hf, and the tm: index inheritance —
    # ride inside it). Only open- and attribution-class documents publish;
    # nc/odbl/research_private rows and cells the reader cannot parse are
    # excluded and censused in nabu.eval, never silently dropped.
    #
    # == Provenance
    #
    # The catalog projection is the source of truth at URN grain (stable
    # across syncs by the conformance contract); the recipe embeds the
    # published-slice sha256. The one declared input is the nabu-places
    # registry cone — the decisions the basis column cites derive from it,
    # so its sha rides the manifest and the stale-ingest guard covers it.
    class PlaceRefsBuilder
      # №R-29 (ruled 2026-08-11, sharding): the export splits into
      # fixed-size shards under place-refs/ — one multi-path Frictionless
      # resource — so no single file can cross GitHub's 100 MB hard limit
      # (the unsharded CSV measured 105 MB). 250K rows ≈ 27 MB/shard.
      SHARD_DIR = "place-refs"
      SHARD_SIZE = 250_000
      COLUMNS = %w[ID URN Place_Ref Place_Name Basis Source].freeze

      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze

      NABU_PLACES_URL = "https://github.com/arvicco/nabu-places"

      OVERVIEW =
        "Ancient documents name the places they were written in or found at, but every corpus " \
        "records that differently — a verbatim findspot string, a gazetteer URL, sometimes " \
        "several. This dataset publishes Nabu's compiled projection across its whole " \
        "multilingual catalog: for each document (cited by its stable URN), each place it " \
        "references as a clean namespaced identifier (pleiades:, tm:, geonames:, cigs:, np:) " \
        "ready to join against the public gazetteers, alongside the verbatim name the corpus " \
        "used and the basis of the link — asserted by the upstream corpus itself, or applied " \
        "from the nabu-places curation registry. Mapping and GIS pipelines can join texts to " \
        "gazetteer geometry without re-solving each corpus's ref spelling."

      def initialize(registry: nil, places: nil, shard_size: SHARD_SIZE)
        @registry = registry
        @places = places
        @shard_size = shard_size
      end

      def build(catalog:, out_dir:)
        raise Error, "mul/place-refs needs the catalog open — the projection lives there" if catalog.nil?

        rows, census, published_slugs, digest = published_rows(catalog)
        shard_paths, count = write_shards(out_dir, rows)
        BuildResult.new(
          resources: [resource(shard_paths, count)],
          recipe: recipe(digest),
          citations: citations(published_slugs),
          evaluation: census,
          overview: OVERVIEW
        )
      end

      private

      def open_places
        places = Nabu::Places.load_default(canonical_dir: Nabu::Config.load.canonical_dir)
        raise Error, "the nabu-places registry is not synced — `nabu sync nabu-places` first" if places.nil?

        places
      end

      # {slug => {name => joined refs}} for every MATCHED registry decision.
      def registry_decisions
        places = @places || open_places
        places.sources.to_h do |slug|
          matched = places.decisions_for(slug).select { |_, decision| decision.matched? }
          [slug, matched.transform_values { |decision| decision.refs.join(" ") }]
        end
      end

      def published_rows(catalog)
        decisions = registry_decisions
        sources = catalog[:sources].select_hash(:id, %i[slug license_class])
        state = { rows: [], excluded: Hash.new(0), slugs: {}, seen: {},
                  namespaces: Hash.new(0), places: {}, axis_rows: 0,
                  sha: Digest::SHA256.new }
        each_axis_row(catalog) do |row|
          state[:axis_rows] += 1
          slug, license_class = sources[row[:source_id]]
          unless PUBLISHABLE_LICENSE_CLASSES.include?(license_class)
            state[:excluded][license_class] += 1
            next
          end

          claims = Nabu::PlaceRefs.ids(row[:place_ref])
          if claims.empty?
            state[:excluded]["unparseable"] += 1
            next
          end

          publish_claims(state, row, claims, slug, decisions)
        end
        [state[:rows], evaluation(state), state[:slugs].keys.sort, state[:sha].hexdigest]
      end

      def each_axis_row(catalog, &)
        catalog[:document_axes]
          .exclude(place_ref: nil)
          .join(:documents, id: :document_id)
          .where(withdrawn: false)
          .select(Sequel[:documents][:urn], Sequel[:documents][:source_id],
                  Sequel[:document_axes][:place_ref], Sequel[:document_axes][:place_name])
          .order(Sequel[:documents][:urn], Sequel[:document_axes][:id])
          .paged_each(&)
      end

      def publish_claims(state, row, claims, slug, decisions)
        basis = decisions.dig(slug, row[:place_name]) == row[:place_ref] ? "nabu-places" : "upstream"
        claims.each do |namespace, id|
          claim = "#{namespace}:#{id}"
          key = [row[:urn], claim]
          next if state[:seen].key?(key)

          state[:seen][key] = true
          state[:slugs][slug] = true
          state[:namespaces][namespace] += 1
          state[:places][claim] = true
          state[:sha] << [row[:urn], claim, row[:place_name], basis].join("\x1f") << "\n"
          state[:rows] << { "ID" => CsvWriter.mint_id(row[:urn], claim), "URN" => row[:urn],
                            "Place_Ref" => claim, "Place_Name" => row[:place_name],
                            "Basis" => basis, "Source" => slug }
        end
      end

      def evaluation(state)
        {
          "axis_rows" => state[:axis_rows],
          "published_rows" => state[:rows].size,
          "excluded_rows" => state[:excluded].sort_by { |reason, _| reason.to_s }.to_h,
          "distinct_places" => state[:places].size,
          "claims_by_namespace" => state[:namespaces].sort.to_h
        }
      end

      # Fixed-size shards, claim order continuous across boundaries, every
      # shard with its own header. Returns [relative shard paths, total].
      def write_shards(out_dir, rows)
        FileUtils.mkdir_p(File.join(out_dir, SHARD_DIR))
        paths = []
        total = 0
        rows.each_slice(@shard_size).with_index(1) do |slice, index|
          relative = File.join(SHARD_DIR, format("part-%03d.csv", index))
          paths << relative
          total += CsvWriter.write(path: File.join(out_dir, relative), columns: COLUMNS, rows: slice)
        end
        [paths, total]
      end

      def resource(shard_paths, count)
        Resource.new(
          name: "place_refs", path: shard_paths, rows: count,
          fields: COLUMNS.map { |name| { name: name, type: "string" } },
          primary_key: ["ID"]
        )
      end

      def recipe(digest)
        "place-refs v1: project document_axes.place_ref through Nabu::PlaceRefs at (document, " \
          "claim) grain, license classes #{PUBLISHABLE_LICENSE_CLASSES.join('+')} only, ordered " \
          "(urn, axis row), sharded ≤#{@shard_size} rows/file (№R-29); " \
          "published-slice sha256=#{digest}"
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
        corpus_citations + [nabu_places_citation]
      end

      def nabu_places_citation
        Citation.new(
          key: "nabu-places", type: "misc",
          fields: {
            "title" => "nabu-places — the place decisions registry",
            "howpublished" => NABU_PLACES_URL,
            "note" => "CC BY 4.0; the curation behind every Basis=nabu-places row"
          }
        )
      end
    end
  end
end
