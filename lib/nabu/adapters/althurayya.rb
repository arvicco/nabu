# frozen_string_literal: true

require_relative "../althurayya_index"

module Nabu
  module Adapters
    # al-Ṯurayyā — the gazetteer of the early Islamic world (Maxim Romanov,
    # Masoumeh Seydi et al., U Leipzig; georeferenced from Georgette
    # Cornu's Atlas du monde arabo-islamique à l'époque classique, IXe–Xe
    # siècles, Brill 1983), registered as a FEATURE MODULE (the chgis/nrct
    # shape): discover mints NO documents; each sync derives the "thurayya"
    # place-index slice via AlthurayyaIndex — 2,331 places with Arabic +
    # transliterated name keys, region parents, and WGS84 points.
    #
    # == fetch: the sparse GitFetch cone (the aed recipe)
    #
    # The upstream repo is the live map's site (~620 MB working tree:
    # fonts, tiles, 2,519 legacy per-place files, archived versions). The
    # gazetteer is two files under master/, so fetch is a blobless sparse
    # clone scoped to them plus the license/README — megabytes, not the
    # site. Nothing is materialized beside upstream's tree.
    #
    # == License (repo files verbatim, 2026-10-10)
    #
    # DATA-LICENSE.md (added 2026-09-22): "the original datasets created
    # and curated by the al-Ṯurayyā Gazetteer project are licensed under
    # the Creative Commons Attribution 4.0 International License (CC BY
    # 4.0)" — explicitly covering "curated place records, route records,
    # coordinates, identifiers, transliterations". The repo's Apache-2.0
    # LICENSE (the GitHub spdx) governs the CODE. The data grant is the
    # one that applies here → class attribution.
    class Althurayya < Nabu::Adapter
      REPO_URL = "https://github.com/althurayya/althurayya.github.io.git"

      SPARSE_PATHS = [
        Nabu::AlthurayyaIndex::PLACES_FILE, Nabu::AlthurayyaIndex::REGIONS_FILE,
        "DATA-LICENSE.md", "README.md"
      ].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "althurayya",
        name: "al-Ṯurayyā Gazetteer — the early Islamic world (gazetteer instrument)",
        license: "CC BY 4.0 (DATA-LICENSE.md verbatim: \"licensed under the Creative Commons " \
                 "Attribution 4.0 International License (CC BY 4.0)\"; credit the al-Ṯurayyā " \
                 "Gazetteer Project, https://github.com/althurayya/althurayya.github.io — the " \
                 "repo's Apache-2.0 covers the code)",
        license_class: "attribution",
        upstream_url: "https://althurayya.github.io/",
        parser_family: "althurayya-geojson"
      )

      def self.manifest = MANIFEST

      def self.place_index_producer? = true

      def self.place_index_producer(catalog:)
        Nabu::AlthurayyaIndex::Producer.new(catalog: catalog)
      end

      # A feature module mints no documents (the chgis shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: althurayya is a gazetteer instrument, not a text " \
                          "source — its data derives into the place index; parse is unreachable"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: REPO_URL, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end
    end
  end
end
