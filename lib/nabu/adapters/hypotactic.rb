# frozen_string_literal: true

module Nabu
  module Adapters
    # Hypotactic — David Chamberlain's metrical scansions of Greek verse
    # (hypotactic.com), registered as a FEATURE MODULE (kind: module), not a
    # text source. It mints NO catalog rows: its data is a NEW enrichment kind —
    # meter — layered onto held Perseus lines as links-journal kind="meter"
    # edges (P44-6). The parse/load work lives entirely in the meter producer
    # Nabu::HypotacticMeter, wired via reference_producer below and run by
    # SyncRunner after every hypotactic sync — so, like the trismegistos and
    # kitab modules, discover yields NOTHING and parse is unreachable.
    #
    # GREEK LANE ONLY (v1). The Latin lane on hypotactic.com is JavaScript-
    # blocked; Pedecerto (P44-7) covers Latin meter on this same seam.
    #
    # == License (recorded verbatim)
    #
    # The fetched mirror (github.com/Urdatorn/hypotactic) is licensed CC BY 4.0,
    # and its README quotes Chamberlain's own statement verbatim: "you can use
    # it as you wish, but if you make significant or extensive use of it in
    # published work you should reference me (David Chamberlain) and this site
    # (hypotactic.com)." → class `attribution`. This IS extensive use (a whole
    # scansion database layered onto the library), so the reference expectation
    # is honored: every minted meter edge carries the "Hypotactic (D.
    # Chamberlain, hypotactic.com)" credit in its detail (HypotacticMeter::
    # CREDIT). A feature module serves no passages, so the source-level P43-2
    # `credit:` seam has no card to render on — the per-edge detail is the
    # attribution surface.
    #
    # == fetch: the sparse git clone (the glaux/lila posture — now atomic)
    #
    # A blobless no-checkout clone with a sparse cone of exactly the mirror's
    # tsv/ tree + README + LICENSE, so the owner's first sync transfers the
    # per-work scansion TSVs without the repo's build cruft. The producer reads
    # canonical/hypotactic/tsv/*.tsv. sync_policy manual, enabled: false until
    # the owner-fired first real sync.
    class Hypotactic < Nabu::Adapter
      REPO_URL = "https://github.com/Urdatorn/hypotactic"

      # The sparse cone: the per-work scansion TSVs + the license record + the
      # README (verbatim license + Chamberlain's reference statement).
      SPARSE_PATHS = ["tsv", "README.md", "LICENSE"].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "hypotactic",
        name: "Hypotactic — Greek metrical scansions (D. Chamberlain)",
        license: "CC BY 4.0 (the github.com/Urdatorn/hypotactic mirror), with Chamberlain's " \
                 "own statement quoted verbatim in its README: \"you can use it as you wish, but " \
                 "if you make significant or extensive use of it in published work you should " \
                 "reference me (David Chamberlain) and this site (hypotactic.com)\" — class " \
                 "attribution; the reference is honored on every minted meter edge's detail. " \
                 "GREEK lane only (the Latin lane on hypotactic.com is JS-blocked; Pedecerto " \
                 "covers Latin).",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "hypotactic-meter"
      )

      def self.manifest
        MANIFEST
      end

      # This module's data rides the links journal via HypotacticMeter, refreshed
      # by SyncRunner after every sync (the trismegistos/kitab reference-producer
      # seam — mechanism-general: it re-derives a pure function of the loaded
      # rows and returns a Result-shaped value for the sync tail).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        Nabu::HypotacticMeter.new(catalog: catalog, journal: journal)
      end

      # A feature module mints no documents — its data is meter edges, not
      # passages. Empty by design, not by accident (the kitab/trismegistos shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: hypotactic is a meter instrument, not a text source — " \
                          "its scansions ride the links journal as kind=meter edges (P44-6, " \
                          "HypotacticMeter); parse is unreachable"
      end

      # Sparse GitFetch (class note): only the tsv cone + README + LICENSE
      # materialize; the attic/breaker choreography is the shared one.
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
