# frozen_string_literal: true

require_relative "dharma_epidoc_parser"

module Nabu
  module Adapters
    # Shared base for the DHARMA corpora (P92-1; EFEO/ERC "The Domestication
    # of 'Hindu' Asceticism…", github.com/erc-dharma): five per-repo sources
    # composing the `dharma-epidoc` parser family. A subclass declares its
    # SLUG, REPO_URL, XML_DIR, NAME, CREDIT_CORPUS and LANGUAGES (the
    # measured per-file xml:lang census — the unknown-code net quarantines
    # anything new loudly, including upstream's "languageb-Latn" template
    # placeholder).
    #
    # == Identity
    #
    #   urn:nabu:<slug>:<file stem sans "DHARMA_">   (…:dharma-khmer:INSCIK00001)
    #   passage: <urn>:<line n>  (prose)  |  <urn>:<lg n>.<l n>  (verse)
    #
    # == License
    #
    # Repo-level CC BY 4.0 (GitHub-detected on four of five repos), in-file
    # <licence target> commonly CC BY-SA 4.0 — the in-file grant governs
    # (the Freising doctrine) and is recorded VERBATIM per document in
    # metadata["license"]; both variants are class `attribution`, so no
    # per-document override is needed.
    #
    # == Fetch
    #
    # Sparse GitFetch (the croala recipe) scoped to the XML cone + the
    # repo's grant/README; these are WORKING repos (files carry maturity
    # codes, drafts get renamed/retired), so the attic/breaker choreography
    # earns its keep. Maturity rides metadata for the desk to surface.
    #
    # == Skeletons (rule-skips, never quarantines)
    #
    # Upstream's placeholder records (DharmaEpidocParser, "Skeletons") are
    # a declared grain: discover never yields them and discovery_skips
    # counts each with SKELETON_NOTE. Quarantine is left to malformed
    # input. A once-citable record that skeletonizes simply leaves the
    # parse set and shows as a withdrawal — that lane already carries the
    # "lost its text" signal. Canonical census 2026-11-05 (discovered =
    # parsed + quarantined; skips = non-edition + skeleton):
    #   khmer      1,329 = 1,326 + 3 (two malformed-XML headers, K. 183-1
    #              and 183-33; "thai-Thai")       skips 0 + 29
    #   nusantara    308 = 291 + 17 (16 lang-less, "languageb-Latn")
    #                                             skips 0 + 2
    #   javanese      96 = 91 + 5 ("und")         skips 0 + 2
    #   pyu          146 = 145 + 1 (PYU 120)      skips 0 + 16
    #   campa        122 = 122 + 0                skips 1 + 0
    # (dharma-tamil and dharma-deccan reconcile in their own notes.)
    class DharmaBase < Nabu::Adapter
      FILE_PREFIX = "DHARMA_"

      def self.manifest
        Nabu::SourceManifest.new(
          id: self::SLUG,
          name: self::NAME,
          license: "CC BY 4.0 (repo) / per-file <licence> commonly CC BY-SA 4.0 — " \
                   "the in-file grant governs, recorded verbatim per document; " \
                   "class attribution either way",
          license_class: "attribution",
          upstream_url: self::REPO_URL,
          parser_family: "dharma-epidoc",
          credit: "DHARMA — #{self::CREDIT_CORPUS} (ERC no. 809994, EFEO/CNRS; " \
                  "erc-dharma on GitHub). Cite the corpus and its editors wherever used."
        )
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        edition_paths(workdir).each do |path|
          next if DharmaEpidocParser.skeleton_file?(path)

          stem = File.basename(path, ".xml")
          yield Nabu::DocumentRef.new(
            source_id: self.class::SLUG,
            id: "urn:nabu:#{self.class::SLUG}:#{stem.delete_prefix(FILE_PREFIX)}",
            path: File.expand_path(path),
            metadata: { "stem" => stem }
          )
        end
      end

      # Non-edition xml (upstream worklists like campa's BROUILLON-LISTE.xml)
      # and upstream's skeletons (DharmaEpidocParser, "Skeletons") are
      # censused, never silently dropped — and a skeleton never quarantines:
      # quarantine is for malformed input, a placeholder is a declared
      # grain. A once-citable record that skeletonizes leaves the parse set
      # and surfaces through the withdrawal lane; nothing more is needed.
      def discovery_skips(workdir)
        notes = xml_paths(workdir).filter_map do |path|
          reason = if !edition_file?(path) then non_edition_reason(path)
                   elsif DharmaEpidocParser.skeleton_file?(path) then DharmaEpidocParser::SKELETON_NOTE
                   end
          "#{File.basename(path)}: #{reason}" if reason
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: 0, notes: notes)
      end

      # Censused upstream tag dirt a subclass maps onto held codes
      # ("kaw-Latin" typo → kaw-Latn); default none.
      ALIASES = {}.freeze

      # A MONOLINGUAL corpus's claim for lang-less editions (pyu); nil
      # for multilingual repos — their lang-less editions quarantine.
      DEFAULT_LANGUAGE = nil

      def parse(document_ref)
        doc = Nokogiri::XML(File.read(document_ref.path, encoding: "UTF-8"), &:noblanks)
        doc.remove_namespaces!
        header = corpus_header(doc)
        result = DharmaEpidocParser.parse_doc(
          doc, path: document_ref.path, allowed_languages: self.class::LANGUAGES,
               aliases: self.class::ALIASES,
               default_language: self.class::DEFAULT_LANGUAGE
        )
        document = Nabu::Document.new(
          urn: document_ref.id, language: result.language,
          canonical_path: document_ref.path,
          title: result.title || document_ref.metadata["stem"],
          metadata: {
            "license" => result.license, "maturity" => result.maturity
          }.merge(header).compact
        )
        result.passages.each_with_index do |unit, index|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{unit.key}", language: unit.language,
            text: unit.text, sequence: index,
            annotations: unit.met ? { "met" => unit.met } : {}
          )
        end
        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: sparse_paths)
      end

      private

      # Per-corpus header fields mined from the loaded, namespace-stripped
      # DOM (one load serves header and edition walk). Default: none — the
      # epigraphy repos' headers are censused empty (postures declare it).
      def corpus_header(_doc) = {}

      # Seam for tests (the house local-git pattern).
      def repo_url
        self.class::REPO_URL
      end

      def sparse_paths
        dir = self.class::XML_DIR
        [dir.empty? ? nil : dir, "README.md", "LICENSE", "LICENCE.txt"].compact
      end

      def xml_paths(workdir)
        Dir.glob(File.join(workdir, self.class::XML_DIR, "*.xml")).sort # rubocop:disable Lint/RedundantDirGlobSort -- glob order is platform-dependent pre-3.0 doc habit; explicit sort documents the urn-order guarantee
      end

      def edition_paths(workdir)
        xml_paths(workdir).select { |path| edition_file?(path) }
      end

      def edition_file?(path)
        File.basename(path).start_with?(FILE_PREFIX)
      end

      def non_edition_reason(_path) = "not a DHARMA_ edition file"
    end
  end
end
