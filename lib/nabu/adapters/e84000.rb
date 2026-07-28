# frozen_string_literal: true

require_relative "../e84000_translations"
require_relative "e84000_tei_parser"

module Nabu
  module Adapters
    # 84000 — Translating the Words of the Buddha (P48-2): the English
    # translations of the Tibetan canon from github.com/84000/data-tei, the
    # Kangyur's translation layer. Census (commit bdfc81c, 2026-07-28): 396
    # published Kangyur TEI under translations/kangyur/translations/ + 3
    # Tengyur publications under translations/tengyur/publications/; the
    # sibling placeholders/ dirs hold 560 + 3,366 header-only stubs
    # (unstarted translations) that skip by rule, censused. The TEI body is
    # ENGLISH; Tibetan lives in the header titles (bo + Bo-Ltn Wylie) and
    # the back-matter glossary entities (the named P48 follow-up).
    #
    # == Identity — the frozEN Toh-number contract (P48 crosswalk)
    #
    # Document slugs are the texts' own Tohoku-catalog numbers, exactly as
    # the derge-kangyur shelf mints them: urn:nabu:e84000:toh<N>, N from the
    # filename's toh segment = the file's first sourceDesc <bibl @key>. A
    # text spanning several Toh numbers (94 upstream) slugs by the FIRST and
    # records all in metadata ("toh"); part-publications (toh1-1 … toh44-45,
    # one Toh published chapter-wise — upstream's own keys) keep the part
    # suffix in the slug and expose the base number via "toh_base" (the
    # P48-6 alignment join key). Letter-suffixed Toh numbers (toh846a) are
    # real catalog ids, never stripped.
    #
    # DUPLICATE PAIRS: the repo keeps BOTH halves of 11 renamed/retitled
    # publications (same UT id, same volume-position prefix, e.g. toh761's
    # iron_beak vs lohatunda copies at editions v1.0.2/v1.0.1). Discovery
    # groups by slug and keeps the highest edition version (tiebreak:
    # filename, descending) — deterministic; losers are censused skips.
    #
    # == Passages
    #
    # The `e84000-tei` family (see E84000TeiParser): one passage per
    # `milestone unit="chunk"`, cited by the Reading Room's own published
    # section.paragraph labels (s.1 / ac.1 / i.3 / 1.5 / c.1).
    #
    # == License — nc, with the Terms_of_Use caveat recorded
    #
    # The repo README states the grant verbatim: "These works are provided
    # under the protection of a Creative Commons CC BY-NC-ND (Attribution -
    # Non-commercial - No-derivatives) 3.0 copyright." → class `nc` (the
    # TraCES BY-NC-ND precedent; MCP default-excluded). CAVEAT: the README's
    # Terms_of_Use link (84000/all-data Terms_of_Use.md) layers "data
    # partnership" registration language over bulk external use — the README
    # grant is the operative license (P47-s2 survey, owner-acknowledged).
    #
    # == fetch / sync policy
    #
    # GitFetch sparse to the translations/ cone (206 of the repo's ~216 MB
    # of blobs ARE translations/ — the cone buys scope clarity more than
    # bytes: knowledgebase/, sections/ and schema/ stay out of canonical).
    # Actively translated upstream → sync_policy manual, wired: false until
    # the owner-fired first sync.
    class E84000 < Nabu::Adapter
      REPO_URL = "https://github.com/84000/data-tei"

      LANGUAGE = "en"
      URN_PREFIX = "urn:nabu:e84000:"
      SPARSE_PATHS = ["translations"].freeze

      # The two published cones, keyed by collection tag.
      COLLECTION_DIRS = {
        "kangyur" => File.join("translations", "kangyur", "translations"),
        "tengyur" => File.join("translations", "tengyur", "publications")
      }.freeze

      # Placeholder stubs live in sibling placeholders/ dirs — never
      # discovered, censused as skips.
      PLACEHOLDER_GLOB = File.join("translations", "*", "placeholders", "*.xml")

      # The filename toh segment: "_toh846a-", "_toh1-1_", "_toh539e,774,1074-".
      # A "-<digits>" part suffix binds tighter than the title that follows
      # (part publications); the comma list carries the further Toh numbers.
      TOH_PATTERN = /_toh(\d+[a-z]?(?:-\d+)?(?:,\d+[a-z]?(?:-\d+)?)*)[-_]/i

      # How far into a file the editionStmt is looked for when resolving a
      # duplicate pair (it sits right after titleStmt in every export).
      VERSION_PEEK_BYTES = 16_384
      EDITION_PATTERN = /<edition>\s*v?\s*([0-9][0-9.]*)/

      MANIFEST = Nabu::SourceManifest.new(
        id: "e84000",
        name: "84000 — Translating the Words of the Buddha (English Kangyur translations)",
        license: "CC BY-NC-ND 3.0 (class nc), stated in the data-tei README: \"These works are " \
                 "provided under the protection of a Creative Commons CC BY-NC-ND (Attribution - " \
                 "Non-commercial - No-derivatives) 3.0 copyright.\" CAVEAT (P47-s2, owner-" \
                 "acknowledged): the README's linked Terms_of_Use.md (84000/all-data) layers " \
                 "\"data partnership\" registration language for bulk external use — the README " \
                 "grant is the operative license. Credit 84000: Translating the Words of the " \
                 "Buddha and the named translation teams",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "e84000-tei"
      )

      def self.manifest
        MANIFEST
      end

      # The Kangyur↔84000 translation crosswalk (P48-6): after every e84000
      # sync, each publication's toh_base keys re-derive kind=translation
      # edges to the derge shelves (see E84000Translations).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        E84000Translations.new(catalog: catalog, journal: journal)
      end

      # The canonical Toh-base rule (part suffix strips, letter suffixes
      # stay) — delegated to the parser family, defined once.
      def self.toh_base(key)
        E84000TeiParser.toh_base(key)
      end

      # One DocumentRef per published text, slugged by its first Toh number,
      # sorted by id. Duplicate pairs resolve to the highest edition version.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        published_groups(workdir).map { |_slug, candidates| ref_for(winner(candidates)) }
                                 .sort_by(&:id).each(&block)
      end

      # The discovery census (P11-7): placeholder stubs and duplicate-pair
      # losers are the explicit quiet skips; a filename discover cannot slug
      # is unrecognized — a defect, rendered loudly.
      def discovery_skips(workdir)
        stubs = Dir.glob(File.join(workdir, PLACEHOLDER_GLOB)).size
        losers = published_groups(workdir).sum { |_slug, candidates| candidates.size - 1 }
        strays = unslugged_files(workdir)
        DiscoverySkips.new(
          skipped_by_rule: stubs + losers,
          unrecognized: strays.size,
          notes: strays.map { |path| "no toh segment in published filename: #{File.basename(path)}" }
        )
      end

      def parse(document_ref)
        E84000TeiParser.new.parse(
          document_ref.path,
          urn: document_ref.id, language: LANGUAGE,
          extra_metadata: {
            "collection" => document_ref.metadata.fetch("collection"),
            "file" => document_ref.metadata.fetch("file")
          }
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
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

      Candidate = Data.define(:path, :collection, :slug, :spec)
      private_constant :Candidate

      def candidates(workdir)
        COLLECTION_DIRS.flat_map do |collection, dir|
          Dir.glob(File.join(workdir, dir, "*.xml")).filter_map do |path|
            spec = TOH_PATTERN.match(File.basename(path))&.captures&.first
            next unless spec

            slug = "toh#{spec.split(',').first.downcase}"
            Candidate.new(path: File.expand_path(path), collection: collection, slug: slug, spec: spec)
          end
        end
      end

      def published_groups(workdir)
        candidates(workdir).group_by(&:slug)
      end

      def unslugged_files(workdir)
        COLLECTION_DIRS.values.flat_map do |dir|
          Dir.glob(File.join(workdir, dir, "*.xml")).reject { |path| TOH_PATTERN.match?(File.basename(path)) }
        end
      end

      # The duplicate-pair rule: highest edition version wins; a version tie
      # breaks on the filename, descending — deterministic either way.
      def winner(candidates)
        return candidates.first if candidates.size == 1

        candidates.max_by { |c| [edition_version(c.path), File.basename(c.path)] }
      end

      # "v 1.0.2" → [1, 0, 2]; a file without a readable editionStmt sorts
      # lowest ([0]) rather than erroring — discovery stays cheap and total.
      def edition_version(path)
        peek = File.open(path, "r") { |io| io.read(VERSION_PEEK_BYTES) }.to_s
        match = EDITION_PATTERN.match(peek)
        match ? match[1].split(".").map(&:to_i) : [0]
      end

      def ref_for(candidate)
        Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: "#{URN_PREFIX}#{candidate.slug}",
          path: candidate.path,
          metadata: {
            "file" => File.basename(candidate.path),
            "collection" => candidate.collection,
            "toh_spec" => candidate.spec
          }
        )
      end
    end
  end
end
