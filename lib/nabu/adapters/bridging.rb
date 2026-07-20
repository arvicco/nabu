# frozen_string_literal: true

require_relative "text_fabric"

module Nabu
  module Adapters
    # ETCBC/bridging (P34-1) — the OSHB↔BHSA word-level crosswalk, registered
    # as a FEATURE MODULE row, not a text source. The repo ships two
    # Text-Fabric node features over the BHSA tf/2021 slot space: "osm" (the
    # OpenScriptures morphhb morph tag of the first OSM morpheme aligned to
    # each BHSA word — "HR", "HVqp3ms") and "osm_sf" (the second morpheme of
    # a two-morpheme word, in practice the pronominal suffix / directional
    # he). The alignment was computed upstream (notebook BHSAbridgeOSM) by
    # consonantal matching of BHSA g_cons words against OSHB <w> morphemes;
    # diagnosed-problematic regions carry the honest value "*" (259 slots in
    # 2021) and BHSA's surfaceless elided-article slots carry no value at
    # all. Census at commit 324598bb (2026-07-20): tf/2021 osm covers
    # 420,108 of 426,590 BHSA words (98.5%), osm_sf 49,376; tf/2017 (the
    # 88%-era build against BHSA 2017's 426,582 slots) is deliberately
    # outside the fetch cone.
    #
    # == Why a module row, not a text source or a links-journal producer
    #
    # The data IS a per-BHSA-word feature — there are no documents to mint,
    # and word slots have no urns for the links journal (whose reference
    # edges are curated document/passage-grain assertions; verse-grain
    # OSHB↔BHSA edges would only duplicate the ot alignment hub). So
    # discover yields NOTHING, parse is unreachable, enabled stays false
    # permanently, and the crosswalk surfaces exclusively as the bhsa
    # adapter's token lane ("osm"/"osm_sf" beside lex/gloss/qere — see
    # Nabu::Adapters::Bhsa): one owner-run `nabu sync bridging` lands
    # canonical/bridging via the sanctioned GitFetch gateway, and the next
    # bhsa (re)parse lights the lane up.
    #
    # == Version pin honesty
    #
    # The BHSA side is pinned hard: osm.tf declares @coreData=BHSA
    # @version=2021 and its slot space (max node 426,590) equals the frozen
    # tf/2021 dataset the bhsa adapter pins — the bhsa Corpus refuses a
    # module whose nodes exceed the dataset's slot space. The OSHB side is
    # NOT commit-pinned upstream: the notebook read morphhb master as pulled
    # ~2021-12-09, while nabu's canonical oshb sits at 3d15126 (2024-08-27) —
    # morphology corrections since then mean the projected tags can lag our
    # OSHB snapshot in places; measured drift is journaled in
    # docs/02-sources.md. The tags remain what upstream shipped, verbatim.
    #
    # == License (verbatim, LICENSE, verified 2026-07-20)
    #
    # "MIT License / Copyright (c) 2019 Dirk Roorda … The above copyright
    # notice and this permission notice shall be included in all copies or
    # substantial portions of the Software." → class attribution (the corph
    # posture: MIT's notice preservation is an attribution duty). NB the
    # values themselves are OSHB morphology (CC BY 4.0) keyed to BHSA nodes;
    # they surface only on bhsa passages, whose CC BY-NC class already
    # governs every serving surface — the strictest gate wins.
    class Bridging < Nabu::Adapter
      REPO_URL = "https://github.com/ETCBC/bridging"

      # The sparse cone IS the version pin: the 2021 build + the yaml
      # feature metadata + the license/README carrying the grants. tf/2017
      # and the notebooks/images never materialize (repo is small, but the
      # pin is the point).
      SPARSE_PATHS = ["tf/2021", "yaml", "README.md", "LICENSE"].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "bridging",
        name: "ETCBC bridging — OSHB↔BHSA word-level crosswalk (Text-Fabric tf/2021 module)",
        license: "MIT License (LICENSE verbatim: \"MIT License / Copyright (c) 2019 Dirk Roorda\"; " \
                 "notice preservation required. The osm values are OSHB morphology, CC BY 4.0; they " \
                 "surface only on bhsa passages, whose CC BY-NC 4.0 class governs serving)",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "text-fabric"
      )

      def self.manifest
        MANIFEST
      end

      # A feature module mints no documents — its data rides the bhsa
      # adapter's tokens. Empty by design, not by accident.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: bridging is a feature module, not a text source — " \
                          "its osm/osm_sf features ride bhsa tokens (P34-1); parse is unreachable"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end
    end
  end
end
