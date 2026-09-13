# frozen_string_literal: true

module Nabu
  module Query
    # The kind axis' browse view (P99-3 — №R-63): head-grain class
    # counts over the derived facet="kind" rows, the honesty buckets
    # (unmapped / unknown) counted beside — never inside — the classes,
    # and the unclassified remainder announced (sources carrying nothing
    # genre-shaped speak through their postures, not through silence).
    # Indexed GROUP BY over document_facets + one join to documents for
    # the source spread — quasi-instant per the desk-commands law.
    class KindCensus
      ClassRow = Data.define(:head, :documents, :sources)
      UnmappedRow = Data.define(:slug, :raw, :documents)
      Report = Data.define(:classes, :unmapped_documents, :unknown_documents,
                           :classified_documents, :unclassified_documents,
                           :unclassified_sources, :seconds)

      BUCKETS = %w[unmapped unknown].freeze

      def initialize(catalog:)
        @catalog = catalog
      end

      def run
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rows = head_rows
        buckets, classes = rows.partition { |row| BUCKETS.include?(row.head) }
        classified = kind_facets.select(:document_id).distinct.count
        live = @catalog[:documents].where(withdrawn: false)
        Report.new(
          classes: classes,
          unmapped_documents: buckets.find { |b| b.head == "unmapped" }&.documents || 0,
          unknown_documents: buckets.find { |b| b.head == "unknown" }&.documents || 0,
          classified_documents: classified,
          unclassified_documents: live.count - classified,
          unclassified_sources: unclassified_sources(live),
          seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        )
      end

      # The curation worklist: every raw value that fell into the
      # unmapped bucket, by document count per source, largest first.
      def unmapped_worklist
        dataset = @catalog[:document_facets]
                  .where(facet: KindHead::FACET, value: "unmapped")
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

      def kind_facets
        @catalog[:document_facets].where(facet: KindHead::FACET)
      end

      # Head grain: "funerary/epitaph" and "funerary" fold into one
      # family row; distinct documents and sources counted in SQL so
      # multi-sub documents never double-count.
      def head_rows
        dataset = kind_facets
                  .join(:documents, id: :document_id)
                  .group(KindHead.expr)
                  .select(KindHead.expr.as(:head),
                          distinct_count(Sequel[:document_facets][:document_id]).as(:docs),
                          distinct_count(Sequel[:documents][:source_id]).as(:sources))
                  .order(Sequel.desc(:docs), :head)
        dataset.map { |row| ClassRow.new(head: row[:head], documents: row[:docs], sources: row[:sources]) }
      end

      # COUNT(DISTINCT column) as a plain expression (SQLite accepts the
      # parenthesized-DISTINCT rendering).
      def distinct_count(column)
        Sequel.function(:count, Sequel.function(:distinct, column))
      end

      def unclassified_sources(live)
        classified_sources = kind_facets.join(:documents, id: :document_id)
                                        .distinct.select(Sequel[:documents][:source_id])
        live.exclude(source_id: classified_sources).select(:source_id).distinct.count
      end
    end

    # The one head-extraction expression, shared by census and any
    # future kind surface: everything before the first "/" (SQLite
    # instr over value || '/').
    module KindHead
      FACET = "kind"

      def self.expr
        value = Sequel[:document_facets][:value]
        Sequel.function(:substr, value,
                        1,
                        Sequel.function(:instr, Sequel.join([value, "/"]), "/") - 1)
      end
    end
  end
end
