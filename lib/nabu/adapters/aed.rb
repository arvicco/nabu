# frozen_string_literal: true

require_relative "aed_tei_parser"

module Nabu
  module Adapters
    # The AED adapter (P28-1): the TLA/BBAW Ägyptische Wortliste — the
    # Egyptian dictionary shelf (architecture §11), dictionary slug "aed",
    # language egy, parser family aed-tei. Same content_kind :dictionary
    # routing and DictionaryDocument/Entry model as the lexica /
    # Bosworth-Toller shelves.
    #
    # == THE JOIN CONTRACT (the packet's point)
    #
    # AED entry ids are the upstream @xml:id VERBATIM ("tla550034") — the
    # TLA lemmaIDs that the AES corpus (P28-0, the sibling packet) mints as
    # its gold lemma ids. So the minted urn
    #
    #   urn:nabu:dict:aed:<lemmaID>
    #
    # is exactly what an AES annotation predicts: Egyptian `define` resolves
    # an AES lemma id directly (Define#by_urn / nabu show), and the folded
    # headwords resolve the transliteration lookups (`define nfr`). AES
    # token references spell the id with the TEI prefix notation
    # ("tla:550034", prefixDef → dictionary.xml#…); normalizing that to
    # "tla550034" is the AES side's one obligation.
    #
    # == Upstream
    #
    # github.com/simondschweitzer/aed-tei — the TLA (Thesaurus Linguae
    # Aegyptiae, BBAW) dictionary export: files/dictionary.xml, 35,052
    # entries, 18 MB. The repo also carries ~55,000 per-text TEI files
    # (651 MB working tree) that belong to the AES corpus surface, not this
    # shelf — fetch is therefore the SPARSE GitFetch recipe (the DCS
    # precedent): blobless no-checkout clone + sparse cone scoped to the
    # dictionary file and the README, so a sync transfers megabytes, not
    # the repo.
    #
    # == License
    #
    # CC BY-SA 4.0, from the file's own <availability> (in-file doctrine),
    # quoted verbatim in the manifest → license_class "attribution".
    class Aed < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "aed",
        name: "AED — Ägyptische Wortliste (TLA/BBAW dictionary export)",
        license: "CC BY-SA 4.0 (verbatim in-file <availability>: \"Metadata and texts are " \
                 "released as Creative Commons, Attribution-ShareAlike 4.0 (CC BY-SA 4.0)\"; " \
                 "data from the TLA project via github.com/simondschweitzer/aed-tei)",
        license_class: "attribution",
        upstream_url: "https://github.com/simondschweitzer/aed-tei",
        parser_family: "aed-tei"
      )

      # The sparse cone: the one dictionary file + the README that carries
      # the project description (the license grant is in-file).
      SPARSE_PATHS = ["files/dictionary.xml", "README.md"].freeze

      DICTIONARY_FILE = File.join("files", "dictionary.xml").freeze
      DICTIONARY_SLUG = "aed"
      LANGUAGE = "egy"
      TITLE = "Ägyptische Wortliste (TLA — Ancient Egyptian Dictionary)"

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # One DocumentRef for the one dictionary file. A workdir without it
      # yields nothing (the day-one pre-fetch state); the same relative
      # shape recurs under the attic, so retention costs nothing here.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", DICTIONARY_FILE)).first(1).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:dictionary.xml",
            path: File.expand_path(path),
            metadata: { "dictionary" => DICTIONARY_SLUG }
          )
        end
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        AedTeiParser.new.entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "aed: #{document_ref.id}: #{e.message}"
      end

      # Clone or non-destructively pull the aed-tei repo via the shared git
      # path (GitFetch: attic + pre-merge mass-deletion breaker), sparse
      # cone scoped to the dictionary file (class note).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress,
                   force: force, sparse: SPARSE_PATHS)
      end

      private

      # Split out so fetch tests can point a singleton at a local git
      # tmpdir (the house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end
    end
  end
end
