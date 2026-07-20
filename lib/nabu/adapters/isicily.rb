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

      TRANSLATION_TITLES = { "eng" => "English", "ita" => "Italian" }.freeze

      # ISO 639-3 (stored document language) → the urn sibling suffix.
      TRANSLATION_SUFFIXES = { "eng" => "en", "ita" => "it" }.freeze

      # +translations+ arrives via SourceRegistry::Entry#build_adapter for
      # the opted-in registry row (P34-0). Off (the default) mints the base
      # records + their -translit layer siblings only; on adds the -en/-it
      # translation siblings.
      def initialize(translations: false)
        super()
        @translations = translations
      end

      # One DocumentRef per record file plus its citable siblings, sorted by
      # urn. A workdir without inscriptions/ yields nothing (the day-one
      # pre-clone state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        metadata = document_ref.metadata
        parser = IsicilyEpidocParser.new
        case metadata["kind"]
        when "translation"
          parse_translation(document_ref, metadata.fetch("language"))
        when "transliteration"
          layer = IsicilyEpidocParser::TRANSLITERATION_LAYER
          parser.parse(document_ref.path, urn: document_ref.id, layer: layer)
        else
          parser.parse(document_ref.path, urn: document_ref.id)
        end
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
           .flat_map { |path| record_refs(File.expand_path(path)) }
           .sort_by(&:id)
      end

      # The base record ref + its citable siblings (the parser's own census
      # decides which layers/translations are real — the ogham/itant
      # discipline). An unreadable record still mints its base ref, whose
      # parse re-raises the real error as the honest quarantine.
      def record_refs(path)
        base = "#{IsicilyEpidocParser::URN_PREFIX}#{File.basename(path, '.xml').downcase}"
        refs = [Nabu::DocumentRef.new(source_id: manifest.id, id: base, path: path)]
        census = record_siblings(path)
        return refs if census.nil?

        if census.transliteration
          refs << Nabu::DocumentRef.new(source_id: manifest.id, id: "#{base}-translit", path: path,
                                        metadata: { "kind" => "transliteration" })
        end
        refs + translation_refs(base, path, census)
      end

      def translation_refs(base, path, census)
        return [] unless @translations

        census.translations.map do |language|
          Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{base}-#{TRANSLATION_SUFFIXES.fetch(language)}", path: path,
            metadata: { "kind" => "translation", "language" => language }
          )
        end
      end

      # nil = unreadable record (malformed XML): only the base ref is
      # minted, its parse re-raising the quarantine.
      def record_siblings(path)
        IsicilyEpidocParser.new.siblings(path)
      rescue ParseError
        nil
      end

      # The -en/-it sibling: one passage per translation paragraph, cited
      # p<ordinal>, the first carrying upstream's whole-text corresp anchor
      # at the primary's first line (loose-alignment honesty — the ETCSL
      # mechanism, never per-line invention).
      def parse_translation(document_ref, language)
        parser = IsicilyEpidocParser.new
        base = document_ref.id.delete_suffix("-#{TRANSLATION_SUFFIXES.fetch(language)}")
        original = parser.parse(document_ref.path, urn: base)
        anchor = original.first&.urn&.delete_prefix("#{base}:")
        document = Nabu::Document.new(
          urn: document_ref.id, language: language,
          title: translation_title(original.title, language),
          canonical_path: document_ref.path, metadata: { "kind" => "translation" }
        )
        parser.translations(document_ref.path, anchor_suffix: anchor).fetch(language, [])
              .each_with_index do |(cite, text, corresp), sequence|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{cite}", language: language, text: text, sequence: sequence,
            annotations: corresp ? { "corresp" => corresp } : {}
          )
        end
        if document.empty?
          raise ParseError, "#{document_ref.path}: no #{language} translation prose for #{document_ref.id}"
        end

        document
      rescue ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def translation_title(title, language)
        label = "#{TRANSLATION_TITLES.fetch(language)} translation"
        title ? "#{title} — #{label}" : label
      end
    end
  end
end
