# frozen_string_literal: true

require_relative "isicily_epidoc_parser"

module Nabu
  module Adapters
    # The I.Sicily adapter (P29-4): the inscriptions of ancient Sicily
    # across all languages (Prag, Oxford; ERC Crossreads;
    # github.com/ISicily/ISicily; Zenodo DOI 10.5281/zenodo.2556743). A
    # thin composition of the IsicilyEpidocParser family with the shared
    # GitFetch choreography (the ogham shape: one ordinary git repo).
    #
    # == Census (2026-07-18, commit db1a4959 — the fixture pin)
    #
    # 5,120 inscriptions/ISic*.xml records. textLang/@mainLang: grc 3,194 ·
    # la 1,232 · xly 319 (Elymian) · scx 299 (Sicel) · xpu 67 (Sicilian
    # Punic) · osc 4 (Mamertine Oscan) · he 2 · xx 1 · absent 2. The
    # Greek/Latin majority is Hellenistic–Roman epigraphy; the fragmentary
    # languages are the corpus's unique value — their only machine-
    # readable home (many as metadata-only catalogue records: scx 212/299,
    # xpu 53/67 carry no transcription). ~70 MB of XML; the repo also
    # holds documentation/, alists/, signacula/ — discovery only reads
    # inscriptions/ISic<digits>.xml.
    #
    # == License (three concordant layers — no conflict)
    #
    # - Repo licence.txt: the full CC BY 4.0 legal text.
    # - GitHub license field: CC-BY-4.0 (API-verified 2026-07-18).
    # - EVERY record's <availability>: "Licensed under a Creative
    #   Commons-Attribution 4.0 licence" (target …/by/4.0/).
    # → attribution. Facsimile <graphic> images carry separate museum
    # permission language and are never fetched (the repo holds none).
    #
    # == EDH overlap (honesty note)
    #
    # I.Sicily's 1,232 Latin records may intersect EDH's Sicily holdings —
    # provenance-distinct witnesses (standing doctrine), never deduped.
    # The explicit intersection is tiny: 8 records carry a non-empty EDH
    # idno, each minting a urn:nabu:edh:hd… reference edge that resolves
    # inside the catalog once EDH is synced. The wider latent overlap
    # (EDCS 1,962 / TM 2,697 concordances) is journaled, not guessed.
    #
    # == fetch / sync policy
    #
    # One git repo through the shared non-destructive GitFetch
    # choreography (#git_fetch!). The corpus is LIVE (ERC Crossreads
    # lemmatization landing through 2025–26; pushed daily) → sync_policy
    # manual: re-syncs are owner-fired.
    class Isicily < Nabu::Adapter
      REPO_URL = "https://github.com/ISicily/ISicily"

      INSCRIPTIONS_DIRNAME = "inscriptions"

      # A record file as the repo spells it (ISic000001.xml … ISic090135
      # .xml); the directory's ISicily.xpr / tei-epidoc.rng are tooling,
      # not records.
      RECORD_FILENAME = /\AISic\d+\.xml\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "isicily",
        name: "I.Sicily — the inscriptions of ancient Sicily (Prag, Oxford / ERC Crossreads)",
        license: "CC BY 4.0, three concordant layers: repo licence.txt (the full CC BY 4.0 text), " \
                 "the GitHub license field (CC-BY-4.0, API-verified 2026-07-18), and EVERY record's " \
                 "<licence> \"Licensed under a Creative Commons-Attribution 4.0 licence\" " \
                 "(target creativecommons.org/licenses/by/4.0/)",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "isicily-epidoc"
      )

      def self.manifest
        MANIFEST
      end

      # The concordance edges — TM/EDR/EDCS/PHI stable-id schemes plus the
      # cross-catalog urn:nabu:edh:hd… targets (parser class note).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        LibraryReferences.new(catalog: catalog, journal: journal, producer: "isicily")
      end

      # One DocumentRef per record file, sorted by urn. A workdir without
      # inscriptions/ yields nothing (the day-one pre-clone state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        IsicilyEpidocParser.new.parse(document_ref.path, urn: document_ref.id)
      end

      # One git repo, the shared non-destructive choreography (fetch →
      # breaker → attic → ff-merge).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: REPO_URL, workdir: workdir, progress: progress, force: force)
      end

      private

      def document_refs(workdir)
        Dir.glob(File.join(workdir, INSCRIPTIONS_DIRNAME, "ISic*.xml"))
           .select { |path| RECORD_FILENAME.match?(File.basename(path)) }
           .map do |path|
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{IsicilyEpidocParser::URN_PREFIX}#{File.basename(path, '.xml').downcase}",
            path: File.expand_path(path)
          )
        end.sort_by(&:id)
      end
    end
  end
end
