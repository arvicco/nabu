# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_place tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      PLACE_DESCRIPTION =
        "The place desk (P44-2; v2 P66-2): one ancient place — resolved through the LOCAL " \
        "Pleiades gazetteer dump or the derived multi-gazetteer place index — plus the " \
        "library's holdings AT that place, per source. `query` is a Pleiades numeric id, a " \
        "pleiades.stoa.org/places URL, a NAMESPACED ref (tm:2810, cigs:GIR — the tm/cigs " \
        "gazetteers), or an EXACT place title " \
        "(case-insensitive; \"Segesta\" works, \"Seges\" does not — no fuzzy matching anywhere, " \
        "by design; homonym titles return one card each). Holdings count live documents whose " \
        "parsers captured that upstream-asserted Pleiades id (the epigraphic sources: isicily, " \
        "edh, iip, itant) — aggregate counts only; read the texts with nabu_search/nabu_show. " \
        "An honest labelled `unlinked` tail counts id-LESS documents whose captured findspot " \
        "TEXT mentions the name (exact substring) — never merged into the id-matched holdings. " \
        "Degrades honestly when the gazetteer dump is not on this box: a numeric id still " \
        "counts holdings (the catalog side needs no dump, the card is just fact-less); a NAME " \
        "lookup needs the dump and says so. Coordinates are display facts — no maps, no " \
        "coordinate math. A card serving gazetteer facts carries `attribution` (the gazetteer's " \
        "source slug, license_class, verbatim license, and the place's upstream uri) — PRESERVE " \
        "it when quoting the facts (Pleiades is CC BY 3.0)."

      PLACE_SCHEMA = {
        type: "object",
        properties: {
          query: { type: "string",
                   description: "A Pleiades numeric id (462281), a pleiades.stoa.org/places " \
                                "URL, or an exact place title (Lilybaeum)." }
        },
        required: ["query"],
        additionalProperties: false
      }.freeze

      private

      # nabu_place (P44-3): the place desk — Query::Place unchanged under an
      # MCP shape. Degradation split: a dump-less NAME lookup is a corpus
      # STATE (note, never isError — the owner syncs the dump, not the
      # caller); an unknown title or empty query is caller-fixable
      # (tool_error, SEP-1303). Holdings are aggregate per-source counts (no
      # urns, no titles, no text — the license_counts stance), so no
      # restricted-exclusion gate is needed here.
      def place(args)
        query = string_arg(args, "query") or
          raise InvalidArguments, "nabu_place needs a query (a Pleiades id or an exact place title)"
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        resolver = place_resolver(catalog)
        # P66-2: namespaced refs (tm:2810, cigs:GIR) resolve through the
        # derived place index, not the pleiades dump — never gated on it.
        namespaced = query.match?(Nabu::PlaceRefs::MINT_PATTERN)
        return note(NO_GAZETTEER_NOTE) if resolver.nil? && !namespaced && Nabu::Pleiades.ref_id(query).nil?

        result = Query::Place.new(catalog: catalog, pleiades: resolver).run(query)
        json(place_payload(query, result))
      rescue Query::Place::Error => e
        tool_error(e.message)
      end

      # -- place internals (P44-3) -------------------------------------------------

      # Resolve the gazetteer slot for one nabu_place call: :auto
      # feature-detects per call, unmemoized — the derived place index in
      # +catalog+ first (P45-6), else the canonical dump, else nil
      # (unsynced); the initializer note carries the cost rationale.
      def place_resolver(catalog)
        @pleiades == :auto ? Nabu::Pleiades.load_default(catalog: catalog) : @pleiades
      end

      def place_payload(query, result)
        {
          type: "place", query: query, dump_loaded: result.dump_loaded,
          cards: result.cards.map { |card| place_card_payload(card, result.dump_loaded) },
          unlinked_term: result.unlinked_term,
          unlinked: source_count_rows(result.unlinked),
          note: "holdings count live documents whose parsers captured this upstream-asserted " \
                "Pleiades id (no fuzzy matching anywhere); axis_holdings is the SEPARATE " \
                "place_ref lane (adapter-asserted + nabu-places registry decisions, both " \
                "spellings, doc-deduped); unlinked counts id-less documents whose captured " \
                "findspot text mentions the name — never merged into holdings; counts are " \
                "aggregate only, nabu_search/nabu_show read the texts"
        }
      end

      # One resolver card. Gazetteer facts ride only when the dump resolved
      # the id; a fact-less card says why honestly (dump unsynced vs id not
      # in the dump) — the CLI's print_place_card degradation, shaped.
      def place_card_payload(card, dump_loaded)
        base = { pleiades_id: card.pleiades_id, ref: card.ref,
                 holdings: source_count_rows(card.holdings),
                 axis_holdings: source_count_rows(card.axis_holdings) }
        # P75 C-3: crosswalk equivalences, present-only (no rows → no key —
        # pre-P75 payloads stay byte-identical).
        unless card.equivalences.empty?
          base[:equivalences] = card.equivalences.map { |namespace, id| "#{namespace}:#{id}" }
        end
        place = card.place
        if place
          base = base.merge(title: place.title, place_types: place.place_types,
                            time_periods: place.time_periods, lat: place.lat, lon: place.lon)
          # P81 U-3 (survey A3): a gazetteer's own "?"-suffixed title — the
          # Barrington less-certain lineage — merges the cataloguer's-"?"
          # certainty object beside the verbatim title; unmarked titles
          # stay byte-identical (the empty-hash idiom).
          if place.title.to_s.strip.end_with?("?")
            base[:title_certainty] = Nabu::Certainty.payload(:cataloguer_query, "?").fetch(:certainty)
          end
          # The reference envelope: served gazetteer FACTS carry the
          # gazetteer's attribution (CC BY — license verbatim from the
          # adapter manifest, plus the place's upstream URI).
          attribution = place_card_attribution(card)
          attribution ? base.merge(attribution: attribution) : base
        elsif dump_loaded
          base.merge(note: "id not in the local gazetteer dump")
        else
          base.merge(note: "gazetteer dump not synced (the owner runs `nabu sync pleiades` to " \
                           "add the card) — holdings counted from the catalog alone")
        end
      end

      def place_card_attribution(card)
        namespace, id = card.ref.to_s.split(":", 2)
        return Envelope.place_attribution("pleiades", card.pleiades_id) if id.nil?

        Envelope.place_attribution(namespace, id)
      end

      def source_count_rows(counts)
        counts.map { |slug, count| { source: slug, documents: count } }
      end
    end
  end
end
