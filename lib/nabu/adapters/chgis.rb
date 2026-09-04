# frozen_string_literal: true

require_relative "../chgis"

module Nabu
  module Adapters
    # CHGIS — the China Historical GIS Temporal Gazetteer (Harvard–Fudan),
    # registered as a FEATURE MODULE (the cigs/pleiades shape): discover
    # mints NO documents; each sync derives the "chgis" place-index slice
    # via ChgisIndex — 82,117 historical placenames with hanzi + pinyin
    # name keys, year spans, and WGS84 points.
    #
    # == fetch: one CC0 Dataverse artifact (P96-0 read, 2026-09-04)
    #
    # The TGAZ 2018 backup rides a stable Dataverse datafile URL (file id
    # 3370559 under doi:10.7910/DVN/H3OB28), 21.6 MB zip → the 122 MB SQL
    # dump. The dataset's own license field: CC0 1.0 (the separate legacy
    # "CHGIS V6 EULA" record covers third-party redistribution of the
    # official-distributor copies; the Dataverse CC0 deposits are
    # Harvard's own grant and govern this artifact — recorded for
    # transparency).
    class Chgis < Nabu::Adapter
      ZIP_URL = "https://dataverse.harvard.edu/api/access/datafile/3370559"

      MANIFEST = Nabu::SourceManifest.new(
        id: "chgis",
        name: "CHGIS/TGAZ — China Historical GIS Temporal Gazetteer (gazetteer instrument)",
        license: "CC0 1.0 (the Dataverse dataset's own license field, doi:10.7910/DVN/H3OB28; " \
                 "cite Berman, Bol et al., China Historical GIS)",
        license_class: "open",
        upstream_url: "https://doi.org/10.7910/DVN/H3OB28",
        parser_family: "chgis-sql"
      )

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "tgaz zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      def self.place_index_producer? = true

      def self.place_index_producer(catalog:)
        Nabu::ChgisIndex::Producer.new(catalog: catalog)
      end

      # A feature module mints no documents (the cigs shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: chgis is a gazetteer instrument, not a text source — " \
                          "its data derives into the place index; parse is unreachable"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date" : nil)
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "chgis fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
