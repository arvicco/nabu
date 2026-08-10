# frozen_string_literal: true

module Nabu
  module Query
    # `nabu place NAME|ID` (P44-2): the place desk — a Pleiades resolver card
    # plus the library's holdings at that place, per source.
    #
    # == Only upstream-asserted ids, only exact names
    #
    # Holdings join documents.metadata_json's $.place.pleiades — the id the
    # parsers captured from canonical bytes (isicily/edh/iip/itant), so the
    # counts are rebuild-honest and never guessed. Input is a Pleiades
    # numeric id (or a pleiades.stoa.org place URL) or an EXACT
    # case-insensitive title match against the local gazetteer dump. No
    # fuzzy matching, out by design.
    #
    # == The unlinked tail — labelled, never merged
    #
    # Documents whose captured findspot TEXT mentions the place name but
    # carry NO Pleiades id surface as a separate labelled count (exact
    # substring, case-insensitive over $.place.ancient/$.place.modern/
    # $.place.settlement/$.findspot — the fields the parsers already
    # capture). ASCII case folding only (SQLite lower()); a name that
    # differs only in non-ASCII case is missed rather than fuzzed.
    #
    # == The resolver (v2: the derived index, P45-6)
    #
    # +pleiades+ is a place resolver — the Store::PlaceIndex::Resolver over
    # the derived catalog place index (instant; what Pleiades.load_default
    # hands back once a sync/rebuild has derived it), the in-memory
    # Nabu::Pleiades dump load (~3 s / ~3.9 GB peak RSS on the real
    # 42,242-place dump — the honest fallback while the index is underived),
    # or nil (dump not synced). Both resolvers share the exact matching
    # semantics (Pleiades.title_keys). Without one, an id query still counts
    # holdings (the catalog side needs no gazetteer); a name query is
    # refused with the sync hint.
    class Place
      class Error < Nabu::Error; end

      # One resolver card: +place+ is the Nabu::Pleiades::Place (nil when
      # the dump is absent or lacks the id — the CLI renders the honest
      # degradation), +holdings+ [[source_slug, count], …] descending.
      # P66-2: +ref+ is the namespaced identity ("pleiades:570685",
      # "tm:2810"); +axis_holdings+ the SEPARATE labeled lane over
      # document_axes.place_ref (adapter-asserted + registry-projected refs
      # in both spellings — Nabu::PlaceRefs is the one reader), doc-deduped.
      Card = Data.define(:pleiades_id, :place, :holdings, :dossiers, :ref, :axis_holdings) do
        def initialize(pleiades_id:, place:, holdings:, dossiers: [], ref: nil, axis_holdings: [])
          super
        end
      end

      # The query's answer: every card (homonym titles yield several),
      # whether a dump was loaded at all, and the labelled unlinked tail —
      # +unlinked_term+ is the exact substring counted, +unlinked+
      # [[source_slug, count], …] over id-less documents only.
      Result = Data.define(:cards, :dump_loaded, :unlinked_term, :unlinked)

      # The JSON path the parsers write the captured id under (P44-2's one
      # agreed key) and the captured findspot-text paths the unlinked tail
      # scans.
      ID_PATH = "$.place.pleiades"
      TEXT_PATHS = ["$.place.ancient", "$.place.modern", "$.place.settlement", "$.findspot"].freeze

      def initialize(catalog:, pleiades: nil, canonical_dir: nil)
        @catalog = catalog
        @pleiades = pleiades
        @canonical_dir = canonical_dir
      end

      # Resolve +query+ (id, place URL, namespaced ref, or exact title) to
      # a Result, or raise Error with an actionable message.
      def run(query)
        term = query.to_s.strip
        if term.empty?
          raise Error, "place: give a Pleiades numeric id, a namespaced ref (tm:2810), or an " \
                       "exact place title"
        end

        if (mint = term.match(Nabu::PlaceRefs::MINT_PATTERN)) &&
           Nabu::PlaceRefs::MINT_NAMESPACES.include?(mint[1])
          return mint[1] == "pleiades" ? by_id(mint[2]) : by_ref(mint[1], mint[2])
        end

        id = Nabu::Pleiades.ref_id(term)
        id ? by_id(id) : by_title(term)
      end

      private

      def by_id(id)
        place = @pleiades&.place(id)
        tail_term = place&.title
        Result.new(
          cards: [Card.new(pleiades_id: id, place: place, holdings: holdings(id),
                           dossiers: dossiers_for("pleiades", id), ref: "pleiades:#{id}",
                           axis_holdings: axis_holdings("pleiades", id))],
          dump_loaded: !@pleiades.nil?,
          unlinked_term: tail_term, unlinked: tail_term ? unlinked(tail_term) : []
        )
      end

      # A non-pleiades namespaced ref (P66-2): the card resolves its title
      # through that gazetteer's OWN place-index slice where one is derived
      # (tm/cigs; np has no gazetteer — place nil, honestly), and its
      # holdings are the axis lane only — the metadata lane is
      # pleiades-keyed by design.
      def by_ref(namespace, id)
        place = gazetteer_resolver(namespace)&.place(id)
        Result.new(
          cards: [Card.new(pleiades_id: nil, place: place, holdings: [],
                           dossiers: dossiers_for(namespace, id), ref: "#{namespace}:#{id}",
                           axis_holdings: axis_holdings(namespace, id))],
          dump_loaded: !place.nil?, unlinked_term: nil, unlinked: []
        )
      end

      def gazetteer_resolver(namespace)
        return nil unless @catalog.table_exists?(Nabu::Store::PlaceIndex::TABLE)

        Nabu::Store::PlaceIndex::Resolver.new(@catalog, gazetteer: namespace)
      end

      # The axis lane: live documents whose place_ref cites (namespace, id)
      # in ANY spelling. SQL LIKE prefilters; Nabu::PlaceRefs verifies
      # (bounded — an id never substring-matches); one doc counts once.
      def axis_holdings(namespace, id)
        return [] unless @catalog.table_exists?(:document_axes)

        escaped = id.to_s.gsub(/[\\%_]/) { |ch| "\\#{ch}" }
        # URL-less namespaces (cigs, np) only ever spell as mints — their
        # prefilter carries the namespace, so a short id (GIR) never drags
        # half the table into the Ruby verify (measured 4 s → sub-second).
        prefilter = Nabu::PlaceRefs::URL_PATTERNS.key?(namespace) ? "%#{escaped}%" : "%#{namespace}:#{escaped}%"
        counts = Hash.new(0)
        seen = Set.new
        @catalog[:document_axes]
          .join(:documents, id: Sequel[:document_axes][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:documents][:withdrawn] => false)
          .where(Sequel.like(Sequel[:document_axes][:place_ref], prefilter, { escape: "\\" }))
          .select_map([Sequel[:document_axes][:place_ref], Sequel[:sources][:slug],
                       Sequel[:document_axes][:document_id]])
          .each do |ref, slug, doc_id|
            next unless Nabu::PlaceRefs.ids_in(ref, namespace).include?(id.to_s)

            counts[slug] += 1 if seen.add?([slug, doc_id])
          end
        counts.sort_by { |slug, count| [-count, slug] }
      end

      def by_title(name)
        if @pleiades.nil?
          raise Error, "place: name lookup needs the gazetteer dump on disk — " \
                       "run `nabu sync pleiades` (a numeric Pleiades id still counts holdings)"
        end
        matches = @pleiades.titled(name)
        raise Error, "no place titled #{name.inspect} in the gazetteer (exact title match)" if matches.empty?

        Result.new(
          cards: matches.map do |place|
            Card.new(pleiades_id: place.id, place: place, holdings: holdings(place.id),
                     dossiers: dossiers_for("pleiades", place.id), ref: "pleiades:#{place.id}",
                     axis_holdings: axis_holdings("pleiades", place.id))
          end,
          dump_loaded: true, unlinked_term: name, unlinked: unlinked(name)
        )
      end

      # The owner's authored place dossiers whose refs cover this id
      # (P64-4; empty without a canonical dir or matching files).
      def dossiers_for(namespace, id)
        return [] if @canonical_dir.nil?

        Nabu::PlaceDossiers.for_ids(@canonical_dir, [[namespace, id.to_s]])
      end

      # Per-source counts of live documents whose captured id equals +id+,
      # descending, slug as tiebreak.
      def holdings(id)
        grouped_counts(documents.where(id_field => id))
      end

      # Per-source counts of live, ID-LESS documents whose captured findspot
      # text contains +term+ (exact substring, ASCII-case-insensitive).
      # Never merged into holdings — the caller renders it labelled.
      def unlinked(term)
        escaped = term.downcase.gsub(/[\\%_]/) { |ch| "\\#{ch}" }
        text_match = Sequel.|(*TEXT_PATHS.map do |path|
          Sequel.like(Sequel.function(:lower, json_field(path)), "%#{escaped}%", { escape: "\\" })
        end)
        grouped_counts(documents.where(id_field => nil).where(text_match))
      end

      def documents
        @catalog[:documents]
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:documents][:withdrawn] => false)
      end

      def grouped_counts(dataset)
        dataset
          .group_and_count(Sequel[:sources][:slug].as(:slug))
          .order(Sequel.desc(:count), :slug)
          .map { |row| [row[:slug], row[:count]] }
      end

      def id_field
        json_field(ID_PATH)
      end

      def json_field(path)
        Sequel.function(:json_extract, Sequel[:documents][:metadata_json], path)
      end
    end
  end
end
