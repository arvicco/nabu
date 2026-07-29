# frozen_string_literal: true

module Nabu
  module Adapters
    # nabu-data — the datasets Nabu itself PUBLISHES (github.com/arvicco/
    # nabu-data, built by `nabu data build`) registered back as a FEATURE
    # MODULE (kind: module), not a text source (P51-W6; the lila/cldf-spine
    # shape): discover yields NOTHING, parse is unreachable, no catalog
    # table, no migration. This row closes the two-way loop in public —
    # Nabu consumes its own publication as an ordinary source. `nabu sync
    # nabu-data` (owner-run) lands the repo under canonical/nabu-data/, and
    # Nabu::FormLemma reads `san/form-lemma/form-lemma.csv` (form → lemma
    # candidates for `nabu define`'s Sanskrit lane, D48-a tier 2). The
    # xct/wylie-fold and xct/verb-lemma datasets land with it (future
    # consumer seams).
    #
    # == fetch: the sanctioned GitFetch gateway, whole repo
    #
    # The repo IS the dataset bundle (~53 MB working tree at v1.0.0: three
    # datasets + per-dataset datapackage.json/sources.bib + grants) — no
    # sparse cone; every path is the point (the lila posture minus the
    # sparse list). Attic + breaker + ff-merge as everywhere; the owner may
    # pin `ref:` to a release commit for a reproducible snapshot.
    #
    # == License (repo LICENSE, read 2026-07-29)
    #
    # CC BY 4.0 (LICENSE is the CC BY 4.0 legalcode; CITATION.cff names the
    # repository). Each dataset's datapackage.json carries its own upstream
    # attribution chain — san/form-lemma derives from Hellwig's Digital
    # Corpus of Sanskrit (CC BY 4.0, cited verbatim in `sources`) — so
    # crediting rides per-dataset metadata, class attribution overall.
    class NabuData < Nabu::Adapter
      REPO_URL = "https://github.com/arvicco/nabu-data.git"

      MANIFEST = Nabu::SourceManifest.new(
        id: "nabu-data",
        name: "nabu-data — Nabu's own published datasets, consumed back (form→lemma instrument)",
        license: "CC BY 4.0 (repo LICENSE verbatim; per-dataset datapackage.json carries each " \
                 "dataset's upstream attribution chain — san/form-lemma cites Hellwig, The Digital " \
                 "Corpus of Sanskrit, CC BY 4.0)",
        license_class: "attribution",
        upstream_url: "https://github.com/arvicco/nabu-data",
        parser_family: "nabu-data"
      )

      def self.manifest
        MANIFEST
      end

      # A feature module mints no documents — its data is a read seam
      # (Nabu::FormLemma), not passages. Empty by design (the lila shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: nabu-data is Nabu's own published dataset bundle, " \
                          "not a text source — its data rides Nabu::FormLemma (P51-W6); parse is " \
                          "unreachable"
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
