# frozen_string_literal: true

module Nabu
  module Adapters
    # The World English Bible adapter (P11-8): the public-domain modern English
    # bible — WEB (eBible.org), the Tweedale/eBible.org open text from the
    # seven1m/open-bibles collection (the same repo as the Clementine Vulgate,
    # P11-5). The readable English witness of both alignment-hub works (nt and
    # ot, architecture §10): a reader who cannot yet parse the Greek/Latin sees
    # the same verse in plain English beside the Vorlage.
    #
    # == Why WEB (and not KJV/DRA)
    #
    # WEB is modern, complete (OT + NT + deuterocanon), and unambiguously PUBLIC
    # DOMAIN worldwide — an update of the 1901 ASV released to the public domain
    # by its editor. The KJV is public domain in the US but Crown-copyright in
    # the UK (letters patent), and the Douay-Rheims is archaic; WEB avoids both
    # snags while giving the fullest canon. See test/fixtures/eng-web/README.md.
    #
    # == Layout and identity (the Vulgate USFX-per-book sibling)
    #
    # open-bibles is one flat git repo of per-translation files; ours is exactly
    # ONE file, eng-web.usfx.xml (USFX milestone XML — the UsfxParser family,
    # ZERO new parser). The adapter mints ONE DOCUMENT PER BOOK: urn =
    # urn:nabu:eng-web:<osis-code-downcased> (JON → urn:nabu:eng-web:jon), title
    # = the book's <h> heading (Jonah), passage urns <doc-urn>:<chapter>.<verse>.
    # Per-book documents give per-book titles/quarantine, and the alignment hub's
    # cts-verse extractor rides the passage-urn tails (registry `documents:` maps
    # book tokens to these urns). Minting is frozen once used (standing rule).
    #
    # WEB carries inline <f> footnote apparatus the Clementine text lacks;
    # UsfxParser skips those subtrees so only scripture becomes verse text
    # (UsfxParser::NOTE_ELEMENTS).
    #
    # == License
    #
    # Public Domain → license_class "open". Verbatim: the open-bibles README
    # table row "eng-web.usfx.xml | English | USFX | WEB | World English Bible |
    # Public Domain"; the file's own preface: "Because the World English Bible
    # is in the Public Domain (not copyrighted), it can be freely copied,
    # distributed, and redistributed without any payment of royalties."
    #
    # == fetch
    #
    # The shared git path (Adapter#git_fetch! → GitFetch: attic + pre-merge
    # mass-deletion breaker) clones the whole open-bibles repo; the one-file
    # discovery filter below keeps the other translations inert.
    class EngWeb < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "eng-web",
        name: "World English Bible (eBible.org, via open-bibles)",
        license: "Public Domain",
        license_class: "open",
        upstream_url: "https://github.com/seven1m/open-bibles",
        parser_family: "usfx"
      )

      FILENAME = "eng-web.usfx.xml"

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per book of the WEB file, in canon (file) order.
      # Returns an Enumerator without a block (the adapter contract's lazy
      # shape). A workdir without the file yields nothing (the day-one
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
          language: "eng",
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
            id: "urn:nabu:eng-web:#{book.id.downcase}",
            path: File.expand_path(path),
            metadata: { "book" => book.id, "title" => book.heading || book.id, "language" => "eng" }
          )
        end
      end
    end
  end
end
