# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The mul/kind-classifications builder (P102-2) — the kind axis
    # (№R-63/№R-66), published. One row per (document, class) pair:
    # the ruled cross-corpus class path (multi-label documents export
    # one row per label) with the VERBATIM upstream genre label beside
    # it — the honesty column that lets a consumer see what each fold
    # was made from. A whole-source declaration row (okhc's mold)
    # carries no upstream label, honestly empty.
    #
    # The honesty buckets split: `unknown` (upstream's own "cannot
    # determine" — a ruled claim, №R-63) PUBLISHES; `unmapped` (our
    # curation lag, a TODO marker, not a classification) is excluded
    # and censused. The document-dates license slice applies: open-
    # and attribution-class documents only, nc excluded row-by-row and
    # censused in nabu.eval; CC BY-SA 4.0 under the №R-24 carve-out.
    #
    # Provenance: the catalog's kind projection is the source of truth
    # at URN grain (the lect-assignments posture — no cone shas are
    # load-bearing; the class list and folds are Nabu config, cited by
    # the recipe); the recipe embeds the published-slice sha256.
    class KindClassificationsBuilder
      FILENAME = "kind-classifications.csv"
      COLUMNS = %w[ID URN Value Kind_Raw Source].freeze

      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze
      UNMAPPED = "unmapped"

      OVERVIEW =
        "What KIND of text is each ancient document — an epitaph, a receipt, a hymn, a " \
        "school exercise? This dataset publishes Nabu's fourth document axis across its " \
        "whole multilingual catalog: for each classified document (cited by its stable URN), " \
        "the ruled cross-corpus class path (a 21-family list with named sub-classes, e.g. " \
        "funerary/epitaph, literary/poetry, divination/extispicy), multi-label as multiple " \
        "rows, together with the verbatim upstream genre label each fold was derived from — " \
        "one uniform classification table instead of a dozen per-corpus genre jargons."

      def initialize(registry: nil)
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "mul/kind-classifications needs the catalog open — the projection lives there" if catalog.nil?

        rows, census, published_slugs, digest = published_rows(catalog)
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: rows)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(digest),
          citations: citations(published_slugs),
          evaluation: census,
          overview: OVERVIEW
        )
      end

      private

      def published_rows(catalog)
        sources = catalog[:sources].select_hash(:id, %i[slug license_class])
        state = { rows: [], excluded: Hash.new(0), slugs: {}, kind_rows: 0, unmapped: 0,
                  seq: Hash.new(0), sha: Digest::SHA256.new }
        each_kind_row(catalog) do |row|
          state[:kind_rows] += 1
          if row[:value] == UNMAPPED
            state[:unmapped] += 1
            next
          end

          slug, license_class = sources[row[:source_id]]
          unless PUBLISHABLE_LICENSE_CLASSES.include?(license_class)
            state[:excluded][license_class] += 1
            next
          end

          publish(state, row, slug)
        end
        census = { "kind_rows" => state[:kind_rows], "published_rows" => state[:rows].size,
                   "excluded_rows" => state[:excluded].sort_by { |reason, _| reason.to_s }.to_h,
                   "unmapped_rows_excluded" => state[:unmapped] }
        [state[:rows], census, state[:slugs].keys.sort, state[:sha].hexdigest]
      end

      def each_kind_row(catalog, &)
        catalog[:document_facets]
          .where(facet: "kind")
          .join(:documents, id: :document_id)
          .where(withdrawn: false)
          .select(Sequel[:documents][:urn], Sequel[:documents][:source_id],
                  Sequel[:document_facets][:value], Sequel[:document_facets][:raw])
          .order(Sequel[:documents][:urn], Sequel[:document_facets][:id])
          .paged_each(&)
      end

      # A multi-label document carries several class rows; the per-URN
      # sequence keeps IDs deterministic under the (urn, facet id)
      # export order.
      def publish(state, row, slug)
        state[:slugs][slug] = true
        seq = (state[:seq][row[:urn]] += 1)
        id = seq == 1 ? CsvWriter.mint_id(row[:urn]) : CsvWriter.mint_id(row[:urn], seq.to_s)
        state[:sha] << [row[:urn], row[:value], row[:raw]].join("\x1f") << "\n"
        state[:rows] << { "ID" => id, "URN" => row[:urn],
                          "Value" => row[:value], "Kind_Raw" => row[:raw],
                          "Source" => slug }
      end

      def resource(count)
        Resource.new(name: "kind_classifications", path: FILENAME, rows: count,
                     fields: COLUMNS.map { |name| { name: name, type: "string" } },
                     primary_key: ["ID"])
      end

      def recipe(digest)
        "kind-classifications v1: project facet=kind document_facets rows at URN grain " \
          "(config/kind_classes.yml + kind_map.yml folds, №R-63/№R-66), license classes " \
          "#{PUBLISHABLE_LICENSE_CLASSES.join('+')} only, unmapped excluded, ordered " \
          "(urn, facet row); published-slice sha256=#{digest}"
      end

      def citations(published_slugs)
        registry = @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
        published_slugs.filter_map do |slug|
          entry = registry[slug]
          next nil if entry.nil?

          manifest = entry.manifest
          Citation.new(key: slug, type: "misc",
                       fields: { "title" => manifest.name, "howpublished" => manifest.upstream_url,
                                 "note" => "license: #{manifest.license}" })
        end
      end
    end
  end
end
