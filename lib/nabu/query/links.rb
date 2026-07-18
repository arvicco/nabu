# frozen_string_literal: true

require_relative "catalog_join"

module Nabu
  module Query
    # Reader for the links journal (P16-1, docs/intertext-design.md §7):
    # `nabu links <urn>` — every mined edge touching this urn, BOTH directions,
    # grouped by kind, each counterpart resolved through the catalog to its
    # document title/language/license. The urn is the join key on purpose:
    # edges are urn-keyed so they survive rebuilds, and this reader re-resolves
    # them against whatever catalog currently exists. A counterpart the catalog
    # no longer holds (withdrawn since the batch run, or a rebuild off a
    # slimmer canonical) resolves to nils and renders honestly as unresolved —
    # the edge itself is journal truth, not catalog truth.
    #
    # == Why an edge never renders twice (P18-3, the dedupe audit)
    #
    # The journal's unique (from_urn, to_urn, kind) index plus write_edge!'s
    # reverse-direction refresh keep AT MOST ONE row per unordered pair per
    # kind, and the out/in halves of this query could both return one row
    # only for a self-edge (from_urn = to_urn) — which no producer mints
    # (parallels excludes the anchor's own document, formula spokes fan out
    # of a hub distinct from every spoke, cognate pairs span two languages'
    # passages). So the kind groups are duplicate-free by construction.
    class Links
      include CatalogJoin

      # One edge as seen FROM the queried urn. +direction+ is :out (the batch
      # probe discovered the counterpart from this urn) or :in (some other
      # anchor's probe found this urn). +urn+ is the COUNTERPART; title/
      # language/license_class come from catalog resolution (nil when the
      # counterpart is no longer in the catalog). +detail+ is the per-edge
      # evidence (P16-2, migration 002): the formula gram, the cognate meet
      # (ref · root [shelf]); nil for parallel edges and journals predating
      # the column (a read-only open never migrates — missing key reads nil).
      Edge = Data.define(:direction, :urn, :title, :language, :license_class,
                         :score, :detail, :run_id) do
        def resolved? = !title.nil? || !language.nil?
      end

      # A producer run cited by at least one shown edge — the provenance line.
      RunInfo = Data.define(:id, :producer, :scope, :params, :code_version, :created_at)

      # +groups+ is { kind => [Edge] } (edges score-desc within a kind);
      # +runs+ the RunInfos the edges cite, id-ordered. +title+ is the queried
      # urn's own resolution (nil when it is not in the catalog — possible,
      # since edges outlive catalog rows).
      Result = Data.define(:urn, :title, :groups, :total, :runs)

      def initialize(catalog:, journal:)
        @catalog = catalog
        @journal = journal
      end

      # Edges touching +urn+. Returns nil when the urn is unknown BOTH ways —
      # no catalog passage/document and no edge (the caller errors); a known
      # urn with no edges returns an empty Result (a state, not an error).
      def run(urn)
        edges = outgoing(urn) + incoming(urn)
        title = resolve_own_title(urn)
        return nil if edges.empty? && title == :unknown

        resolved = resolve_counterparts(edges)
        groups = resolved.group_by { |edge| edge.fetch(:kind) }
                         .transform_values { |group| group.map { |edge| build_edge(edge) } }
        Result.new(urn: urn, title: (title unless title == :unknown),
                   groups: groups, total: resolved.size, runs: run_infos(resolved))
      end

      private

      def outgoing(urn)
        @journal[:links].where(from_urn: urn).all.each { |edge| edge[:direction] = :out }
      end

      def incoming(urn)
        @journal[:links].where(to_urn: urn).all.each { |edge| edge[:direction] = :in }
      end

      # The queried urn's own display title: its document's title whether the
      # urn names a passage or a document — or, third grain (P28-3), a
      # dictionary entry's "headword — dictionary" (the shelf's minted
      # urn:nabu:dict: urns are edge endpoints since P25-0; once the shelf
      # is INGESTED, "(not in catalog)" would be dishonest). :unknown when
      # the catalog holds none (distinct from a nil title on a known row).
      def resolve_own_title(urn)
        passage = @catalog[:passages]
                  .join(:documents, id: Sequel[:passages][:document_id])
                  .where(Sequel[:passages][:urn] => urn)
                  .select(Sequel[:documents][:title].as(:title)).first
        return passage[:title] if passage

        document = @catalog[:documents].where(urn: urn).select(:title).first
        return document[:title] if document

        entry = dictionary_resolutions([urn])[urn]
        entry ? entry[:title] : :unknown
      end

      # One catalog query resolves every counterpart urn to title/language/
      # license (no withdrawn filter: a withdrawn counterpart still resolves —
      # the edge exists; `show` tells the withdrawal story). Urns no passage
      # answers for are retried at DOCUMENT grain (P19-4: reference edges
      # point at whole documents — a local-library article, a discussed
      # edition — not only passages); only then does an edge render
      # "(not in catalog)".
      def resolve_counterparts(edges)
        urns = edges.map { |edge| counterpart(edge) }.uniq
        rows = passage_resolutions(urns)
        unresolved = urns - rows.keys
        rows = rows.merge(document_resolutions(unresolved)) unless unresolved.empty?
        unresolved = urns - rows.keys
        rows = rows.merge(dictionary_resolutions(unresolved)) unless unresolved.empty?
        edges.map { |edge| edge.merge(resolution: rows[counterpart(edge)]) }
             .sort_by { |edge| [-(edge[:score] || 0.0), counterpart(edge)] }
      end

      def passage_resolutions(urns)
        @catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:urn] => urns)
          .select(Sequel[:passages][:urn].as(:urn),
                  Sequel[:passages][:language].as(:language),
                  Sequel[:documents][:title].as(:title),
                  license_expr.as(:license_class))
          .to_hash(:urn)
      end

      def document_resolutions(urns)
        @catalog[:documents]
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:documents][:urn] => urns)
          .select(Sequel[:documents][:urn].as(:urn),
                  Sequel[:documents][:language].as(:language),
                  Sequel[:documents][:title].as(:title),
                  license_expr.as(:license_class))
          .to_hash(:urn)
      end

      # The dictionary-entry grain (P28-3): an INGESTED shelf's
      # urn:nabu:dict: urns resolve to "headword — dictionary title" with
      # the shelf's language and its source's license class; urns of
      # shelves not (yet) ingested — eDIL, the AED/demotic siblings —
      # still fall through to "(not in catalog)", honestly. Guarded for
      # pre-shelf catalogs (the read path opens whatever file exists).
      def dictionary_resolutions(urns)
        return {} unless @catalog.table_exists?(:dictionary_entries)

        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .join(:sources, id: Sequel[:dictionaries][:source_id])
          .where(Sequel[:dictionary_entries][:urn] => urns)
          .select(Sequel[:dictionary_entries][:urn].as(:urn),
                  Sequel[:dictionary_entries][:headword].as(:headword),
                  Sequel[:dictionaries][:title].as(:dictionary_title),
                  Sequel[:dictionaries][:language].as(:language),
                  Sequel[:sources][:license_class].as(:license_class))
          .to_hash(:urn)
          .transform_values do |row|
            { urn: row[:urn], title: "#{row[:headword]} — #{row[:dictionary_title]}",
              language: row[:language], license_class: row[:license_class] }
          end
      end

      def counterpart(edge)
        edge[:direction] == :out ? edge[:to_urn] : edge[:from_urn]
      end

      def build_edge(edge)
        resolution = edge[:resolution] || {}
        Edge.new(direction: edge[:direction], urn: counterpart(edge),
                 title: resolution[:title], language: resolution[:language],
                 license_class: resolution[:license_class],
                 score: edge[:score], detail: edge[:detail], run_id: edge[:run_id])
      end

      def run_infos(edges)
        ids = edges.map { |edge| edge[:run_id] }.uniq
        @journal[:link_runs].where(id: ids).order(:id).all.map do |row|
          RunInfo.new(id: row[:id], producer: row[:producer], scope: row[:scope],
                      params: JSON.parse(row[:params_json]), code_version: row[:code_version],
                      created_at: row[:created_at])
        end
      end
    end
  end
end
