# frozen_string_literal: true

require_relative "../place_refs"
require_relative "../pleiades"
require_relative "../store/place_index"

module Nabu
  module Query
    # The --place resolution seam (P75 C-1): one term becomes a Resolution —
    # which identity claims to match on document_axes.place_ref, and which
    # name pattern (if any) to keep matching on place_name. Lanes:
    #
    # - a namespaced mint (`cigs:GIR`, `pleiades:912855`) IS its identity —
    #   no name pattern (the user named an identity, not a spelling);
    # - a LIKE pattern (%/_) stays the historical name-LIKE lane untouched;
    # - a NAME resolves through the derived place index (every gazetteer
    #   slice, Pleiades.name_key fold-both-sides) and the nabu-places
    #   registry's matched decisions — and KEEPS its LIKE pattern, so
    #   name-only documents never fall out (recall composes, never shrinks);
    # - anything unresolved is the honest name-LIKE fallback, exactly the
    #   pre-P75 behavior.
    #
    # Every seed identity expands ONE hop through the derived
    # place_crosswalk (both directions) — the asserted equivalences answer
    # for each other, entity resolution stays out (the places-lpf posture).
    module PlaceFilter
      # +pattern+ nil ⇔ pure identity lane; +identities+ [] ⇔ pure name lane.
      Resolution = Data.define(:term, :pattern, :identities) do
        def identity? = !identities.empty?
      end

      module_function

      # Resolve +term+ against +catalog+ (the derived index + crosswalk) and
      # the optional +places+ registry read seam (Nabu::Places, nil = lane
      # off). Pure read; safe to call for a label and again for the filter.
      def resolve(term, catalog:, places: nil)
        term = term.to_s.strip
        if (mint = term.match(PlaceRefs::MINT_PATTERN)) &&
           PlaceRefs::MINT_NAMESPACES.include?(mint[1])
          return Resolution.new(term: term, pattern: nil,
                                identities: expand([[mint[1], mint[2]]], catalog))
        end
        return Resolution.new(term: term, pattern: term, identities: []) if term.match?(/[%_]/)

        seeds = index_identities(term, catalog) | registry_identities(term, places)
        Resolution.new(term: term, pattern: term,
                       identities: seeds.empty? ? [] : expand(seeds, catalog))
      end

      # The CatalogJoin seam: accept a Resolution (already resolved), a raw
      # string (a caller predating the seam — name-LIKE lane, byte-identical
      # behavior), or nil.
      def coerce(place)
        return place if place.nil? || place.is_a?(Resolution)

        Resolution.new(term: place.to_s, pattern: place.to_s, identities: [])
      end

      # Exact name-key hits across EVERY derived gazetteer slice (np included
      # — minted places derive like any other), deterministic order.
      def index_identities(name, catalog)
        return [] unless catalog.table_exists?(Store::PlaceIndex::NAMES_TABLE)

        catalog[Store::PlaceIndex::NAMES_TABLE]
          .where(name_key: Pleiades.name_key(name))
          .distinct.order(:gazetteer, :place_id)
          .select_map(%i[gazetteer place_id])
      end

      # Matched registry decisions whose verbatim name folds to the same key
      # (fold-both-sides: the registry keys corpus-verbatim spellings).
      def registry_identities(name, places)
        return [] if places.nil?

        key = Pleiades.name_key(name)
        places.sources.flat_map do |source|
          places.decisions_for(source).flat_map do |verbatim, decision|
            next [] unless decision.matched? && Pleiades.name_key(verbatim) == key

            decision.refs.flat_map { |ref| PlaceRefs.ids(ref) }
          end
        end.uniq
      end

      # One crosswalk hop, both directions, seeds first — asserted
      # equivalences only, never inferred chains.
      def expand(seeds, catalog)
        return seeds unless catalog.table_exists?(:place_crosswalk)

        walk = catalog[:place_crosswalk]
        extra = seeds.flat_map do |namespace, id|
          walk.where(gazetteer_a: namespace, id_a: id).select_map(%i[gazetteer_b id_b]) +
            walk.where(gazetteer_b: namespace, id_b: id).select_map(%i[gazetteer_a id_a])
        end
        (seeds + extra.sort).uniq
      end
    end
  end
end
