# frozen_string_literal: true

require_relative "../cigs"

module Nabu
  module Adapters
    # CIGS — the Cuneiform Inscriptions Geographical Site Index (Uppsala,
    # "Geomapping Landscapes of Writing"; published through CDLI's journal,
    # CDLJ 2021-1 — CDLI's place authority in practice), registered as a
    # FEATURE MODULE (the pleiades shape): discover mints NO documents; each
    # sync derives the "cigs" place-index slice + the cigs crosswalk slice
    # (its own Pleiades/GeoNames/CDLI-provenience columns) via CigsIndex.
    #
    # == fetch: one Zenodo-pinned CSV (the pleiades FileFetch posture)
    #
    # 597 sites / 158 kB on a stable versioned Zenodo URL — trivially inside
    # the automation bar. A new CIGS release is a new record URL the owner
    # re-pins (check for releases newer than v1.7 at first sync; the concept
    # DOI resolved to v1.7 on 2026-08-07).
    #
    # == License (verbatim, zenodo.org/records/14568765, 2026-08-07)
    #
    # "Creative Commons Attribution 4.0 International" → class attribution.
    class Cigs < Nabu::Adapter
      DUMP_URL = "https://zenodo.org/records/14568765/files/cigs_v1_7_20241215.csv?download=1"
      FILENAME = Nabu::CigsIndex::CSV_FILENAME

      MANIFEST = Nabu::SourceManifest.new(
        id: "cigs",
        name: "CIGS — Cuneiform Inscriptions Geographical Site Index (gazetteer instrument)",
        license: "CC BY 4.0 (Zenodo record verbatim: \"Creative Commons Attribution 4.0 " \
                 "International\")",
        license_class: "attribution",
        upstream_url: "https://zenodo.org/records/14568765",
        parser_family: "cigs-csv"
      )

      def self.manifest
        MANIFEST
      end

      # P79-2: one Zenodo-pinned CSV via FileFetch; the deposit is
      # versioned, so a replaced artifact means a NEW file URL — drift
      # rides URL identity against the .file-fetch.json state.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "cigs csv", zip_url: DUMP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      def self.place_index_producer? = true

      def self.place_index_producer(catalog:)
        Nabu::CigsIndex::Producer.new(catalog: catalog)
      end

      # A feature module mints no documents (the pleiades/bridging shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: cigs is a gazetteer instrument, not a text source — " \
                          "its data derives into the place index; parse is unreachable"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: DUMP_URL, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date" : nil)
      rescue Nabu::FileFetch::Error => e
        raise Nabu::FetchError, "cigs fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
