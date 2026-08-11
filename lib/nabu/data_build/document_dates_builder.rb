# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The mul/document-dates builder (P73-7) — the dating layer,
    # published. One row per dated document_axes row: normalized signed
    # year bounds (negative = BCE, astronomical convention), the
    # precision marker where a lane records one, and the VERBATIM
    # upstream dating string (date_raw) — the honesty column that lets a
    # consumer see what the normalization was made from. An open-ended
    # bound stays empty; nothing is ever invented.
    #
    # == The license slice (owner ruling №R-24, 2026-08-11)
    #
    # CC BY-SA 4.0, one carve-out dataset (the share-alike lanes — edh,
    # tla-hf, aes, elephantine, ceipom, imp — ride inside it). Only open-
    # and attribution-class documents publish; the nc slices (ebl,
    # openiti, iip, ...) AND the ODbL lane (rundata — a copyleft class of
    # its own, incompatible with CC) are excluded row-by-row and censused
    # in nabu.eval.
    #
    # == Provenance
    #
    # The catalog's dating projection is the source of truth at URN grain
    # (the mul/lect-assignments posture — no cone shas are load-bearing);
    # the recipe embeds the published-slice sha256. The regnal-year
    # precision upgrade (№R-28, the P73-6 scout) lands here automatically
    # on a re-derive once ruled.
    class DocumentDatesBuilder
      FILENAME = "document-dates.csv"
      COLUMNS = %w[ID URN Not_Before Not_After Precision Date_Raw Source].freeze

      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze

      OVERVIEW =
        "When was each ancient document written? This dataset publishes Nabu's normalized " \
        "answer across its whole multilingual catalog: for each dated document (cited by its " \
        "stable URN), the year span the corpus's own dating resolves to — signed years, " \
        "negative for BCE — together with the verbatim upstream dating string it was derived " \
        "from, so every normalization can be checked against its source. Time-series and " \
        "period-stratified corpus work gets one uniform dating table instead of a dozen " \
        "per-corpus conventions."

      def initialize(registry: nil)
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "mul/document-dates needs the catalog open — the projection lives there" if catalog.nil?

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
        state = { rows: [], excluded: Hash.new(0), slugs: {}, dated: 0,
                  seq: Hash.new(0), sha: Digest::SHA256.new }
        each_dated_row(catalog) do |row|
          state[:dated] += 1
          slug, license_class = sources[row[:source_id]]
          unless PUBLISHABLE_LICENSE_CLASSES.include?(license_class)
            state[:excluded][license_class] += 1
            next
          end

          publish(state, row, slug)
        end
        census = { "dated_axis_rows" => state[:dated], "published_rows" => state[:rows].size,
                   "excluded_rows" => state[:excluded].sort_by { |reason, _| reason.to_s }.to_h }
        [state[:rows], census, state[:slugs].keys.sort, state[:sha].hexdigest]
      end

      def each_dated_row(catalog, &)
        catalog[:document_axes]
          .where(Sequel.~(not_before: nil) | Sequel.~(not_after: nil))
          .join(:documents, id: :document_id)
          .where(withdrawn: false)
          .select(Sequel[:documents][:urn], Sequel[:documents][:source_id],
                  Sequel[:document_axes][:not_before], Sequel[:document_axes][:not_after],
                  Sequel[:document_axes][:precision], Sequel[:document_axes][:date_raw])
          .order(Sequel[:documents][:urn], Sequel[:document_axes][:id])
          .paged_each(&)
      end

      # A document may carry several dated axis rows (multi-lane sources);
      # the per-URN sequence keeps IDs deterministic under the (urn, axis
      # id) export order.
      def publish(state, row, slug)
        state[:slugs][slug] = true
        seq = (state[:seq][row[:urn]] += 1)
        id = seq == 1 ? CsvWriter.mint_id(row[:urn]) : CsvWriter.mint_id(row[:urn], seq.to_s)
        state[:sha] << [row[:urn], row[:not_before], row[:not_after],
                        row[:precision], row[:date_raw]].join("\x1f") << "\n"
        state[:rows] << { "ID" => id, "URN" => row[:urn],
                          "Not_Before" => row[:not_before], "Not_After" => row[:not_after],
                          "Precision" => row[:precision], "Date_Raw" => row[:date_raw],
                          "Source" => slug }
      end

      def resource(count)
        fields = COLUMNS.map do |name|
          { name: name, type: %w[Not_Before Not_After].include?(name) ? "integer" : "string" }
        end
        Resource.new(name: "document_dates", path: FILENAME, rows: count,
                     fields: fields, primary_key: ["ID"])
      end

      def recipe(digest)
        "document-dates v1: project dated document_axes rows at URN grain, license classes " \
          "#{PUBLISHABLE_LICENSE_CLASSES.join('+')} only, ordered (urn, axis row); " \
          "published-slice sha256=#{digest}"
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
