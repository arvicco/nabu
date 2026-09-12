# frozen_string_literal: true

module Nabu
  # The place-mine review surface (P97-1 — Q70): aggregate the journal's
  # kind=place-candidate edges into reviewable rows — one row per PLACE,
  # ranked by document spread (how many distinct held documents attest
  # the place: spread separates real geography from one chatty text),
  # title resolved through the gazetteer's derived place-index slice,
  # each row carrying its evidence (matched names with counts, sample
  # passage urns) and the two exits the review-fuel doctrine ends in:
  # the ready-to-paste config/place_stop_names.yml line for a name that
  # is a common word wearing a place's clothes, and the place ref
  # (`nabu place chgis:hvd_N`) for the np: decision a real place earns.
  #
  # == The ranking bound (honest, announced)
  #
  # Document spread needs from_urn → document resolution through the
  # catalog; computing it for every attested place would walk every
  # edge. The report pre-ranks by distinct-passage count (one grouped
  # journal query), computes EXACT document spread for the top
  # PRERANK_FACTOR × limit candidates, re-ranks by (documents,
  # passages), and reports the bound — a place outside the pre-rank
  # window cannot surface, which is acceptable for review fuel where
  # the head of the distribution is the work.
  class PlaceMineReport
    PRODUCER = "place-mine"
    KIND = "place-candidate"
    TO_PREFIX = "urn:nabu:place:"

    # Pre-rank window multiplier and the catalog IN-clause chunk size.
    PRERANK_FACTOR = 5
    URN_CHUNK = 500

    DEFAULT_LIMIT = 30

    Row = Data.define(:ref, :title, :documents, :passages, :names, :samples) do
      # The ready-to-paste stop-list exit, one line per matched name.
      def stop_lines = names.map { |name, _count| "  - \"#{name}\"" }
    end
    Report = Data.define(:rows, :total_places, :edges, :source, :gazetteer,
                         :prerank_window, :seconds)

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Aggregate the current place-mine edges into ranked review rows.
    # +source+/+gazetteer+ filter by the producer runs' scope
    # ("<source>:<gazetteer>"); nil means every mined scope.
    def run(source: nil, gazetteer: nil, limit: DEFAULT_LIMIT)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      run_ids = run_ids_for(source, gazetteer)
      edges = run_ids.empty? ? nil : @journal[:links].where(kind: KIND, run_id: run_ids)
      if edges.nil? || (edge_count = edges.count).zero?
        return Report.new(rows: [], total_places: 0, edges: 0, source: source,
                          gazetteer: gazetteer, prerank_window: 0,
                          seconds: elapsed(started))
      end

      by_passages = edges.group_and_count(:to_urn)
                         .select_append { count(:from_urn).distinct.as(:passage_count) }
                         .all
      window = [limit * PRERANK_FACTOR, 100].max
      candidates = by_passages.sort_by { |r| -r[:passage_count] }.first(window)
      rows = candidates.map { |r| build_row(edges, r[:to_urn], r[:passage_count]) }
                       .sort_by { |row| [-row.documents, -row.passages] }
                       .first(limit)
      Report.new(rows: rows, total_places: by_passages.size, edges: edge_count,
                 source: source, gazetteer: gazetteer, prerank_window: window,
                 seconds: elapsed(started))
    end

    private

    def elapsed(started) = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    def run_ids_for(source, gazetteer)
      runs = @journal[:link_runs].where(producer: PRODUCER)
      runs = runs.where(Sequel.like(:scope, "#{source}:%")) if source
      runs = runs.where(Sequel.like(:scope, "%:#{gazetteer}")) if gazetteer
      runs.select_map(:id)
    end

    def build_row(edges, to_urn, passage_count)
      place_edges = edges.where(to_urn: to_urn)
      names = place_edges.group_and_count(:detail).all
                         .map { |r| [mined_name(r[:detail]), r[:count]] }
                         .reject { |name, _| name.nil? }
                         .group_by(&:first)
                         .map { |name, pairs| [name, pairs.sum(&:last)] }
                         .sort_by { |_, count| -count }
      from_urns = place_edges.select_map(:from_urn)
      Row.new(ref: ref_for(to_urn), title: title_for(to_urn),
              documents: document_spread(from_urns),
              passages: passage_count, names: names,
              samples: from_urns.first(2))
    end

    # "urn:nabu:place:chgis:hvd_1" → "chgis:hvd_1"
    def ref_for(to_urn) = to_urn.delete_prefix(TO_PREFIX)

    def title_for(to_urn)
      namespace, id = ref_for(to_urn).split(":", 2)
      resolver = (@resolvers ||= {})[namespace] ||=
        Nabu::Store::PlaceIndex.resolver(@catalog, gazetteer: namespace)
      place = resolver&.place(id)
      place&.title
    end

    def mined_name(detail)
      match = detail&.match(/「(.+?)」/)
      match && match[1]
    end

    # Exact distinct-document count for one place's attesting passages,
    # resolved through the catalog in bounded chunks.
    def document_spread(from_urns)
      docs = Set.new
      from_urns.uniq.each_slice(URN_CHUNK) do |chunk|
        @catalog[:passages].where(urn: chunk).select_map(:document_id).each { |id| docs << id }
      end
      docs.size
    end
  end
end
