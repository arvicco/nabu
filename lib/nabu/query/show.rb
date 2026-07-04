# frozen_string_literal: true

module Nabu
  module Query
    # `nabu show URN`: inspect a single passage or a whole document by urn.
    #
    # == Inspection tool, not a corpus view
    #
    # Unlike Search and Export (which honour the two-level visibility rule and
    # hide withdrawn rows), Show deliberately reveals withdrawn passages and
    # documents — flagged as such. A withdrawn row still EXISTS in the catalog
    # (nothing is ever hard-deleted, CLAUDE.md); `show` is the honest window
    # onto what the store actually holds, so an operator inspecting a specific
    # urn sees the truth, "withdrawn" label and all. Filtering belongs to the
    # corpus-facing commands, not the inspector.
    #
    # == Passage first, then document
    #
    # urns are globally unique across both tables, and a passage urn never
    # equals its document's urn, so we probe passages first (the common case:
    # a citation points at a line/section) and fall back to documents. Unknown
    # urn → nil (the CLI turns that into "urn not found", exit 1).
    #
    # Reads the catalog through raw datasets (like Search/Indexer) so it never
    # depends on whichever db the global Store models are bound to.
    class Show
      # One provenance journal entry (architecture §5), chronological.
      ProvenanceEvent = Data.define(:event, :tool, :at)

      # A passage in the context of its document + source, with the effective
      # license class (override coalesced over source class) and its full
      # provenance trail.
      PassageResult = Data.define(
        :urn, :language, :sequence, :revision, :withdrawn, :text,
        :document_urn, :document_title, :source_slug, :license_class, :provenance
      )

      # One line of a document listing: a passage's urn and text, in sequence.
      PassageLine = Data.define(:urn, :text, :withdrawn)

      # A document header plus its passages in sequence order.
      # retired_upstream (P5-2): upstream scrapped the canonical file, the
      # attic kept it — the document is live, labeled honestly.
      DocumentResult = Data.define(
        :urn, :title, :language, :source_slug, :license_class,
        :revision, :withdrawn, :retired_upstream, :passages
      )

      def initialize(catalog:)
        @catalog = catalog
      end

      # Resolve +urn+ to a PassageResult, a DocumentResult, or nil.
      def run(urn)
        passage(urn) || document(urn)
      end

      private

      def passage(urn)
        row = @catalog[:passages]
              .join(:documents, id: Sequel[:passages][:document_id])
              .join(:sources, id: Sequel[:documents][:source_id])
              .where(Sequel[:passages][:urn] => urn)
              .select(*passage_columns)
              .first
        return nil if row.nil?

        build_passage(row)
      end

      def document(urn)
        row = @catalog[:documents]
              .join(:sources, id: Sequel[:documents][:source_id])
              .where(Sequel[:documents][:urn] => urn)
              .select(*document_columns)
              .first
        return nil if row.nil?

        build_document(row)
      end

      def build_passage(row)
        PassageResult.new(
          urn: row.fetch(:urn), language: row.fetch(:language),
          sequence: row.fetch(:sequence), revision: row.fetch(:revision),
          withdrawn: truthy?(row.fetch(:withdrawn)), text: row.fetch(:text),
          document_urn: row.fetch(:document_urn), document_title: row.fetch(:document_title),
          source_slug: row.fetch(:source_slug), license_class: row.fetch(:license_class),
          provenance: provenance_events(row.fetch(:passage_id))
        )
      end

      def build_document(row)
        DocumentResult.new(
          urn: row.fetch(:urn), title: row.fetch(:title), language: row.fetch(:language),
          source_slug: row.fetch(:source_slug), license_class: row.fetch(:license_class),
          revision: row.fetch(:revision), withdrawn: truthy?(row.fetch(:withdrawn)),
          retired_upstream: truthy?(row.fetch(:retired_upstream)),
          passages: document_passages(row.fetch(:document_id))
        )
      end

      # Chronological provenance for a passage: order by time, id as tiebreak
      # so events written in the same tick keep their insertion order.
      def provenance_events(passage_id)
        @catalog[:provenance]
          .where(passage_id: passage_id)
          .order(:at, :id)
          .select(:event, :tool, :at)
          .map { |r| ProvenanceEvent.new(event: r.fetch(:event), tool: r.fetch(:tool), at: r.fetch(:at)) }
      end

      def document_passages(document_id)
        @catalog[:passages]
          .where(document_id: document_id)
          .order(:sequence)
          .select(:urn, :text, :withdrawn)
          .map do |r|
            PassageLine.new(urn: r.fetch(:urn), text: r.fetch(:text),
                            withdrawn: truthy?(r.fetch(:withdrawn)))
          end
      end

      # Effective license class: document override wins over source class (P1-3).
      def license_expr
        Sequel.function(:coalesce,
                        Sequel[:documents][:license_override],
                        Sequel[:sources][:license_class])
      end

      def passage_columns
        [
          Sequel[:passages][:id].as(:passage_id),
          Sequel[:passages][:urn],
          Sequel[:passages][:language],
          Sequel[:passages][:sequence],
          Sequel[:passages][:revision],
          Sequel[:passages][:withdrawn],
          Sequel[:passages][:text],
          Sequel[:documents][:urn].as(:document_urn),
          Sequel[:documents][:title].as(:document_title),
          Sequel[:sources][:slug].as(:source_slug),
          license_expr.as(:license_class)
        ]
      end

      def document_columns
        [
          Sequel[:documents][:id].as(:document_id),
          Sequel[:documents][:urn],
          Sequel[:documents][:title],
          Sequel[:documents][:language],
          Sequel[:documents][:revision],
          Sequel[:documents][:withdrawn],
          Sequel[:documents][:retired_upstream],
          Sequel[:sources][:slug].as(:source_slug),
          license_expr.as(:license_class)
        ]
      end

      # SQLite stores booleans as 0/1; normalize back to true/false so the
      # value objects carry real booleans regardless of the driver's typecast.
      def truthy?(value)
        [true, 1].include?(value)
      end
    end
  end
end
