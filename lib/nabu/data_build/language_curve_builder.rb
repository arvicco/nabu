# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "builder"
require_relative "csv_writer"
require_relative "rollup_slice"

module Nabu
  module DataBuild
    # The mul/language-curve builder — the catalog's language_curve
    # (Store::LemmaRollup) published: the library-wide diachronic
    # attestation census. One row per (language, century, basis, source):
    # live documents and passages. Language_ID is the passage code falling
    # back to the document's; Century the signed century index of the
    # document's date-envelope midpoint; Basis its date class (composition |
    # artifact); both empty = undated, silver-estimate datings folded in
    # (RollupSlice).
    #
    # License: CC BY-SA 4.0 (the share-alike carve-out). Open- and
    # attribution-class sources only; nc, odbl and research_private source
    # rows are excluded row-by-row and censused (rows and passages per
    # class) in nabu.eval. Own catalog projection; the recipe embeds the
    # published-slice sha256.
    class LanguageCurveBuilder
      FILENAME = "language-curve.csv"
      COLUMNS = %w[ID Language_ID Century Basis Documents Passages Source].freeze
      INTEGER_COLUMNS = %w[Century Documents Passages].freeze

      OVERVIEW =
        "When is each ancient and premodern language attested, and how much of it survives from " \
        "each century? This dataset publishes Nabu's attestation census across its whole " \
        "multilingual library: for every language, century and corpus, how many documents and " \
        "passages are held — the rise-and-fall table of the written record, dated by each " \
        "corpus's own upstream dating. Undated material is counted honestly in its own row."

      def initialize(registry: nil)
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "mul/language-curve needs the catalog open — language_curve lives there" if catalog.nil?

        state = { excluded: Hash.new(0), excluded_passages: Hash.new(0), slugs: {},
                  minter: IdMinter.new, sha: Digest::SHA256.new }
        stream = RollupSlice::Stream.new { |&emit| each_published(catalog, state, &emit) }
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: stream)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(state[:sha].hexdigest),
          citations: RollupSlice.citations(registry, state[:slugs].keys.sort),
          evaluation: census(catalog, state, count),
          overview: OVERVIEW
        )
      end

      private

      def registry
        @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
      end

      def each_published(catalog, state)
        grouped(catalog).each do |row|
          unless RollupSlice.publishable?(row[:license_class])
            state[:excluded][row[:license_class]] += 1
            state[:excluded_passages][row[:license_class]] += row[:passages]
            next
          end

          yield publish(state, row)
        end
      end

      def grouped(catalog)
        curve = :language_curve
        century = RollupSlice.century_expression(curve)
        basis = RollupSlice.basis_expression(curve)
        catalog[curve]
          .join(:sources, id: Sequel[curve][:source_id])
          .group(Sequel[curve][:language], century, basis, Sequel[:sources][:slug],
                 Sequel[:sources][:license_class])
          .select(Sequel[curve][:language], century.as(:century), basis.as(:basis),
                  Sequel[:sources][:slug], Sequel[:sources][:license_class],
                  Sequel.function(:sum, Sequel[curve][:documents]).as(:documents),
                  Sequel.function(:sum, Sequel[curve][:passages]).as(:passages))
          .order(Sequel[curve][:language], century, basis, Sequel[:sources][:slug])
      end

      def publish(state, row)
        slug = row[:slug]
        state[:slugs][slug] = true
        state[:sha] << [row[:language], row[:century], row[:basis], slug,
                        row[:documents], row[:passages]].join("\x1f") << "\n"
        id = state[:minter].mint(slug, row[:language], RollupSlice.century_token(row[:century]), row[:basis])
        { "ID" => id, "Language_ID" => row[:language], "Century" => row[:century], "Basis" => row[:basis],
          "Documents" => row[:documents], "Passages" => row[:passages], "Source" => slug }
      end

      def census(catalog, state, count)
        curve = catalog[:language_curve]
        { "curve_rows" => curve.count,
          "silver_dated_rows_folded" => curve.where(basis: RollupSlice::SILVER_BASIS).count,
          "published_rows" => count,
          "excluded_rows" => RollupSlice.sorted_census(state[:excluded]),
          "excluded_passages" => RollupSlice.sorted_census(state[:excluded_passages]) }
      end

      def resource(count)
        fields = COLUMNS.map { |name| { name: name, type: INTEGER_COLUMNS.include?(name) ? "integer" : "string" } }
        Resource.new(name: "language_curve", path: FILENAME, rows: count,
                     fields: fields, primary_key: ["ID"])
      end

      def recipe(digest)
        "language-curve v1: project language_curve at (language, century, basis, source) grain, " \
          "silver-estimate datings folded undated, license classes " \
          "#{RollupSlice::PUBLISHABLE_LICENSE_CLASSES.join('+')} only, ordered (language, century, " \
          "basis, source); published-slice sha256=#{digest}"
      end
    end
  end
end
