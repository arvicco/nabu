# frozen_string_literal: true

require_relative "../lects"
require_relative "../store/lect_facets"

module Nabu
  module Query
    # The lect-filter dispatch (P59-3, extracted verbatim from
    # Query::Search's P57-4/P58-4 machinery so parallels — and any later
    # passage-serving query — speaks the same `lect:` filter). Host
    # contract: `@catalog` (the catalog DB) and `@lects` (the resolution
    # seam: :auto feature-detects canonical/nabu-lects lazily, a loaded
    # registry is used as-is, nil means unconfigured — the filter then
    # errors loudly, never a silent no-op).
    #
    # #lect_filter returns the CatalogJoin keyword slice for the host's
    # visible_passages call: `{lect_target:}` once a materialization
    # exists (the only shape that sees per-document journal rulings),
    # `{lect_pairs:}` on a never-materialized catalog (the P57-4 path,
    # byte-identical), `{}` when no lect was asked for.
    module LectFilter
      LECT_MODULE_MISSING = "nabu-lects module not synced"

      private

      # Feature-detect + memoize (the tibetan_words :auto contract): loaded
      # from canonical/nabu-lects on first use, nil while absent (re-detected
      # per call, so a mid-session `nabu sync nabu-lects` is picked up
      # without a restart).
      def lects_seam
        return @lects unless @lects == :auto

        loaded = Nabu::Lects.load_default
        @lects = loaded if loaded
        loaded
      end

      # The dispatch (P58-4): once a materialization exists, the lect facet
      # is the query path — it is the only shape that can express
      # per-document journal rulings. A catalog with no lect facet rows at
      # all (never materialized) keeps the P57-4 (language, source) pair
      # path byte-identically. The module requirement holds either way.
      def lect_filter(lect)
        return {} unless lect

        seam = lects_seam
        raise Nabu::Error, LECT_MODULE_MISSING unless seam
        return { lect_target: lect.to_s } if Store::LectFacets.materialized?(@catalog)

        { lect_pairs: lect_pairs_for(lect) }
      end

      # Every (language, source slug) pair the catalog carries, resolved
      # through Nabu::Lects and kept when it matches +target+ (prefix
      # semantics). Small and query-independent (the vocabulary of held
      # codes × sources, not the passage count), so it costs one DISTINCT
      # scan per lect call, never a per-passage resolve.
      def lect_pairs_for(target)
        seam = lects_seam
        raise Nabu::Error, LECT_MODULE_MISSING unless seam

        @catalog[:documents]
          .join(:sources, id: Sequel[:documents][:source_id])
          .exclude(Sequel[:documents][:language] => nil)
          .distinct
          .select(Sequel[:documents][:language].as(:language), Sequel[:sources][:slug].as(:slug))
          .all
          .filter_map do |row|
            language = row.fetch(:language)
            slug = row.fetch(:slug)
            [language, slug] if lect_matches_target?(seam.resolve(language, source: slug), target)
          end
      end

      # +resolved+ matches +target+ when it IS target, or is a MORE SPECIFIC
      # lect under it — target immediately followed by one of the axis
      # separators (":"/"/"/"@", nabu-lects docs/schema.md's strict order)
      # counts as "under"; a same-length or unrelated string does not
      # (lect lat:med matches lat:med and lat:med/xyz, never lat:cla).
      def lect_matches_target?(resolved, target)
        return true if resolved == target
        return false unless resolved.start_with?(target)

        %w[: / @].include?(resolved[target.length])
      end
    end
  end
end
