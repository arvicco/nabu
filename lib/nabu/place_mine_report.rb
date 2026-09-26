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

    # The board (P105-1 — Q86): the name-grouped VERDICT surface. A
    # matching decision is made per verbatim NAME (names.yml keys are
    # names), so the board's grain is the mined name — its candidate
    # places listed under it with the discriminators that separate
    # homonym identities (parent unit, feature type, year span,
    # coordinates) and 1–2 attestation snippets in context. Names the
    # registry has already decided, and names ruled onto the hand stop
    # list after the mine ran, leave the board censused — the surface
    # shows undecided work only (the review-fuel doctrine).
    BoardCandidate = Data.define(:ref, :title, :parent, :place_types, :time_periods,
                                 :lat, :lon)
    BoardRow = Data.define(:name, :documents, :passages, :candidates, :snippets)
    Board = Data.define(:rows, :total_names, :edges, :source, :gazetteer,
                        :prerank_window, :decided, :stopped, :seconds)

    # Characters of context kept either side of the matched name in a
    # snippet — enough classical Chinese to read the usage, short enough
    # to scan fifty rows.
    SNIPPET_CONTEXT = 18
    SNIPPET_SAMPLES = 2

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

    # The name-grouped board over one mined (source, gazetteer) scope.
    # +registry+ is a nabu-places read seam (or anything answering
    # #decision(source, name)); +stop_names+ the hand stop list as ruled
    # TODAY — both filters censused on the result, never silent.
    def board(source:, gazetteer:, limit: DEFAULT_LIMIT, registry: nil, stop_names: [])
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      run_ids = run_ids_for(source, gazetteer)
      edges = run_ids.empty? ? nil : @journal[:links].where(kind: KIND, run_id: run_ids)
      if edges.nil? || (edge_count = edges.count).zero?
        return Board.new(rows: [], total_names: 0, edges: 0, source: source,
                         gazetteer: gazetteer, prerank_window: 0, decided: [],
                         stopped: [], seconds: elapsed(started))
      end

      by_name = passages_by_name(edges)
      decided = []
      stopped = []
      undecided = by_name.reject do |name, _count|
        if (decision = registry&.decision(source, name))
          decided << [name, decision.status]
          true
        elsif stop_names.include?(name)
          stopped << name
          true
        else
          false
        end
      end
      window = [limit * PRERANK_FACTOR, 100].max
      head = undecided.sort_by { |_name, count| -count }.first(window)
      rows = head.map { |name, _count| build_board_row(edges, name, gazetteer) }
                 .sort_by { |row| [-row.documents, -row.passages] }
                 .first(limit)
      Board.new(rows: rows, total_names: undecided.size, edges: edge_count,
                source: source, gazetteer: gazetteer, prerank_window: window,
                decided: decided.sort_by(&:first), stopped: stopped.sort,
                seconds: elapsed(started))
    end

    private

    def elapsed(started) = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    # {mined name => distinct attesting passages} — the pre-rank tally,
    # one grouped journal query (the run()-side bound, per name).
    def passages_by_name(edges)
      edges.group_and_count(:detail)
           .select_append { count(:from_urn).distinct.as(:passage_count) }
           .all
           .group_by { |r| mined_name(r[:detail]) }
           .reject { |name, _rows| name.nil? }
           .transform_values { |rows| rows.sum { |r| r[:passage_count] } }
    end

    def build_board_row(edges, name, gazetteer)
      name_edges = edges.where(detail: "mined 「#{name}」 (#{gazetteer})")
      from_urns = name_edges.distinct.select_map(:from_urn).uniq
      candidates = name_edges.distinct.select_map(:to_urn).sort
                             .map { |to_urn| candidate_for(to_urn) }
      BoardRow.new(name: name, documents: document_spread(from_urns),
                   passages: from_urns.size, candidates: candidates,
                   snippets: snippets_for(from_urns.first(SNIPPET_SAMPLES), name))
    end

    # One candidate's discriminator card, read straight off the derived
    # place index (an absent row degrades to bare ref — honest).
    def candidate_for(to_urn)
      ref = ref_for(to_urn)
      namespace, id = ref.split(":", 2)
      row = @catalog[:place_index].first(gazetteer: namespace, place_id: id)
      if row.nil?
        return BoardCandidate.new(ref: ref, title: nil, parent: nil, place_types: [],
                                  time_periods: [], lat: nil, lon: nil)
      end

      BoardCandidate.new(ref: ref, title: row[:title], parent: row[:parent],
                         place_types: JSON.parse(row[:place_types_json]),
                         time_periods: JSON.parse(row[:time_periods_json]),
                         lat: row[:lat], lon: row[:lon])
    end

    def snippets_for(urns, name)
      texts = @catalog[:passages].where(urn: urns).to_hash(:urn, :text)
      urns.filter_map { |urn| texts[urn] && [urn, snippet(texts[urn], name)] }
    end

    # The attestation in context: ±SNIPPET_CONTEXT characters around the
    # first occurrence, the matched name bracketed 「…」 in place.
    def snippet(text, name)
      text = text.to_s.gsub(/\s+/, " ")
      i = text.index(name)
      return text[0, (SNIPPET_CONTEXT * 2) + name.length] if i.nil?

      pre_start = [i - SNIPPET_CONTEXT, 0].max
      tail_end = i + name.length + SNIPPET_CONTEXT
      [pre_start.positive? ? "…" : "",
       text[pre_start...i], "「#{name}」", text[i + name.length, SNIPPET_CONTEXT],
       tail_end < text.length ? "…" : ""].join
    end

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
