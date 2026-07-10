# frozen_string_literal: true

module Nabu
  module Adapters
    # The Vulgate adapter (P11-5): the FULL Latin bible — Clementine
    # (Sixto-Clementine 1592), the Tweedale/eBible.org public-domain text from
    # the seven1m/open-bibles collection. The in-catalog PROIEL latin-nt is
    # NT-only; this is the whole canon (GEN…MAL, deuterocanon, MAT…REV), the
    # Latin witness of both alignment-hub works (nt and ot, architecture §10).
    #
    # == Layout and identity (FROZEN minting)
    #
    # open-bibles is one flat git repo of per-translation files; ours is
    # exactly ONE file, lat-clementine.usfx.xml (4.65 MB, whole bible, USFX
    # milestone XML — the UsfxParser family). The adapter mints ONE DOCUMENT
    # PER BOOK: urn = urn:nabu:vulgate:<osis-code-downcased> (MRK →
    # urn:nabu:vulgate:mrk), title = the book's <h> heading (Marcus), passage
    # urns <doc-urn>:<chapter>.<verse>. Per-book documents give per-book
    # titles and quarantine, and the alignment hub's cts-verse extractor rides
    # the passage-urn tails (registry `documents:` maps book tokens to these
    # urns). Minting is frozen once used (standing rule).
    #
    # == License
    #
    # Public Domain → license_class "open". Verbatim: the open-bibles README
    # table row "Clementine Latin Vulgate | Public Domain"; eBible.org: "No
    # person, company, or organization may claim any kind of copyright or
    # restriction on this version of the Bible... even if they make changes."
    # (NB the repo has no repo-wide LICENSE file — per-file assertion; the
    # Clementine text itself is 1592.) See test/fixtures/vulgate/README.md
    # and docs/02-sources.md for the full chain.
    #
    # == fetch
    #
    # The shared git path (Adapter#git_fetch! → GitFetch: attic + pre-merge
    # mass-deletion breaker) clones the whole open-bibles repo (~76 MB — the
    # one-file discovery filter below keeps the other translations inert).
    class Vulgate < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "vulgate",
        name: "Biblia Sacra Vulgata Clementina (Tweedale/eBible.org, via open-bibles)",
        license: "Public Domain",
        license_class: "open",
        upstream_url: "https://github.com/seven1m/open-bibles",
        parser_family: "usfx"
      )

      FILENAME = "lat-clementine.usfx.xml"

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per book of the Clementine file, in canon (file)
      # order. Returns an Enumerator without a block (the adapter contract's
      # lazy shape). A workdir without the file yields nothing (the day-one
      # pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        UsfxParser.new.parse(
          document_ref.path,
          book: document_ref.metadata.fetch("book"),
          urn: document_ref.id,
          language: "lat",
          title: document_ref.metadata["title"]
        )
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Split out so fetch tests can point a singleton at a local git tmpdir
      # (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end

      def document_refs(workdir)
        path = Dir.glob(File.join(workdir, "**", FILENAME)).min
        return [] unless path

        UsfxParser.new.books(path).map do |book|
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:vulgate:#{book.id.downcase}",
            path: File.expand_path(path),
            metadata: { "book" => book.id, "title" => book.heading || book.id, "language" => "lat" }
          )
        end
      end
    end
  end
end
