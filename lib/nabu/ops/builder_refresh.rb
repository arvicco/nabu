# frozen_string_literal: true

module Nabu
  module Ops
    # The standalone corpus-wide builder pass (P104): timeline →
    # place apply → facets → kind axis, in rebuild's own order with
    # rebuild's own arguments — over a LIVE catalog. Exists because
    # rebuilds are owner-fired inter-phase steps (owner rule
    # 2026-09-26): a phase whose live changes are builder-side
    # (facet_map/kind_map rules, timeline lanes) refreshes projections
    # through this seam instead of firing a library-wide replay. Every
    # builder invoked is drop-and-reproject, so the pass is idempotent
    # and db/ stays a pure function of the permanent folders.
    module BuilderRefresh
      Summary = Data.define(:timeline, :facets, :kinds, :lect_rows, :dictionary_stats, :derge_titles)

      module_function

      def run(catalog:, config:, progress: nil)
        canonical_dir = config.canonical_dir
        progress&.stage("timeline")
        timeline = Store::TimelineBuilder.rebuild!(catalog: catalog, canonical_dir: canonical_dir)
        progress&.stage("place apply")
        PlaceApply.run(catalog: catalog, canonical_dir: canonical_dir)
        progress&.stage("facets")
        facets = Store::FacetBuilder.rebuild!(catalog: catalog,
                                              facet_map: FacetMap.load_default(config: config))
        progress&.stage("kind axis")
        kinds = Store::KindBuilder.rebuild!(catalog: catalog,
                                            kinds: Kinds.load_default(config: config),
                                            progress: progress, canonical_dir: canonical_dir)
        # P106-7 (Q88.2): the lect facet joins the sanctioned in-phase
        # pass — the one rebuild-only derivation a killed rebuild could
        # strand dark corpus-wide (the 2026-09-26 incident); with it ride
        # the two cheap censuses derived in the same breath (P106-1/-5).
        progress&.stage("lect facets")
        lect_rows = Store::LectFacets.rebuild!(catalog: catalog,
                                               registry: Lects.load_default(config: config),
                                               progress: progress)
        progress&.stage("dictionary stats")
        dictionary_stats = Store::DictionaryStats.rebuild!(catalog: catalog,
                                                           lects: Lects.load_default(config: config))
        progress&.stage("derge titles")
        derge_titles = E84000DergeTitles.new(catalog: catalog, canonical_dir: canonical_dir).run
        Summary.new(timeline: timeline, facets: facets, kinds: kinds, lect_rows: lect_rows,
                    dictionary_stats: dictionary_stats, derge_titles: derge_titles)
      end
    end
  end
end
