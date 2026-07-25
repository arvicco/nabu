# frozen_string_literal: true

require_relative "croala_tei_parser"

module Nabu
  module Adapters
    # CroALa — Croatiae auctores Latini (P44-9): Neven Jovanović's TEI P5
    # edition of Croatian Latin authors, 976 CE onward through the neo-Latin
    # centuries — ~569 documents / 5.8M words of medieval and Renaissance Latin
    # on the classical desk's medieval-Latin edge. A thin composition of the
    # bespoke `croala-tei` parser family; the adapter owns identity, the source
    # license, and the fetch.
    #
    # == Identity
    #
    # The repo ships one TEI file per work at txts/<work-id>.xml, and the
    # filename stem IS the work's own id (== its fileDesc/@xml:id — verified on
    # the fixtures), so:
    #
    #   document urn  urn:nabu:croala:<stem>          (urn:nabu:croala:albert-i-inscr)
    #   passage urn   <document-urn>:<div-path>.<unit>  (…:albert-i-inscr:d1.p1)
    #
    # The <div-path>.<unit> citation is minted by the parser (positional and
    # coherent — see CroalaTeiParser). ref.id == parse(ref).urn (the
    # conformance identity the sync breaker relies on).
    #
    # == License — the D44-b resolution (in-repo LICENSE governs, house doctrine)
    #
    # The recorded fork was site CC BY-NC-SA 3.0 vs GitHub CC BY. The repo's
    # own LICENSE.md is the full Creative Commons **Attribution 4.0
    # International** legal text ("# Attribution 4.0 International"), and the
    # README states the texts are "freely available under a CC-BY license". The
    # in-file grant governs → CC BY 4.0, registry class `attribution` (the
    # Perseus/First1K class). No per-document override, no owner ruling needed
    # (D44-b self-consistent).
    #
    # == fetch / sync policy
    #
    # Sparse GitFetch scoped to the cone [txts, LICENSE.md, README.md]: a
    # blobless no-checkout clone that materializes the TEI tree + the grant +
    # the collection note, skipping the schemas/, scripts/ and oXygen-project
    # cruft. The corpus is a living edition (the editor adds texts over time:
    # 509 → 569 already), so git tracks the ongoing state — sync_policy manual,
    # enabled: false until the owner-fired first real sync. Working tree is
    # modest (single-digit MB of text; one file reaches ~6 MB, which is why the
    # parser streams).
    class Croala < Nabu::Adapter
      REPO_URL = "https://github.com/nevenjovanovic/croatiae-auctores-latini-textus"

      # The sparse cone: the TEI tree + the in-file grant (D44-b) + the
      # collection's own state note.
      SPARSE_PATHS = ["txts", "LICENSE.md", "README.md"].freeze

      TXTS_DIR = "txts"
      LANGUAGE = "lat"
      URN_PREFIX = "urn:nabu:croala:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "croala",
        name: "Croatiae auctores Latini — CroALa (Jovanović, ed.)",
        license: "CC BY 4.0 (in-repo LICENSE.md, verbatim: \"Attribution 4.0 " \
                 "International\"; README: \"freely available under a CC-BY license\") — " \
                 "the D44-b fork (site CC BY-NC-SA 3.0 vs GitHub CC BY) resolves to the " \
                 "in-file grant, class attribution. Cite CroALa (croala.ffzg.unizg.hr), " \
                 "doi:10.5281/zenodo.10456561",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "croala-tei"
      )

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per txts/<stem>.xml, sorted by urn. A pre-fetch workdir
      # yields nothing (txts/ absent).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Delegate to the CroalaTeiParser with identity and language (lat); the
      # parser mines the title and creation metadata from the teiHeader.
      def parse(document_ref)
        CroalaTeiParser.new.parse(
          document_ref.path,
          urn: document_ref.id, language: LANGUAGE
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Sparse GitFetch (the DCS/GLAUx recipe): only the txts cone + the grant
      # + README materialize; the attic/breaker choreography is the shared one.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end

      def document_refs(workdir)
        Dir.glob(File.join(workdir, TXTS_DIR, "*.xml")).map do |path|
          stem = File.basename(path, ".xml")
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{stem}",
            path: File.expand_path(path),
            metadata: { "stem" => stem }
          )
        end.sort_by(&:id)
      end
    end
  end
end
