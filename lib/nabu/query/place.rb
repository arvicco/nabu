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
      Card = Data.define(:pleiades_id, :place, :holdings)

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

      def initialize(catalog:, pleiades: nil)
        @catalog = catalog
        @pleiades = pleiades
      end

      # Resolve +query+ (id, place URL, or exact title) to a Result, or
      # raise Error with an actionable message.
      def run(query)
        term = query.to_s.strip
        raise Error, "place: give a Pleiades numeric id or an exact place title" if term.empty?

        id = Nabu::Pleiades.ref_id(term)
        id ? by_id(id) : by_title(term)
      end

      private

      def by_id(id)
        place = @pleiades&.place(id)
        tail_term = place&.title
        Result.new(
          cards: [Card.new(pleiades_id: id, place: place, holdings: holdings(id))],
          dump_loaded: !@pleiades.nil?,
          unlinked_term: tail_term, unlinked: tail_term ? unlinked(tail_term) : []
        )
      end

      def by_title(name)
        if @pleiades.nil?
          raise Error, "place: name lookup needs the gazetteer dump on disk — " \
                       "run `nabu sync pleiades` (a numeric Pleiades id still counts holdings)"
        end
        matches = @pleiades.titled(name)
        raise Error, "no place titled #{name.inspect} in the gazetteer (exact title match)" if matches.empty?

        Result.new(
          cards: matches.map { |place| Card.new(pleiades_id: place.id, place: place, holdings: holdings(place.id)) },
          dump_loaded: true, unlinked_term: name, unlinked: unlinked(name)
        )
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
