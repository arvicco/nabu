# frozen_string_literal: true

require_relative "dillmann_tei_parser"

module Nabu
  module Adapters
    # Dillmann (P46-2): the Gǝʿǝz dictionary shelf — August Dillmann's
    # Lexicon linguae aethiopicae (1865) in the TraCES project's TEI
    # digitization with TraCES additions: 13,727 entry files, one <entry>
    # per file, under numbered directories (`1/` … `11/`) plus `new/` and
    # `new1/`. content_kind :dictionary, slug dillmann, language gez, urns
    # urn:nabu:dict:dillmann:<entry-id> — and those L-prefixed entry ids are
    # exactly what the TraCES corpus's per-token `lex` links point at (the
    # cross-shelf crosswalk, fixture-pinned from both sides).
    #
    # == The repo choice
    #
    # github.com/BetaMasaheft/DillmannData is the DATA repo; the sibling
    # `Dillmann` repo is only the eXist-db display application — recorded so
    # nobody re-scouts the wrong repo.
    #
    # == License — the malformed-URL quirk (row 124)
    #
    # Every entry file carries `<licence target="http(s)://creativecommons
    # .org/licenses/by-sa-nc/4.0/">` — a URL Creative Commons does NOT
    # serve ("by-sa-nc" is not a license slug). The prose beside it reads
    # "licensed under the Creative Commons Attribution-ShareAlike Non
    # Commercial 4.0": the intent is CC BY-NC-SA 4.0 → class `nc` (MCP
    # default-excluded, never redistributed — the GRETIL/MW posture). Both
    # URL-scheme variants exist upstream (12,453 http + 1,274 https,
    # censused 2026-07-26); the quirk is pinned by the fixtures.
    #
    # == fetch / sync policy
    #
    # Sparse GitFetch scoped to the `*.xml` cone + README (the entry files
    # are the repo; schema/build cruft never materializes) through the full
    # attic + breaker contract. Upstream still receives corrections →
    # sync_policy manual, wired: false until the owner-fired first sync.
    class Dillmann < Nabu::Adapter
      REPO_URL = "https://github.com/BetaMasaheft/DillmannData"

      # "**/*.xml" both in git's sparse-pattern grammar (any depth) and in
      # Dir.glob's (the fetch-layer materialization probe).
      SPARSE_PATHS = ["**/*.xml", "README.md"].freeze

      DICTIONARY_SLUG = "dillmann"
      LANGUAGE = "gez"
      TITLE = "Dillmann, Lexicon linguae aethiopicae (1865) — TraCES digital edition"

      MANIFEST = Nabu::SourceManifest.new(
        id: "dillmann",
        name: "Dillmann, Lexicon linguae aethiopicae (TraCES/Beta maṣāḥǝft digitization)",
        license: "CC BY-NC-SA 4.0 (class nc). In-file grant verbatim: \"This file is licensed " \
                 "under the Creative Commons Attribution-ShareAlike Non Commercial 4.0.\" — its " \
                 "target URL is MALFORMED upstream (\"…/licenses/by-sa-nc/4.0/\", a slug Creative " \
                 "Commons does not serve; both http and https variants exist); the prose names " \
                 "the intent. Credit Dillmann 1865 and the TraCES project (ERC Advanced Grant " \
                 "338756), Hiob-Ludolf-Zentrum für Äthiopistik, Hamburg",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "dillmann-tei"
      )

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild load
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # One DocumentRef per */<entry>.xml, sorted by id. The one-level glob
      # keeps the repo-root packaging XML (build/expath-pkg/repo) out of
      # discovery and never matches the dotted `.attic` (the base class
      # walks the attic separately, same relative shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        document << DillmannTeiParser.new.entry(document_ref.path)
        document
      rescue Nabu::ValidationError => e
        raise ParseError, "dillmann: #{document_ref.id}: #{e.message}"
      end

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
        Dir.glob(File.join(workdir, "*", "*.xml")).map do |path|
          stem = File.basename(path, ".xml")
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{stem}",
            path: File.expand_path(path),
            metadata: { "dictionary" => DICTIONARY_SLUG }
          )
        end.sort_by(&:id)
      end
    end
  end
end
