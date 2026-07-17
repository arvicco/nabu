# frozen_string_literal: true

require_relative "../source_dossier"
require_relative "../source_shelf"

module Nabu
  module Ops
    # The P24-0 gate-check rider (`rake site:check`): FLAGS drift between
    # the canonical/local-source dossier descriptions and the public map
    # (docs/library.md and, through it, the site). It never generates —
    # the owner decided the dossiers are gate-checked only.
    #
    # == The tolerance rule (journaled here — the honest boundary)
    #
    # This is a PRESENCE/MENTION check, never verbatim equality — the
    # dossier description and the library prose are different registers of
    # the same fact and legitimately diverge in wording. Drift means one
    # side KNOWS OF a shelf the other doesn't:
    #
    # 1. a registered source with NO dossier file — the shelf census is
    #    incomplete (fix: re-run the idempotent seed,
    #    `nabu list --export-source-dossiers`, or scaffold one);
    # 2. a slug docs/library.md mentions (backticked, anywhere) whose
    #    dossier carries NO description — the public map says more than
    #    canonical memory;
    # 3. an ENABLED source with a described dossier that docs/library.md
    #    never mentions — canonical memory says more than the public map
    #    (disabled/pending sources are exempt: MAINTENANCE.md duty 2 puts
    #    a shelf on the map when it goes live, not before);
    # 4. a malformed dossier (it can assert nothing).
    #
    # site/library.md is covered TRANSITIVELY: it is the printed map of
    # docs/library.md, re-synced from it at every gate (site/MAINTENANCE.md
    # duties 1–2), and carries collection names rather than slugs — so the
    # mechanical anchor is docs/library.md, the source of truth. Checked
    # here only for existence when a path is given.
    class DossierDrift
      Finding = Data.define(:slug, :message)

      def initialize(shelf_dir:, registry:, library_md:, site_library_md: nil)
        @shelf = SourceShelf.new(dir: shelf_dir)
        @shelf_dir = shelf_dir
        @registry = registry
        @library_md = library_md
        @site_library_md = site_library_md
      end

      # Every drift finding, slug order. Empty = green.
      def findings
        return [not_seeded] unless Dir.exist?(@shelf_dir)

        findings = @registry.slugs.sort.flat_map { |slug| check(slug) }
        findings << missing_site_file if @site_library_md && !File.file?(@site_library_md)
        findings
      end

      private

      def not_seeded
        Finding.new(slug: SourceShelf::SLUG,
                    message: "shelf not seeded yet (#{@shelf_dir} missing) — " \
                             "run bin/nabu list --export-source-dossiers")
      end

      def missing_site_file
        Finding.new(slug: SourceShelf::SLUG, message: "site library page missing: #{@site_library_md}")
      end

      def check(slug)
        dossier = load(slug)
        return [dossier] if dossier.is_a?(Finding) # missing or malformed

        entry = @registry[slug]
        mentioned = mentioned?(slug)
        if dossier.description.nil?
          return [] unless mentioned

          [Finding.new(slug: slug, message: "docs/library.md describes this shelf but the dossier has " \
                                            "no description — write one (nabu ingest --shelf source #{slug})")]
        elsif !mentioned && entry&.enabled
          [Finding.new(slug: slug, message: "dossier describes an enabled shelf docs/library.md never " \
                                            "mentions — add its row/paragraph (MAINTENANCE.md duty 2)")]
        else
          []
        end
      end

      def load(slug)
        dossier = @shelf.load(slug)
        if dossier.nil?
          return Finding.new(slug: slug, message: "no dossier — run bin/nabu list --export-source-dossiers " \
                                                  "(idempotent) or nabu ingest --shelf source #{slug}")
        end

        dossier
      rescue SourceDossier::FormatError => e
        Finding.new(slug: slug, message: "malformed dossier: #{e.message}")
      end

      def mentioned?(slug)
        library_text.include?("`#{slug}`")
      end

      def library_text
        @library_text ||= File.file?(@library_md) ? File.read(@library_md, encoding: "UTF-8") : ""
      end
    end
  end
end
