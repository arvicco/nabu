# frozen_string_literal: true

require_relative "ollett_tei_parser"

module Nabu
  module Adapters
    # Shared base for Andrew Ollett's two TEI text repositories (P118-3):
    # the Kannada Digital Texts Project (KannadaTexts) and the Prakrit
    # Digital Texts Project (PrakritTexts), both composing the `ollett-tei`
    # parser family. A subclass declares SLUG, REPO_URL, NAME, LICENSE,
    # CREDIT, DEFAULT_LANGUAGE, ALLOWED_LANGUAGES (the measured per-passage
    # census — the unknown-code net) and optionally EXCLUDED (repo path →
    # declared reason), LANGUAGE_REPAIRS (siglum → code) and #refine_metadata.
    #
    # == Identity (FROZEN minting)
    #
    #   urn:nabu:<slug>:<file stem, NFC>   (…:kannada-texts:pampa-ādipurāṇaṁ)
    #   passage: <urn>:<div path>.<unit n>  (…:pampa-ādipurāṇaṁ:1.25)
    #
    # The literal filename stem is upstream's stable id (the SARIT/GRETIL
    # precedent; stems are unique across each repo's author folders,
    # census 2026-10-11). The work's own citation siglum (the TEI root's
    # @n — Ādi, GāSa, Āyār) rides metadata["siglum"] with the cRefPattern.
    # Trimmed FIXTURES carry suffixed stems so fixture urns never collide
    # with the real corpus urns.
    #
    # == Discovery
    #
    # tei/**/*.xml (the raw/, txt/ and scripts/ trees are OCR inputs and
    # generated derivatives, never ingested; the sparse fetch does not even
    # materialize them). Two exclusion rules, both censused in
    # discovery_skips with a per-file note — never silent: (1) a declared
    # EXCLUDED path (an overlap held through another source); (2) a file
    # whose <availability> carries NO grant text (the Śvētāmbara Āgama
    # template comment "add whatever license you like") — no grant, no
    # ingest. The parser re-verifies every admitted file's grant (the
    # license gate), so a file that slips the peek still quarantines.
    #
    # == Fetch
    #
    # Sparse GitFetch (the croala recipe) of the tei/ cone + README.md (the
    # repo-level statement); attic + mass-deletion breaker as everywhere.
    class OllettTextsBase < Nabu::Adapter
      TEI_DIR = "tei"
      SPARSE_PATHS = [TEI_DIR, "README.md"].freeze

      # The grants these repositories carry in-file (census 2026-10-11:
      # every admitted Kannada and Prakrit file reads "Distributed under a
      # Creative Commons Attribution-ShareAlike 4.0 license").
      GRANTS = {
        %r{creativecommons\.org/licenses/by-sa/4\.0} => "CC BY-SA 4.0",
        /Creative Commons Attribution[- ]ShareAlike 4\.0/i => "CC BY-SA 4.0"
      }.freeze

      EXCLUDED = {}.freeze
      LANGUAGE_REPAIRS = {}.freeze

      # The availability element of a raw TEI file and whether it says
      # anything once comments are stripped.
      AVAILABILITY = %r{<availability\b[^>]*>(.*?)</availability>}m
      COMMENT = /<!--.*?-->/m

      def self.manifest
        Nabu::SourceManifest.new(
          id: self::SLUG, name: self::NAME, license: self::LICENSE,
          license_class: "attribution", upstream_url: self::REPO_URL,
          parser_family: "ollett-tei", credit: self::CREDIT
        )
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        tei_paths(workdir).filter_map do |path|
          next if exclusion(workdir, path)

          stem = stem_of(path)
          Nabu::DocumentRef.new(
            source_id: self.class::SLUG,
            id: "urn:nabu:#{self.class::SLUG}:#{stem}",
            path: File.expand_path(path),
            metadata: { "stem" => stem, "repo_path" => relative(workdir, path) }
          )
        end.sort_by(&:id).each(&block)
      end

      def discovery_skips(workdir)
        notes = tei_paths(workdir).filter_map do |path|
          reason = exclusion(workdir, path)
          "#{relative(workdir, path)}: #{reason}" if reason
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: 0, notes: notes)
      end

      def parse(document_ref)
        parser.parse(
          document_ref.path,
          urn: document_ref.id, default_language: self.class::DEFAULT_LANGUAGE,
          language_overrides: self.class::LANGUAGE_REPAIRS,
          refine: ->(metadata) { refine_metadata(metadata) }
        )
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        self.class::REPO_URL
      end

      def parser
        OllettTeiParser.new(allowed: self.class::ALLOWED_LANGUAGES, grants: GRANTS)
      end

      # Subclass hook: censused corrections and attributed dates.
      def refine_metadata(metadata)
        metadata
      end

      def tei_paths(workdir)
        Dir.glob(File.join(workdir, TEI_DIR, "**", "*.xml"))
      end

      def stem_of(path)
        File.basename(path, ".xml").unicode_normalize(:nfc)
      end

      def relative(workdir, path)
        File.expand_path(path).delete_prefix("#{File.expand_path(workdir)}/").unicode_normalize(:nfc)
      end

      # The declared reason a file is not ingested, or nil.
      def exclusion(workdir, path)
        declared = self.class::EXCLUDED[relative(workdir, path)]
        return declared if declared
        return nil if grant_text?(path)

        "no license in the file (<availability> holds only the upstream template comment) — not ingested"
      end

      def grant_text?(path)
        head = File.read(path, 64 * 1024).force_encoding(Encoding::UTF_8).scrub
        availability = head[AVAILABILITY, 1]
        return true if availability.nil? # no element at all: the parser gate decides, loudly

        !availability.gsub(COMMENT, "").gsub(/<[^>]*>/, "").strip.empty?
      end
    end
  end
end
