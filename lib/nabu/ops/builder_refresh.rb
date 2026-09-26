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
      Summary = Data.define(:timeline, :facets, :kinds)

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
        Summary.new(timeline: timeline, facets: facets, kinds: kinds)
      end
    end
  end
end
