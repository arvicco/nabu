# frozen_string_literal: true

require_relative "../errors"
require_relative "../source_registry"
require_relative "../store/silver_dates"
require_relative "builder"

module Nabu
  module DataBuild
    # The shared screening seam of the two catalog-rollup projections
    # (mul/lemma-frequencies over lemma_rollup, mul/language-curve over
    # language_curve). Both rollups key on (..., century, basis, source):
    #
    # - License screening (the char-postings/document-dates pattern): only
    #   open- and attribution-class sources publish — the share-alike lanes
    #   (aes, tla-hf, menota, glaux, ...) are attribution class and ride
    #   inside the BY-SA dataset; nc, odbl and research_private (and any
    #   restricted) source rows are excluded ROW BY ROW against
    #   sources.license_class and censused in nabu.eval, so no screened
    #   contribution can hide in an integer.
    # - The silver-date fold: a document dated ONLY by a model/tool estimate
    #   (Store::SilverDates — basis "silver") lands in its estimate's century
    #   in the rollups. The published datasets promise upstream dating only
    #   (the mul/document-dates posture: an estimate is never minted
    #   outward), so those rows fold into the undated bucket (century and
    #   basis both empty). The fold is exact: each document carries exactly
    #   one (century, basis) bucket, so for a fixed key the document sets of
    #   different buckets are disjoint and the documents column sums without
    #   double counting.
    module RollupSlice
      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze

      SILVER_BASIS = Store::SilverDates::DATE_CLASS

      module_function

      # The century expression with a silver-estimate century folded to NULL.
      def century_expression(table)
        Sequel.case([[{ Sequel[table][:basis] => SILVER_BASIS }, nil]], Sequel[table][:century])
      end

      # The basis expression with the silver estimate folded to NULL.
      def basis_expression(table)
        Sequel.case([[{ Sequel[table][:basis] => SILVER_BASIS }, nil]], Sequel[table][:basis])
      end

      # The signed century as an identifier token: bce2 / ce5 / undated.
      def century_token(century)
        return "undated" if century.nil?

        century.negative? ? "bce#{-century}" : "ce#{century}"
      end

      def publishable?(license_class) = PUBLISHABLE_LICENSE_CLASSES.include?(license_class)

      def sorted_census(counts) = counts.sort_by { |key, _| key.to_s }.to_h

      def citations(registry, published_slugs)
        published_slugs.filter_map do |slug|
          entry = registry[slug]
          next nil if entry.nil?

          manifest = entry.manifest
          Citation.new(key: slug, type: "misc",
                       fields: { "title" => manifest.name, "howpublished" => manifest.upstream_url,
                                 "note" => "license: #{manifest.license}" })
        end
      end

      # A one-pass row stream CsvWriter.write can consume without the whole
      # table materialized in memory (lemma_rollup's gold slice runs to
      # hundreds of thousands of rows). #size is the published row count,
      # known only once the stream has been drained — asking earlier is a
      # programming error, never a silent zero.
      class Stream
        def initialize(&producer)
          @producer = producer
          @size = nil
        end

        def each(&)
          count = 0
          @producer.call do |row|
            count += 1
            yield row
          end
          @size = count
        end

        def size
          raise Error, "row stream size asked before the stream was drained" if @size.nil?

          @size
        end
      end
    end
  end
end
