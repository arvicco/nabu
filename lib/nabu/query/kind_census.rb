# frozen_string_literal: true

module Nabu
  module Query
    # The kind axis' browse view (P99-3 — №R-63): head-grain class
    # counts, the honesty buckets (unmapped / unknown) counted beside —
    # never inside — the classes, and the unclassified remainder
    # announced (sources carrying nothing genre-shaped speak through
    # their postures, not through silence).
    #
    # Reads PRECOMPILED data only (the desk-commands law): the board
    # comes from kind_stats (per-source per-head distinct-doc counts,
    # written by KindBuilder in the projection pass — migration 032) and
    # the library totals from source_stats; grouping the millions of
    # kind facet rows at ask time is exactly what this design refuses.
    # The one exception is the --unmapped worklist, which needs raw-value
    # detail and queries only the unmapped subset. A catalog predating
    # migration 032 returns nil — the CLI renders the honest hint.
    class KindCensus
      ClassRow = Data.define(:head, :documents, :sources)
      UnmappedRow = Data.define(:slug, :raw, :documents)
      Report = Data.define(:classes, :unmapped_documents, :unknown_documents,
                           :classified_documents, :unclassified_documents,
                           :unclassified_sources, :seconds)

      BUCKETS = %w[unmapped unknown].freeze
      FACET = Store::KindBuilder::FACET

      def initialize(catalog:)
        @catalog = catalog
      end

      def run
        return nil unless @catalog.table_exists?(:kind_stats)

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        buckets, classes = head_rows.partition { |row| BUCKETS.include?(row.head) }
        classified = @catalog[:kind_stats].where(head: nil).sum(:documents) || 0
        live = live_documents
        classified_source_ids = @catalog[:kind_stats].distinct.select_map(:source_id)
        Report.new(
          classes: classes,
          unmapped_documents: buckets.find { |b| b.head == "unmapped" }&.documents || 0,
          unknown_documents: buckets.find { |b| b.head == "unknown" }&.documents || 0,
          classified_documents: classified,
          unclassified_documents: [live - classified, 0].max,
          unclassified_sources: unclassified_sources(classified_source_ids),
          seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        )
      end

      # The curation worklist: every raw value that fell into the
      # unmapped bucket, by document count per source, largest first.
      # Queries the unmapped subset only — bounded by the bucket size.
      def unmapped_worklist
        dataset = @catalog[:document_facets]
                  .where(facet: FACET, value: "unmapped")
                  .join(:documents, id: :document_id)
                  .join(:sources, id: Sequel[:documents][:source_id])
                  .group(Sequel[:sources][:slug], Sequel[:document_facets][:raw])
                  .select(Sequel[:sources][:slug].as(:slug),
                          Sequel[:document_facets][:raw].as(:raw),
                          distinct_count(Sequel[:document_facets][:document_id]).as(:docs))
                  .order(Sequel.desc(:docs), :slug)
        dataset.map { |row| UnmappedRow.new(slug: row[:slug], raw: row[:raw], documents: row[:docs]) }
      end

      private

      # Head families over the precompiled stats: per-source distinct
      # counts are additive across sources (a document has one source),
      # and the source spread is the row count per head.
      def head_rows
        dataset = @catalog[:kind_stats]
                  .exclude(head: nil)
                  .group(:head)
                  .select(:head,
                          Sequel.function(:sum, :documents).as(:docs),
                          Sequel.function(:count, :source_id).as(:sources))
                  .order(Sequel.desc(:docs), :head)
        dataset.map { |row| ClassRow.new(head: row[:head], documents: row[:docs], sources: row[:sources]) }
      end

      # Library-wide live-document total from source_stats (precompiled
      # at every sync/rebuild — the stats_drift invariant watches it).
      def live_documents
        return 0 unless @catalog.table_exists?(:source_stats)

        @catalog[:source_stats].sum(:live_documents) || 0
      end

      def unclassified_sources(classified_source_ids)
        return 0 unless @catalog.table_exists?(:source_stats)

        @catalog[:source_stats]
          .where(Sequel[:live_documents] > 0) # rubocop:disable Style/NumericPredicate -- SQL expression, not Ruby arithmetic
          .exclude(source_id: classified_source_ids)
          .count
      end

      def distinct_count(column)
        Sequel.function(:count, Sequel.function(:distinct, column))
      end
    end
  end
end
