# frozen_string_literal: true

require_relative "digiliblt_conllu_parser"

module Nabu
  module Adapters
    # digilibLT (P45-3): the Biblioteca digitale di testi latini tardoantichi
    # (Vercelli / Università del Piemonte Orientale) — 373 late-antique
    # SECULAR Latin prose texts, 2nd–7th c. AD: the classical→medieval
    # transition band (Ammianus, the grammarians, the agrimensores, the
    # jurists), and the romance axis's ancestor shelf. Ingested via CIRCSE's
    # github.com/CIRCSE/digilibLT — the digiliblt.uniupo.it TEI texts
    # UDPipe-lemmatized and LiLa-linked as CoNLL-U (the recommended lane:
    # commit-pinned git posture, one file per work, lemma + UPOS riding every
    # token). A thin composition of the `digiliblt-conllu` family; the
    # adapter owns identity, license and the fetch.
    #
    # == Identity
    #
    # The archives ship one file per work named <dlt-id>.xml_linked.conllu
    # (dlt000008 …); the dlt id IS the corpus's own text id (`# docId`
    # header), so:
    #
    #   document urn  urn:nabu:digiliblt:<dlt-id>       (urn:nabu:digiliblt:dlt000008)
    #   passage urn   <document-urn>:<sent_id>          (…:dlt000008:1)
    #
    # sent_id is the file's own per-document 1..n sentence number (the UD
    # precedent). ref.id == parse(ref).urn (the sync-breaker identity).
    #
    # == THE SILVER TIER (upstream's own word: "Bronze")
    #
    # README, verbatim: "these were lemmatised and PoS tagged with the UDPipe
    # tool … The output of UDPipe still needs checking and disambiguating.
    # This upload consists in a *Bronze* version of linking and still needs
    # lots of manual checking." Machine annotation → `lemma_tier: silver` in
    # sources.yml: every lemma count renders LABELED, never gold attestation
    # (the GLAUx/diorisis/CDLI precedent). The fixture carries the evidence
    # in real bytes (dlt000619: "rovinciae" lemmatized "rovintia"). No
    # hand-checked slice exists upstream to promote.
    #
    # == LICENSE (README "Copyright", the ONE license statement in the repo)
    #
    # Verbatim: "The *DigilibLT* texts are licensed under a Creative Commons
    # Attribution-ShareAlike 4.0 International License" (the statement links
    # creativecommons.org/licenses/by-sa/4.0/) → class `attribution`.
    # RECORDED FORK (the CroALa D44-b shape): the decorative badge beside
    # that sentence still links CC BY-NC-SA 3.0 — the license the digilibLT
    # SITE uses for its own TEI downloads — but the repo's operative written
    # grant is the BY-SA 4.0 sentence, and this adapter ingests the repo,
    # not the site. Resolution as D44-b: the in-repo written statement wins;
    # the fork stays recorded here and in docs/02-sources.md.
    #
    # == fetch / sync policy
    #
    # Sparse GitFetch cone [conllu, README.md] — the ttl/ lane (~230 MB of
    # LiLa RDF) never transfers. The conllu/ cone is four tar.gz archives
    # (~106 MB; the .conllu files live INSIDE them, ~700 MB extracted), so
    # fetch EXTRACTS them into <workdir>/texts/ after the git phases
    # (extraction-on-fetch — the ORACC/Diorisis/Pedecerto ZipFetch pattern;
    # discover/parse never open an archive). Extraction is ADDITIVE: a text
    # upstream drops from an archive stays extracted on disk, so retention
    # holds without atticking (the tarballs themselves are the git-tracked
    # assets the attic/breaker choreography sees). No release cadence →
    # sync_policy manual, wired: false until the owner-fired first sync.
    class Digiliblt < Nabu::Adapter
      REPO_URL = "https://github.com/CIRCSE/digilibLT"

      # The archive cone + the license-bearing README.
      SPARSE_PATHS = ["conllu", "README.md"].freeze

      ARCHIVE_DIR = "conllu"
      TEXTS_DIR = "texts"
      LANGUAGE = "lat"
      URN_PREFIX = "urn:nabu:digiliblt:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "digiliblt",
        name: "digilibLT — Biblioteca digitale di testi latini tardoantichi (CIRCSE CoNLL-U)",
        license: "CC BY-SA 4.0 (repo README, verbatim: \"The *DigilibLT* texts are licensed " \
                 "under a Creative Commons Attribution-ShareAlike 4.0 International License\"; " \
                 "recorded fork: the adjacent badge still links CC BY-NC-SA 3.0, the SITE's TEI " \
                 "license — the repo's written BY-SA 4.0 grant governs this lane). Credit " \
                 "digilibLT (Università del Piemonte Orientale) + CIRCSE/LiLa (ERC 769994)",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "digiliblt-conllu"
      )

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per texts/**/<dlt-id>.xml_linked.conllu, sorted by
      # urn. Only the extracted tree is ingestible — the tarballs are fetch
      # furniture, never documents. A pre-fetch workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, TEXTS_DIR, "**", "*.conllu")).map do |path|
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{File.basename(path).split('.').first}",
            path: File.expand_path(path),
            metadata: {}
          )
        end.sort_by(&:id).each(&block)
      end

      # Delegate to the family parser; title and document metadata come from
      # the file's own header block. The parser raises ParseError itself on
      # every censused damage shape (dlt000079 quarantines).
      def parse(document_ref)
        DigilibltConlluParser.new.parse(document_ref.path, urn: document_ref.id, language: LANGUAGE)
      end

      # Sparse GitFetch (class note), then extract the archive cone into
      # texts/. Extraction runs on every fetch (manual cadence; overwrite is
      # idempotent, never a delete).
      def fetch(workdir, progress: nil, force: false)
        report = git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                            sparse: SPARSE_PATHS)
        extract_archives!(workdir, progress: progress)
        report
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end

      # Unpack conllu/part*.tar.gz into texts/ (members are part*/<file>, so
      # the extracted tree is texts/part*/<dlt-id>.xml_linked.conllu). A cone
      # with no archives is a failed acquisition, loudly.
      def extract_archives!(workdir, progress: nil)
        archives = Dir.glob(File.join(workdir, ARCHIVE_DIR, "*.tar.gz"))
        if archives.empty?
          raise Nabu::FetchError,
                "#{manifest.id}: no #{ARCHIVE_DIR}/*.tar.gz archives in #{workdir} to extract"
        end

        texts = File.join(workdir, TEXTS_DIR)
        FileUtils.mkdir_p(texts)
        archives.each do |archive|
          progress&.call("extracting #{File.basename(archive)} into #{TEXTS_DIR}/…\n")
          Shell.run("tar", "-xzf", archive, "-C", texts)
        end
      rescue Shell::Error => e
        raise Nabu::FetchError, "#{manifest.id}: archive extraction failed in #{workdir}: #{e.message}"
      end
    end
  end
end
