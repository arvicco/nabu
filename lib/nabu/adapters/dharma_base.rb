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
      # is censused, never silently dropped.
      def discovery_skips(workdir)
        skipped = xml_paths(workdir).reject { |path| edition_file?(path) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: skipped.size, unrecognized: 0,
          notes: skipped.map { |path| "#{File.basename(path)}: not a DHARMA_ edition file" }
        )
      end

      # Censused upstream tag dirt a subclass maps onto held codes
      # ("kaw-Latin" typo → kaw-Latn); default none.
      ALIASES = {}.freeze

      def parse(document_ref)
        result = DharmaEpidocParser.parse(
          document_ref.path, allowed_languages: self.class::LANGUAGES,
                             aliases: self.class::ALIASES
        )
        document = Nabu::Document.new(
          urn: document_ref.id, language: result.language,
          canonical_path: document_ref.path,
          title: result.title || document_ref.metadata["stem"],
          metadata: {
            "license" => result.license, "maturity" => result.maturity
          }.compact
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
    end
  end
end
