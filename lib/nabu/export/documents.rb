# frozen_string_literal: true

require_relative "../languages"
require_relative "types"
require_relative "axes"
require_relative "../lects"
require_relative "../query/catalog_join"
require_relative "../store/lect_facets"

module Nabu
  module Export
    # `nabu export documents` (P121-1): one row per live document. The
    # identity columns always ship; --with-axes adds the library axes —
    # the resolved lect and its held script, the artifact script, the date
    # envelope (Axes class note), the place, genre and kind — every one
    # NULL where the axis is absent for that document, never a guess.
    #
    # Visibility is the corpus rule: withdrawn documents never export;
    # retired-upstream ones do (they are part of the collection). The
    # license class is the EFFECTIVE one (document override over source
    # class — CatalogJoin's semantics). The year window is CatalogJoin's
    # NULL-aware overlap, so an export and a `search --from/--to` agree on
    # which documents a window holds.
    #
    # Rows stream in urn order by keyset paging (urn > last, the unique
    # urn index), with one batched read per page for passage counts, axes
    # and facets — constant memory at library scale. passage_count counts
    # live passages only; on the full library it is the expensive column
    # (an indexed pass over every passage row).
    class Documents
      include Nabu::Query::CatalogJoin

      NAME = "documents"
      SUMMARY = "One row per live document: identity, effective license, live passage count, and " \
                "(with --with-axes) the resolved lect, script, date envelope, place, genre and kind"

      # const: keyset page — one batched axis/facet/count read per page, well under SQLite's variable cap
      PAGE_SIZE = 1_000

      BASE_COLUMNS = [
        Column.new(name: "urn", description: "the document urn (stable across rebuilds)"),
        Column.new(name: "source", description: "source slug (config/sources.yml)"),
        Column.new(name: "language", description: "the stored language code, as the adapter emitted it"),
        Column.new(name: "title", description: "document title as stored"),
        Column.new(name: "license_class",
                   description: "effective license class — the document override when present, else the source's"),
        Column.new(name: "passage_count", description: "live (non-withdrawn) passages")
      ].freeze

      AXIS_COLUMNS = [
        Column.new(name: "lect",
                   description: "resolved lect id (journal ruling, source override, or codemap default; the bare " \
                                "code when none applies); NULL when the catalog never materialized lects"),
        Column.new(name: "lect_basis",
                   description: "provenance of a non-identity resolution (owner, rule:<id>, override:<slug>, " \
                                "codemap); NULL for identity"),
        Column.new(name: "script", description: "script of the text AS HELD — the lect id's ~script segment"),
        Column.new(name: "artifact_script",
                   description: "the original artifact's script where it differs from the held text"),
        Column.new(name: "not_before",
                   description: "envelope lower bound, signed historical year (BCE negative, no year 0); " \
                                "NULL = open-ended or undated"),
        Column.new(name: "not_after", description: "envelope upper bound, same convention"),
        Column.new(name: "date_precision", description: "the dating lane's precision marker, verbatim"),
        Column.new(name: "date_class",
                   description: "artifact (the source's own date of the object/witness), composition " \
                                "(the work's composition era), edition (a print year) or silver (a model/tool " \
                                "estimate, only where no upstream date exists)"),
        Column.new(name: "date_basis", description: "the extractor lane that minted the envelope (axis_source)"),
        Column.new(name: "date_raw", description: "the upstream dating string the envelope was normalized from"),
        Column.new(name: "place_name", description: "provenance place as the source names it"),
        Column.new(name: "place_ref", description: "gazetteer reference(s) the source asserts (Pleiades, TM, ...)"),
        Column.new(name: "place_lat", description: "source-asserted WGS84 latitude"),
        Column.new(name: "place_lon", description: "source-asserted WGS84 longitude"),
        Column.new(name: "genre", description: "genre facet value(s), sorted and |-joined"),
        Column.new(name: "kind", description: "kind facet path(s), sorted and |-joined")
      ].freeze

      FACETS = %w[lect genre kind].freeze

      # Validates every filter up front (a refusal names the fix): +sources+
      # must be catalog slugs, years follow the timeline convention.
      def initialize(catalog:, sources: nil, langs: nil, from: nil, to: nil, with_axes: false, page_size: PAGE_SIZE)
        @catalog = catalog
        @sources = presence(sources)
        @langs = presence(langs)
        @from = from
        @to = to
        @with_axes = with_axes
        @page_size = page_size
        validate!
        @lect_materialized = with_axes && catalog.table_exists?(:document_facets) &&
                             Nabu::Store::LectFacets.materialized?(catalog)
      end

      def columns = @with_axes ? BASE_COLUMNS + AXIS_COLUMNS : BASE_COLUMNS

      def filters
        { "source" => @sources, "language" => @langs, "from" => @from, "to" => @to,
          "with_axes" => @with_axes, "withdrawn" => "excluded" }
      end

      def notes
        @with_axes ? { "lect_materialized" => @lect_materialized } : {}
      end

      def each_row(license_classes: nil)
        dataset = scoped(license_classes)
        last = nil
        loop do
          page = (last ? dataset.where(Sequel[:documents][:urn] > last) : dataset).limit(@page_size).all
          break if page.empty?

          extras = page_extras(page.map { |row| row[:id] })
          page.each { |row| yield build(row, extras) }
          last = page.last[:urn]
        end
      end

      private

      def presence(list)
        list = Array(list).map(&:to_s).map(&:strip).reject(&:empty?).uniq
        list.empty? ? nil : list
      end

      def validate!
        validate_sources!
        [[@from, "--from"], [@to, "--to"]].each do |year, flag|
          raise Error, "date filter: there is no year 0 (#{flag}); 1 BCE is -1, 1 CE is 1" if year&.zero?
        end
        return unless @from && @to && @from > @to

        raise Error, "date filter: --from #{@from} is after --to #{@to} " \
                     "(BCE years are negative — 300 BCE is -300, so -300 comes before -30)"
      end

      def validate_sources!
        return unless @sources

        known = @catalog[:sources].order(:slug).select_map(:slug)
        unknown = @sources - known
        return if unknown.empty?

        raise Error, "unknown source #{unknown.first.inspect} — the catalog holds: #{known.join(', ')}"
      end

      def scoped(license_classes)
        documents = Sequel[:documents]
        dataset = @catalog[:documents].join(:sources, id: documents[:source_id]).where(documents[:withdrawn] => false)
        dataset = dataset.where(Sequel[:sources][:slug] => @sources) if @sources
        if @langs
          dataset = dataset.where(documents[:language] => @langs.flat_map do |code|
            Nabu::Languages.code_variants(code)
          end)
        end
        dataset = dataset.where(license_expr => license_classes) if license_classes
        dataset = dataset.where(timeline_exists(from: @from, to: @to, place: nil)) if @from || @to
        dataset.order(documents[:urn])
               .select(documents[:id].as(:id), documents[:urn].as(:urn), Sequel[:sources][:slug].as(:source),
                       documents[:language].as(:language), documents[:title].as(:title),
                       license_expr.as(:license_class))
      end

      # One batched read per concern for the page's ids.
      def page_extras(ids)
        counts = @catalog[:passages].where(document_id: ids, withdrawn: false)
                                    .group_and_count(:document_id).as_hash(:document_id, :count)
        return { counts: counts } unless @with_axes

        { counts: counts, axes: Axes.by_document(@catalog, ids), facets: facets_for(ids) }
      end

      # { document_id => { facet => [[value, raw], ...] } } for the page.
      def facets_for(ids)
        return {} unless @catalog.table_exists?(:document_facets)

        @catalog[:document_facets].where(document_id: ids, facet: FACETS)
                                  .order(:document_id, :facet, :value)
                                  .select(:document_id, :facet, :value, :raw).all
                                  .group_by { |row| row[:document_id] }
                                  .transform_values do |rows|
                                    rows.group_by { |row| row[:facet] }
                                        .transform_values { |group| group.map { |row| [row[:value], row[:raw]] } }
                                  end
      end

      def build(row, extras)
        values = [row[:urn], row[:source], row[:language], row[:title], row[:license_class],
                  extras[:counts].fetch(row[:id], 0)]
        values.concat(axis_values(row, extras)) if @with_axes
        Row.new(values: values, draws: [[row[:source], row[:license_class]]])
      end

      def axis_values(row, extras)
        facets = extras[:facets].fetch(row[:id], {})
        lect, basis = lect_for(row, facets)
        axes = extras[:axes].fetch(row[:id], Axes::EMPTY)
        [lect, basis, lect && Nabu::Lects.parse_id(lect)&.[](:script), axes.artifact_script,
         axes.not_before, axes.not_after, axes.precision, axes.date_class, axes.date_basis, axes.date_raw,
         axes.place_name, axes.place_ref, axes.place_lat, axes.place_lon,
         joined(facets["genre"]), joined(facets["kind"])]
      end

      # The materialized invariant (Store::LectFacets): a facet row is a
      # non-identity resolution; no row means the bare code resolves to
      # itself — true only once a materialization has run at all.
      def lect_for(row, facets)
        return [nil, nil] unless @lect_materialized

        value, raw = facets.fetch("lect", []).first
        value ? [value, raw] : [row[:language], nil]
      end

      def joined(pairs)
        values = Array(pairs).map(&:first).uniq.sort
        values.empty? ? nil : values.join("|")
      end
    end
  end
end
