# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "../nrct_index"
require_relative "../url_download"

module Nabu
  module Adapters
    # NRCT — the 日本歴史地名大系 placename dataset (P108-2), registered
    # as a FEATURE MODULE (the chgis/cigs shape): discover mints NO
    # documents; each sync derives the "nrct" place-index slice via
    # NrctIndex — 80,502 historical Japanese placenames with 名称 +
    # 読み + 歴史地名 name keys, WGS84 points, and the 上位地名 parent
    # discriminator.
    #
    # == fetch: one CC BY 4.0 CSV (read 2026-09-29)
    #
    # The geoshape download page links the dated cut directly
    # (dataset/nrct-20250719.csv, ~10.7 MB); a NEW cut is a deliberate
    # CSV_URL bump, recorded here with its census.
    class Nrct < Nabu::Adapter
      CSV_URL = "https://geoshape.ex.nii.ac.jp/nrct/dataset/nrct-20250719.csv"

      MANIFEST = Nabu::SourceManifest.new(
        id: "nrct",
        name: "NRCT — 日本歴史地名大系 historical placenames (gazetteer instrument)",
        license: "CC BY 4.0 (the dataset page's stated license, DOI 10.20676/00000448; " \
                 "credit 平凡社『日本歴史地名大系』and ROIS-DS/NII geoshape as publisher)",
        license_class: "attribution",
        upstream_url: "https://geoshape.ex.nii.ac.jp/nrct/",
        parser_family: "nrct-csv"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "placename csv", zip_url: CSV_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      def self.place_index_producer? = true

      def self.place_index_producer(catalog:)
        Nabu::NrctIndex::Producer.new(catalog: catalog)
      end

      # A feature module mints no documents (the chgis shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: nrct is a gazetteer instrument, not a text source — " \
                          "its data derives into the place index; parse is unreachable"
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        downloaded = Nabu::UrlDownload.new.fetch(CSV_URL, dir: workdir)
        target = File.join(workdir, Nabu::NrctIndex::CSV_FILENAME)
        FileUtils.mv(downloaded, target) unless downloaded == target
        Nabu::FetchReport.new(sha: Digest::SHA256.file(target).hexdigest, fetched_at: Time.now,
                              notes: ["#{Nabu::NrctIndex::CSV_FILENAME} (#{File.size(target)} bytes)"])
      end
    end
  end
end
