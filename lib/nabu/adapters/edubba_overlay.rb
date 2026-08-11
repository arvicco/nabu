# frozen_string_literal: true

require_relative "../edubba_overlay"

module Nabu
  module Adapters
    # The Edubba didactic overlay (P72-6) — the sister school's curated
    # hiero-101/102 sign pedagogy + codex sign pages, registered as a
    # FEATURE MODULE (the osl/unikemet shape): discover mints NO
    # documents; the data rides the Nabu::EdubbaOverlay read seam into
    # the P65-2 hiero card, with Edubba's attribution line wherever
    # overlay fields show.
    #
    # == fetch: the sanctioned GitFetch of the site repo
    #
    # A plain GitFetch clone of github.com/arvicco/nabu-edubba (attic +
    # breaker + ff-merge); the seam reads assets-src/data/hiero-10*.yml
    # + site/hieroglyphs/addenda/signs/*.md. Rolling main — Edubba's
    # extraction contract (inbox, 2026-08-11) freezes the FIELD NAMES
    # (additive-only, renames announced in our inbox first), so a
    # re-sync is safe any time; sync_policy manual (course releases,
    # not a nightly feed).
    #
    # == License
    #
    # CC BY-SA 4.0 per the contract's attribution line ("Didactic
    # overlay: Edubba (edubba.ac) · CC BY-SA 4.0") → class attribution
    # (the D51-a BY-SA precedent). The frequency TSVs in the same repo
    # derive FROM Nabu and are NEVER re-imported (circularity guard).
    class EdubbaOverlay < Nabu::Adapter
      REPO_URL = "https://github.com/arvicco/nabu-edubba"

      MANIFEST = Nabu::SourceManifest.new(
        id: "edubba-overlay",
        name: "Edubba didactic overlay — hiero sign pedagogy (module)",
        license: "CC BY-SA 4.0 (the extraction contract's attribution line: " \
                 "\"Didactic overlay: Edubba (edubba.ac) · CC BY-SA 4.0\")",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "edubba-overlay"
      )

      def self.manifest
        MANIFEST
      end

      # A feature module mints no documents (the osl/unikemet shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: edubba-overlay is a didactic instrument, not a " \
                          "text source — its data rides the Nabu::EdubbaOverlay read seam " \
                          "(P72-6); parse is unreachable"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end
    end
  end
end
