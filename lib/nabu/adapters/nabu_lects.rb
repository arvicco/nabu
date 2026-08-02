# frozen_string_literal: true

module Nabu
  module Adapters
    # nabu-lects (P57-3) — a small, curated registry of LECTS (language
    # varieties identified by genealogical anchor x historical stage x
    # variety x orthography), with a universal mapping from standard codes
    # (ISO 639, Wiktionary) onto them (github.com/arvicco/nabu-lects),
    # registered as a FEATURE MODULE (kind: module), not a text source (the
    # cldf-spine/nabu-data shape): discover yields NOTHING, parse is
    # unreachable, no catalog table, no migration. `nabu sync nabu-lects`
    # (owner-run) lands the repo under canonical/nabu-lects/, and
    # Nabu::Lects reads its two data files (`lects.yml` the registry,
    # `codemap.yml` the universal code -> lect defaults) — the read seam
    # exercised in test/lects_test.rb. First consumers arrive at P57-4.
    #
    # == fetch: the sanctioned GitFetch gateway, whole repo
    #
    # The repo IS the data bundle (lects.yml + codemap.yml, ~14 KB together,
    # plus docs/README/LICENSE/bin) — no sparse cone, every path is the
    # point (the nabu-data posture). Attic + breaker + ff-merge as
    # everywhere; the owner may pin `ref:` to a tagged release once one
    # exists (the repo is pre-1.0, per its own README's stability note).
    #
    # == License (repo LICENSE, read 2026-08-02)
    #
    # CC BY 4.0 — LICENSE verbatim: "This work — the lect registry
    # (lects.yml), the code mapping (codemap.yml), the documentation, and
    # the validation tooling in this repository — is licensed under the
    # Creative Commons Attribution 4.0 International License."
    class NabuLects < Nabu::Adapter
      REPO_URL = "https://github.com/arvicco/nabu-lects.git"

      MANIFEST = Nabu::SourceManifest.new(
        id: "nabu-lects",
        name: "nabu-lects — the lect registry (anchor x stage x variety x orthography resolver)",
        license: "CC BY 4.0 (repo LICENSE verbatim: \"This work — the lect registry (lects.yml), " \
                 "the code mapping (codemap.yml), the documentation, and the validation tooling in " \
                 "this repository — is licensed under the Creative Commons Attribution 4.0 " \
                 "International License\")",
        license_class: "attribution",
        upstream_url: "https://github.com/arvicco/nabu-lects",
        parser_family: "nabu-lects"
      )

      def self.manifest
        MANIFEST
      end

      # A feature module mints no documents — its data is a read seam
      # (Nabu::Lects), not passages. Empty by design (the nabu-data shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: nabu-lects is a lect registry module, not a text " \
                          "source — its data rides Nabu::Lects (P57-3); parse is unreachable"
      end

      # Clone/update the published repo via the sanctioned GitFetch gateway
      # (attic + breaker + ff-merge). No network in tests.
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
