# frozen_string_literal: true

module Nabu
  module Ops
    # The standalone corpus-wide builder pass (P104): timeline →
    # place apply → facets → kind axis → … → lemma rollups, in rebuild's own order with
    # rebuild's own arguments — over a LIVE catalog. Exists because
    # rebuilds are owner-fired inter-phase steps (owner rule
    # 2026-09-26): a phase whose live changes are builder-side
    # (facet_map/kind_map rules, timeline lanes) refreshes projections
    # through this seam instead of firing a library-wide replay. Every
    # builder invoked is drop-and-reproject, so the pass is idempotent
    # and db/ stays a pure function of the permanent folders.
    module BuilderRefresh
      Summary = Data.define(:honkoku_ndl, :timeline, :facets, :kinds, :passage_facets, :lect_rows,
                            :dictionary_stats, :derge_titles,
                            :aes_titles,
                            :lemma_rollups)

      module_function

      def run(catalog:, config:, progress: nil)
        canonical_dir = config.canonical_dir
        # The honkoku <- NDL catalog join FIRST: the facet map and the
        # timeline below project the record it writes.
        progress&.stage("honkoku ndl catalog")
        honkoku_ndl = HonkokuNdlCatalog.new(catalog: catalog, canonical_dir: canonical_dir).run
        progress&.stage("timeline")
        timeline = Store::TimelineBuilder.rebuild!(catalog: catalog, canonical_dir: canonical_dir)
        # P122-1: the armed silver-date lane re-projects behind the timeline.
        progress&.stage("silver dates")
        Store::SilverDates.replay!(catalog: catalog, shelf: DateShelf.present(config))
        # The timeline rebuild drops EVERY axis row, this lane included —
        # before 2026-10-13 only a full rebuild restored it (the refresh
        # served script-axis queries without the artifact-script rows).
        progress&.stage("artifact scripts")
        Store::ArtifactScripts.derive!(catalog, config_path: config.artifact_scripts_path,
                                                registry: Lects.load_default(config: config))
        progress&.stage("place apply")
        PlaceApply.run(catalog: catalog, canonical_dir: canonical_dir)
        progress&.stage("facets")
        facets = Store::FacetBuilder.rebuild!(catalog: catalog,
                                              facet_map: FacetMap.load_default(config: config))
        progress&.stage("kind axis")
        kinds = Store::KindBuilder.rebuild!(catalog: catalog,
                                            kinds: Kinds.load_default(config: config),
                                            progress: progress, canonical_dir: canonical_dir)
        # The passage-grain facet lane (facet_map.yml passage_fields).
        progress&.stage("passage facets")
        passage_facets = Store::PassageFacetBuilder.rebuild!(catalog: catalog,
                                                             facet_map: FacetMap.load_default(config: config))
        # P106-7: the lect facet joins the sanctioned in-phase
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
        # The AES <- AED title join (same post-load mold, aed headers).
        progress&.stage("aes titles")
        aes_titles = AesAedTitles.new(catalog: catalog, canonical_dir: canonical_dir).run
        # P121-2: the lemma attestation rollups LAST — they read the
        # timeline just re-projected (and the live fulltext index), so the
        # `lemma` / `language --curve/--mixing` desks follow every refresh.
        progress&.stage("lemma rollups")
        lemma_rollups = Store::LemmaRollup.rebuild!(catalog: catalog, fulltext_path: config.fulltext_path)
        Summary.new(honkoku_ndl: honkoku_ndl, timeline: timeline, facets: facets, kinds: kinds,
                    passage_facets: passage_facets, lect_rows: lect_rows,
                    dictionary_stats: dictionary_stats, derge_titles: derge_titles,
                    aes_titles: aes_titles,
                    lemma_rollups: lemma_rollups)
      end
    end
  end
end
