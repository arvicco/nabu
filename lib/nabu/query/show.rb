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
      # +credit+ (P43-2): the source's optional attribution line (nil on every
      # ordinary source), rendered on the card only when present.
      # +findspot+ (P44-2): the document's captured Pleiades id resolved
      # through the gazetteer dump, nil whenever anything is missing.
      PassageResult = Data.define(
        :urn, :language, :sequence, :revision, :withdrawn, :text,
        :document_urn, :document_title, :source_slug, :license_class, :provenance, :timeline,
        :annotations, :credit, :meter, :findspot
      ) do
        def initialize(timeline: nil, annotations: {}, credit: nil, meter: nil, findspot: nil, **) = super
      end

      # The findspot line's facts (P44-2): the captured Pleiades id resolved
      # through the local gazetteer dump — title + place types, nothing more
      # (maps and coordinate math are out by design). Rendered ONLY when the
      # document's parse-captured metadata carries $.place.pleiades AND the
      # dump is on disk AND it holds the id; nil otherwise, so a corpus
      # without the dump renders byte-identically (the LiLa precedent).
      Findspot = Data.define(:id, :title, :place_types)

      # A meter enrichment attached to a passage (P44-7): the metrical code
      # ("H" hexameter, "P" pentameter, …), the dactyl/spondee foot +pattern+,
      # and +producer+ (the enrichments row's model — "pedecerto"). nil when the
      # passage carries no scansion (every ordinary passage).
      Meter = Data.define(:meter, :pattern, :producer)

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
        :revision, :withdrawn, :retired_upstream, :passages, :timeline, :facets, :credit, :findspot
      ) do
        def initialize(timeline: nil, facets: [], credit: nil, findspot: nil, **) = super
      end

      # A range (P7-6): the document header, the inclusive slice of passages,
      # the two endpoint urns, and total (M) so the CLI can print the honest
      # "[N of M passages]" note. Shaped like DocumentResult so the CLI's
      # passage_label reuse (it reads +urn+ + +passages+) works unchanged.
      RangeResult = Data.define(
        :urn, :title, :language, :source_slug, :license_class, :revision,
        :withdrawn, :retired_upstream, :passages, :total, :start_urn, :end_urn, :timeline, :credit
      ) do
        def initialize(timeline: nil, credit: nil, **) = super
      end

      # +pleiades+ (P44-2): nil (default — note_shelf/mcp callers stay
      # byte-identical), a loaded Nabu::Pleiades resolver (tests), or :auto —
      # the CLI's setting, which feature-detects the canonical dump LAZILY:
      # nothing loads until a shown document actually carries a captured
      # $.place.pleiades id, and then once per Show instance (~3 s /
      # ~3.9 GB peak RSS on the real dump — the P44-2 design datum, the
      # accepted v1 cost of dumping-without-an-index).
      def initialize(catalog:, pleiades: nil)
        @catalog = catalog
        @pleiades = pleiades
      end

      # Resolve +urn+ to a PassageResult, a DocumentResult, a RangeResult, or
      # nil. Literal-first: a real passage/document wins before a range is even
      # attempted (a passage urn holding a hyphen is never misparsed as one).
      # A range with a bad endpoint raises Range::Error (CLI → exit 1).
      # Last, a CITATION PREFIX (P44, owner test-drive friction: a shortened
      # urn between document and passage grain — …:avest020:Y.19.1 over
      # passages Y.19.1.a/b — used to be "urn not found") lists everything
      # below it, boundary-exact, through the RangeResult shape.
      def run(urn)
        return dictionary_entry(urn) if urn.start_with?(DICT_URN_PREFIX)

        passage(urn) || document(urn) || range(urn) || citation_prefix(urn)
      end

      # `define` prints minted dictionary-entry urns on every headline; show
      # resolves them to the same Define::Result the define renderers already
      # speak (P22-2). +fulltext+ was never Show's dependency, so reflex
      # attested-counts read nil here — an honest absence, not a zero.
      DICT_URN_PREFIX = "urn:nabu:dict:"

      # Marker key set in +annotations+ when the stored annotations_json
      # failed to parse (see #parse_annotations) — a reserved name, never
      # minted by any adapter.
      ANNOTATIONS_UNREADABLE = "annotations_unreadable"

      def dictionary_entry(urn)
        return nil unless @catalog.table_exists?(:dictionary_entries)

        Define.new(catalog: @catalog).by_urn(urn)
      end

      private

      # The citation-prefix listing (P44). The prefix's document is found by
      # probing ever-shorter ":"-bounded heads of +urn+ against the documents
      # table (document urns may themselves contain ":" — urn:cts:… — so the
      # probe walks colon positions right-to-left; each probe is one indexed
      # lookup). The children are the document's passages whose urns extend
      # the full prefix across a CITATION BOUNDARY — ".", ":" or the P43-i2
      # occurrence "#" — so Y.19.1 opens into Y.19.1.a/b and never swallows
      # Y.19.10. Zero children stays nil: "urn not found", honestly.
      def citation_prefix(urn)
        document_row, = resolve_prefix_document(urn)
        return nil if document_row.nil?

        escaped = urn.gsub(/[\\%_]/) { |ch| "\\#{ch}" }
        # No withdrawn filter: Show is the honest inspector (class doctrine) —
        # withdrawn children list flagged, exactly like a document listing.
        matches = @catalog[:passages]
                  .where(document_id: document_row.fetch(:id))
                  .where(
                    Sequel.|(*%w[. : #].map { |b| Sequel.like(:urn, "#{escaped}#{b}%", { escape: "\\" }) })
                  )
                  .order(:sequence)
                  .select(:urn, :text, :withdrawn, :annotations_json)
                  .all
        return nil if matches.empty?

        build_prefix_result(document_row, matches)
      end

      # The longest document whose urn is a ":"-bounded proper prefix of
      # +urn+, or nil. Walks the colon positions right-to-left — a handful of
      # indexed point lookups, never a scan.
      def resolve_prefix_document(urn)
        head = urn.dup
        while (cut = head.rindex(":"))
          head = head[0...cut]
          row = @catalog[:documents]
                .join(:sources, id: Sequel[:documents][:source_id])
                .where(Sequel[:documents][:urn] => head)
                .select(*document_columns, Sequel[:documents][:id])
                .first
          return [row, head] if row
        end
        nil
      end

      def build_prefix_result(header, rows)
        total = @catalog[:passages].where(document_id: header.fetch(:id)).count
        RangeResult.new(
          urn: header.fetch(:urn), title: header.fetch(:title), language: header.fetch(:language),
          source_slug: header.fetch(:source_slug), license_class: header.fetch(:license_class),
          revision: header.fetch(:revision), withdrawn: truthy?(header.fetch(:withdrawn)),
          retired_upstream: truthy?(header.fetch(:retired_upstream)),
          passages: rows.map { |row| passage_line(row) }, total: total,
          start_urn: rows.first.fetch(:urn), end_urn: rows.last.fetch(:urn),
          timeline: timeline_for(header.fetch(:id)), credit: header.fetch(:credit)
        )
      end

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
          timeline: timeline_for(slice.document_id), credit: header.fetch(:credit)
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
          annotations: parse_annotations(row),
          credit: row.fetch(:credit),
          meter: meter_for(row.fetch(:passage_id)),
          findspot: findspot_for(row)
        )
      end

      # The passage's meter enrichment (P44-7), or nil when it carries none —
      # the seam proving a consumer reads the enrichments layer. One row per
      # passage per producer; the first (by id) is rendered. Degrades to nil on
      # a catalog predating the enrichments table or on unreadable payload JSON,
      # never crashes (the facets_for/timeline_for stance).
      def meter_for(passage_id)
        return nil unless @catalog.table_exists?(:enrichments)

        row = @catalog[:enrichments]
              .where(passage_id: passage_id, kind: "meter")
              .order(:id)
              .select(:model, :payload_json)
              .first
        return nil if row.nil?

        payload = JSON.parse(row[:payload_json].to_s)
        Meter.new(meter: payload["meter"], pattern: payload["pattern"], producer: row[:model])
      rescue JSON::ParserError
        nil
      end

      def build_document(row)
        DocumentResult.new(
          urn: row.fetch(:urn), title: row.fetch(:title), language: row.fetch(:language),
          source_slug: row.fetch(:source_slug), license_class: row.fetch(:license_class),
          revision: row.fetch(:revision), withdrawn: truthy?(row.fetch(:withdrawn)),
          retired_upstream: truthy?(row.fetch(:retired_upstream)),
          passages: document_passages(row.fetch(:document_id)),
          timeline: timeline_for(row.fetch(:document_id)),
          facets: facets_for(row.fetch(:document_id)), credit: row.fetch(:credit),
          findspot: findspot_for(row)
        )
      end

      # The findspot facts (P44-2), or nil — no captured id, no resolver
      # (dump absent), or an id the dump lacks all degrade silently (the
      # facets_for/timeline_for stance; class Findspot note).
      def findspot_for(row)
        id = captured_place_id(row[:document_metadata_json])
        return nil if id.nil?

        place = pleiades&.place(id)
        place && Findspot.new(id: place.id, title: place.title, place_types: place.place_types)
      end

      # The parse-captured $.place.pleiades id out of documents.metadata_json
      # (the P44-2 cross-source key), nil on absence or unreadable JSON. The
      # place key is not shape-owned by the epigraphy sources — croala mints
      # "place":"Split" (a plain teiHeader string) — so anything but the
      # {"pleiades" => id} hash is simply not a captured id (P44-i4).
      def captured_place_id(json)
        return nil if json.nil? || json.empty?

        parsed = JSON.parse(json)
        place = parsed.is_a?(Hash) ? parsed["place"] : nil
        id = place.is_a?(Hash) ? place["pleiades"] : nil
        id.is_a?(String) && !id.empty? ? id : nil
      rescue JSON::ParserError
        nil
      end

      # Feature-detect + memoize the resolver (initialize note). :auto loads
      # it from canonical/pleiades; an absent dump is nil, and the load only
      # ever happens when a captured id needs resolving.
      def pleiades
        return @pleiades unless @pleiades == :auto

        @pleiades = Nabu::Pleiades.load_default
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
      # Hash; {} on absent — an honest nothing. Unparseable JSON is NOT
      # nothing (H9, P35-6): the annotation lane exists but cannot be read,
      # so the hash carries the ANNOTATIONS_UNREADABLE marker instead of
      # masquerading as an unannotated passage — renderers say so (the
      # skip-with-note rule, the P34-r0/r1 precedent) while inspectors that
      # dig real keys (token coloring, qere) still degrade, never crash.
      def parse_annotations(row)
        json = row[:annotations_json]
        return {} if json.nil? || json.empty?

        parsed = JSON.parse(json)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        { ANNOTATIONS_UNREADABLE => true }
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
          Sequel[:documents][:metadata_json].as(:document_metadata_json),
          Sequel[:sources][:slug].as(:source_slug),
          license_expr.as(:license_class),
          Sequel[:sources][:credit].as(:credit)
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
          Sequel[:documents][:metadata_json].as(:document_metadata_json),
          Sequel[:sources][:slug].as(:source_slug),
          license_expr.as(:license_class),
          Sequel[:sources][:credit].as(:credit)
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
