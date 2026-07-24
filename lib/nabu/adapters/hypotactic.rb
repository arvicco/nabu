# frozen_string_literal: true

module Nabu
  module Adapters
    # Hypotactic — David Chamberlain's metrical scansions of Greek verse
    # (hypotactic.com), registered as a FEATURE MODULE (kind: module), not a
    # text source. It mints NO catalog rows: its data is the meter enrichment
    # layer (P44-6) — per-passage `enrichments` rows (kind="meter",
    # model="hypotactic") on held Perseus lines, the SECOND producer on the
    # P44-7 meter seam beside Pedecerto's Latin lane. The parse/load work
    # lives entirely in the meter producer Nabu::HypotacticMeter, wired via
    # enrichment_producer below and run by SyncRunner after every hypotactic
    # sync and by Rebuild#replay_enrichments — so, like the trismegistos and
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
    # is honored: every minted meter row carries the "Hypotactic (D.
    # Chamberlain, hypotactic.com)" credit in its payload (HypotacticMeter::
    # CREDIT; the shared show meter line names the model — the full credit
    # rides the payload). A feature module serves no passages, so the
    # source-level P43-2 `credit:` seam has no card to render on — the payload
    # is the attribution surface.
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
                 "attribution; the reference is honored in every minted meter row's payload. " \
                 "GREEK lane only (the Latin lane on hypotactic.com is JS-blocked; Pedecerto " \
                 "covers Latin).",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "hypotactic-meter"
      )

      def self.manifest
        MANIFEST
      end

      # This module's data rides the ENRICHMENT seam (kind="meter",
      # model="hypotactic") via HypotacticMeter, refreshed by SyncRunner after
      # every sync and re-derived by rebuild — the pedecerto wiring, declared
      # here beside content_kind so SyncRunner / Rebuild find the producer
      # without special-casing the slug.
      def self.enrichment_producer? = true

      def self.enrichment_producer(catalog:)
        Nabu::HypotacticMeter.new(catalog: catalog)
      end

      # A feature module mints no documents — its data is meter enrichment
      # rows, not passages. Empty by design, not by accident (the
      # kitab/trismegistos shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: hypotactic is a meter instrument, not a text source — " \
                          "its scansions ride the enrichments table as kind=meter rows (P44-6, " \
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
