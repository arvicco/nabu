# frozen_string_literal: true

require "json"

require_relative "define"
require_relative "range"

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

      # The document's timeline (P15-2), when it has one — shown by
      # `show` under the document/passage header. Signed historical years
      # (negative = BCE); either bound may be nil (open-ended). nil when the
      # document is undated (an absence, honestly blank).
      Timeline = Data.define(:not_before, :not_after, :precision, :date_raw,
                             :place_name, :place_ref, :axis_source)

      # A passage in the context of its document + source, with the effective
      # license class (override coalesced over source class), its full
      # provenance trail, and the document's timeline (nil when undated).
      # +annotations+ (P27-1): the stored annotations_json parsed back — the
      # display layer's edition context (ketiv/qere word hashes ride there).
      PassageResult = Data.define(
        :urn, :language, :sequence, :revision, :withdrawn, :text,
        :document_urn, :document_title, :source_slug, :license_class, :provenance, :timeline,
        :annotations
      ) do
        def initialize(timeline: nil, annotations: {}, **) = super
      end

      # One line of a document listing: a passage's urn and text, in sequence
      # (+annotations+ for the display layer's edition context, P27-1).
      PassageLine = Data.define(:urn, :text, :withdrawn, :annotations) do
        def initialize(annotations: {}, **) = super
      end

      # One facet fact (P17-2): "genre" => "epitaph", raw "titsep?" — shown
      # by `show` in one compact line under the document header.
      Facet = Data.define(:facet, :value, :raw)

      # A document header plus its passages in sequence order.
      # retired_upstream (P5-2): upstream scrapped the canonical file, the
      # attic kept it — the document is live, labeled honestly. +facets+
      # (P17-2): the document's facet rows, [] when unfaceted.
      DocumentResult = Data.define(
        :urn, :title, :language, :source_slug, :license_class,
        :revision, :withdrawn, :retired_upstream, :passages, :timeline, :facets
      ) do
        def initialize(timeline: nil, facets: [], **) = super
      end

      # A range (P7-6): the document header, the inclusive slice of passages,
      # the two endpoint urns, and total (M) so the CLI can print the honest
      # "[N of M passages]" note. Shaped like DocumentResult so the CLI's
      # passage_label reuse (it reads +urn+ + +passages+) works unchanged.
      RangeResult = Data.define(
        :urn, :title, :language, :source_slug, :license_class, :revision,
        :withdrawn, :retired_upstream, :passages, :total, :start_urn, :end_urn, :timeline
      ) do
        def initialize(timeline: nil, **) = super
      end

      def initialize(catalog:)
        @catalog = catalog
      end

      # Resolve +urn+ to a PassageResult, a DocumentResult, a RangeResult, or
      # nil. Literal-first: a real passage/document wins before a range is even
      # attempted (a passage urn holding a hyphen is never misparsed as one).
      # A range with a bad endpoint raises Range::Error (CLI → exit 1).
      def run(urn)
        return dictionary_entry(urn) if urn.start_with?(DICT_URN_PREFIX)

        passage(urn) || document(urn) || range(urn)
      end

      # `define` prints minted dictionary-entry urns on every headline; show
      # resolves them to the same Define::Result the define renderers already
      # speak (P22-2). +fulltext+ was never Show's dependency, so reflex
      # attested-counts read nil here — an honest absence, not a zero.
      DICT_URN_PREFIX = "urn:nabu:dict:"

      def dictionary_entry(urn)
        return nil unless @catalog.table_exists?(:dictionary_entries)

        Define.new(catalog: @catalog).by_urn(urn)
      end

      private

      # nil when +urn+ is not a range; otherwise the document header plus the
      # inclusive slice. Delegates the parse/precedence to Query::Range.
      def range(urn)
        slice = Range.new(catalog: @catalog).resolve(urn)
        return nil if slice.nil?

        header = @catalog[:documents]
                 .join(:sources, id: Sequel[:documents][:source_id])
                 .where(Sequel[:documents][:id] => slice.document_id)
                 .select(*document_columns)
                 .first
        build_range(header, slice)
      end

      def build_range(header, slice)
        RangeResult.new(
          urn: header.fetch(:urn), title: header.fetch(:title), language: header.fetch(:language),
          source_slug: header.fetch(:source_slug), license_class: header.fetch(:license_class),
          revision: header.fetch(:revision), withdrawn: truthy?(header.fetch(:withdrawn)),
          retired_upstream: truthy?(header.fetch(:retired_upstream)),
          passages: slice_passages(slice), total: slice.total,
          start_urn: slice.start_urn, end_urn: slice.end_urn,
          timeline: timeline_for(slice.document_id)
        )
      end

      # The inclusive [start_seq, end_seq] slice, in sequence order.
      def slice_passages(slice)
        @catalog[:passages]
          .where(document_id: slice.document_id)
          .where(sequence: slice.start_seq..slice.end_seq)
          .order(:sequence)
          .select(:urn, :text, :withdrawn, :annotations_json)
          .map { |r| passage_line(r) }
      end

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
          provenance: provenance_events(row.fetch(:passage_id)),
          timeline: timeline_for(row.fetch(:document_id)),
          annotations: parse_annotations(row)
        )
      end

      def build_document(row)
        DocumentResult.new(
          urn: row.fetch(:urn), title: row.fetch(:title), language: row.fetch(:language),
          source_slug: row.fetch(:source_slug), license_class: row.fetch(:license_class),
          revision: row.fetch(:revision), withdrawn: truthy?(row.fetch(:withdrawn)),
          retired_upstream: truthy?(row.fetch(:retired_upstream)),
          passages: document_passages(row.fetch(:document_id)),
          timeline: timeline_for(row.fetch(:document_id)),
          facets: facets_for(row.fetch(:document_id))
        )
      end

      # The document's facet rows (P17-2), [] when unfaceted or when the
      # catalog predates migration 009 — degrade, never crash (timeline_for's
      # stance). Ordered by facet name for a stable render.
      def facets_for(document_id)
        return [] unless @catalog.table_exists?(:document_facets)

        @catalog[:document_facets]
          .where(document_id: document_id)
          .order(:facet, :id)
          .select(:facet, :value, :raw)
          .map { |r| Facet.new(facet: r.fetch(:facet), value: r.fetch(:value), raw: r[:raw]) }
      end

      # The document's timeline (P15-2), or nil when undated. A document
      # may carry several timeline rows (Part 2's chronicle annals); `show` renders
      # the primary (earliest not_before) one — document-grain rows are a single
      # row today. `document_axes` may be absent from a catalog that predates
      # migration 008 (never rebuilt): degrade to nil, never crash.
      def timeline_for(document_id)
        return nil unless @catalog.table_exists?(:document_axes)

        row = @catalog[:document_axes].where(document_id: document_id)
                                      .order(Sequel.function(:coalesce, :not_before, :not_after)).first
        return nil if row.nil?

        Timeline.new(
          not_before: row[:not_before], not_after: row[:not_after], precision: row[:precision],
          date_raw: row[:date_raw], place_name: row[:place_name], place_ref: row[:place_ref],
          axis_source: row[:axis_source]
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
          .select(:urn, :text, :withdrawn, :annotations_json)
          .map { |r| passage_line(r) }
      end

      def passage_line(row)
        PassageLine.new(urn: row.fetch(:urn), text: row.fetch(:text),
                        withdrawn: truthy?(row.fetch(:withdrawn)),
                        annotations: parse_annotations(row))
      end

      # The stored annotations hash (P27-1/P27-2 union): row JSON back to a
      # Hash; {} on absent or unparseable — render-time inspectors (token
      # coloring, qere) degrade, never crash.
      def parse_annotations(row)
        json = row[:annotations_json]
        return {} if json.nil? || json.empty?

        parsed = JSON.parse(json)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
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
          Sequel[:documents][:id].as(:document_id),
          Sequel[:passages][:urn],
          Sequel[:passages][:language],
          Sequel[:passages][:sequence],
          Sequel[:passages][:revision],
          Sequel[:passages][:withdrawn],
          Sequel[:passages][:text],
          Sequel[:passages][:annotations_json],
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
