# frozen_string_literal: true

require_relative "../query/catalog_join"
require_relative "types"
require_relative "axes"

module Nabu
  module Export
    # `nabu export links` (P121-1): the edge dump of the links journal
    # (db/links.sqlite3, architecture §15) — one row per edge with its
    # producer run's provenance, each endpoint resolved through the catalog
    # to its source slug and effective license class. Resolution walks the
    # Query::Links grains in order — passage urn, then document urn, then
    # dictionary-entry urn — and an endpoint none of them answers stays
    # NULL (edges are urn-keyed and outlive catalog rows; the edge is
    # journal truth). Withdrawn endpoints still resolve, as in `nabu links`.
    #
    # Each row draws on BOTH endpoints' sources, so under --license-class an
    # edge survives only when both classes are in the set, and an
    # unresolved endpoint (no class to vouch for) drops it. --dated adds
    # each endpoint document's primary date envelope (Axes class note).
    #
    # Two databases, no ATTACH (the CatalogJoin two-step): edges page out
    # of the journal by id keyset, and each page resolves its endpoint urns
    # with one batched catalog read per grain.
    class Links
      include Nabu::Query::CatalogJoin

      NAME = "links"
      SUMMARY = "One row per mined edge in the links journal: kind, endpoints, score, run provenance, and " \
                "each endpoint's source and license (with --dated, each endpoint's date envelope)"

      # const: keyset page — two urns per edge stay well under SQLite's variable cap
      PAGE_SIZE = 1_000

      COLUMNS = [
        Column.new(name: "kind", description: "edge kind (parallel, formula, cognate, reference, ...)"),
        Column.new(name: "from_urn", description: "the endpoint the producer's probe started from"),
        Column.new(name: "to_urn", description: "the endpoint it found"),
        Column.new(name: "score", description: "the producer's score, verbatim"),
        Column.new(name: "detail", description: "per-edge evidence (the formula gram, the cognate meet), if any"),
        Column.new(name: "run_id", description: "the journal run that minted or last refreshed the edge"),
        Column.new(name: "producer", description: "the batch producer of that run"),
        Column.new(name: "scope", description: "the scope that run mined"),
        Column.new(name: "code_version", description: "the producer's engine marker at that run"),
        Column.new(name: "from_source", description: "from endpoint's source slug; NULL when not in the catalog"),
        Column.new(name: "from_license_class", description: "from endpoint's effective license class"),
        Column.new(name: "to_source", description: "to endpoint's source slug; NULL when not in the catalog"),
        Column.new(name: "to_license_class", description: "to endpoint's effective license class")
      ].freeze

      DATED_COLUMNS = [
        Column.new(name: "from_not_before", description: "from endpoint document's envelope lower bound"),
        Column.new(name: "from_not_after", description: "from endpoint document's envelope upper bound"),
        Column.new(name: "from_date_class", description: "artifact, composition, edition or silver"),
        Column.new(name: "to_not_before", description: "to endpoint document's envelope lower bound"),
        Column.new(name: "to_not_after", description: "to endpoint document's envelope upper bound"),
        Column.new(name: "to_date_class", description: "artifact, composition, edition or silver")
      ].freeze

      Endpoint = Data.define(:source, :license_class, :document_id)
      UNRESOLVED = Endpoint.new(source: nil, license_class: nil, document_id: nil)

      def initialize(catalog:, journal:, kinds: nil, dated: false, page_size: PAGE_SIZE)
        @catalog = catalog
        @journal = journal
        kinds = Array(kinds).map(&:to_s).map(&:strip).reject(&:empty?).uniq
        @kinds = kinds.empty? ? nil : kinds
        @dated = dated
        @page_size = page_size
        @unresolved = 0
        @runs = {}
      end

      def columns = @dated ? COLUMNS + DATED_COLUMNS : COLUMNS

      def filters = { "kind" => @kinds, "dated" => @dated }

      def notes = { "unresolved_endpoints" => @unresolved, "journal_runs" => @runs.size }

      # +license_classes+ is enforced by the frame (both endpoints'
      # classes are known only after resolution).
      def each_row(license_classes: nil)
        _ = license_classes
        last = 0
        loop do
          page = edges.where(Sequel[:links][:id] > last).limit(@page_size).all
          break if page.empty?

          endpoints = resolve(page.flat_map { |edge| [edge[:from_urn], edge[:to_urn]] }.uniq)
          envelopes = @dated ? Axes.by_document(@catalog, endpoints.values.filter_map(&:document_id).uniq) : {}
          page.each { |edge| yield build(edge, endpoints, envelopes) }
          last = page.last[:id]
        end
      end

      private

      def edges
        links = Sequel[:links]
        runs = Sequel[:link_runs]
        dataset = @journal[:links].join(:link_runs, id: links[:run_id]).order(links[:id])
        dataset = dataset.where(links[:kind] => @kinds) if @kinds
        dataset.select(links[:id].as(:id), links[:kind].as(:kind), links[:from_urn].as(:from_urn),
                       links[:to_urn].as(:to_urn), links[:score].as(:score), detail_column,
                       links[:run_id].as(:run_id), runs[:producer].as(:producer), runs[:scope].as(:scope),
                       runs[:code_version].as(:code_version))
      end

      # A journal predating migration 002 has no detail column (a read-only
      # open never migrates) — read it as NULL.
      def detail_column
        return Sequel[:links][:detail].as(:detail) if @journal.schema(:links).any? { |name, _| name == :detail }

        Sequel.as(nil, :detail)
      end

      # { urn => Endpoint } — passage grain, then document, then dictionary entry.
      def resolve(urns)
        found = passage_endpoints(urns)
        rest = urns - found.keys
        found.merge!(document_endpoints(rest)) unless rest.empty?
        rest = urns - found.keys
        found.merge!(dictionary_endpoints(rest)) unless rest.empty?
        found
      end

      def passage_endpoints(urns)
        @catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                           .join(:sources, id: Sequel[:documents][:source_id])
                           .where(Sequel[:passages][:urn] => urns)
                           .select(Sequel[:passages][:urn].as(:urn), Sequel[:sources][:slug].as(:source),
                                   license_expr.as(:license_class), Sequel[:documents][:id].as(:document_id))
                           .to_hash(:urn).transform_values { |row| endpoint(row) }
      end

      def document_endpoints(urns)
        @catalog[:documents].join(:sources, id: Sequel[:documents][:source_id])
                            .where(Sequel[:documents][:urn] => urns)
                            .select(Sequel[:documents][:urn].as(:urn), Sequel[:sources][:slug].as(:source),
                                    license_expr.as(:license_class), Sequel[:documents][:id].as(:document_id))
                            .to_hash(:urn).transform_values { |row| endpoint(row) }
      end

      def dictionary_endpoints(urns)
        return {} unless @catalog.table_exists?(:dictionary_entries)

        @catalog[:dictionary_entries].join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
                                     .join(:sources, id: Sequel[:dictionaries][:source_id])
                                     .where(Sequel[:dictionary_entries][:urn] => urns)
                                     .select(Sequel[:dictionary_entries][:urn].as(:urn),
                                             Sequel[:sources][:slug].as(:source),
                                             Sequel[:sources][:license_class].as(:license_class))
                                     .to_hash(:urn).transform_values { |row| endpoint(row) }
      end

      def endpoint(row)
        Endpoint.new(source: row[:source], license_class: row[:license_class], document_id: row[:document_id])
      end

      def build(edge, endpoints, envelopes)
        from = endpoint_for(edge[:from_urn], endpoints)
        to = endpoint_for(edge[:to_urn], endpoints)
        @runs[edge[:run_id]] = true
        values = [edge[:kind], edge[:from_urn], edge[:to_urn], edge[:score], edge[:detail], edge[:run_id],
                  edge[:producer], edge[:scope], edge[:code_version],
                  from.source, from.license_class, to.source, to.license_class]
        values.concat(dated_values(from, envelopes) + dated_values(to, envelopes)) if @dated
        Row.new(values: values, draws: [[from.source, from.license_class], [to.source, to.license_class]])
      end

      def endpoint_for(urn, endpoints)
        endpoints.fetch(urn) do
          @unresolved += 1
          UNRESOLVED
        end
      end

      def dated_values(endpoint, envelopes)
        axes = envelopes.fetch(endpoint.document_id, Axes::EMPTY)
        [axes.not_before, axes.not_after, axes.date_class]
      end
    end
  end
end
