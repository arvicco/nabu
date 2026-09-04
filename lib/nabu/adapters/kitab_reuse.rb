# frozen_string_literal: true

require_relative "../kitab_reuse"

module Nabu
  module Adapters
    # KITAB text-reuse data (P96-5), registered as a FEATURE MODULE:
    # the acquisition arm for KitabReuse — one 164 MB stats TSV from the
    # versioned Zenodo record (11501559, v2023.1.8; CC BY-NC-SA 4.0 →
    # nc), fetched whole and kept gzipped; the producer streams it into
    # kind=reuse document-grain edges over the held openiti corpus
    # after every sync. The 10 GB passage-grain pairwise archive on the
    # same record is a deliberate v2 (owner-fired when wanted).
    class KitabReuse < Nabu::Adapter
      STATS_URL = "https://zenodo.org/records/11501559/files/" \
                  "KITAB-TextReuse-stats_2023-1-8.csv.gz?download=1"
      FILENAME = Nabu::KitabReuse::STATS_FILENAME

      MANIFEST = Nabu::SourceManifest.new(
        id: "kitab-reuse",
        name: "KITAB Text Reuse Data — pairwise statistics (intertext instrument)",
        license: "CC BY-NC-SA 4.0 (Zenodo record 11501559 v2023.1.8, license field verbatim " \
                 "cc-by-nc-sa-4.0; cite the KITAB project, Aga Khan University)",
        license_class: "nc",
        upstream_url: "https://doi.org/10.5281/zenodo.11501559",
        parser_family: "kitab-reuse-tsv"
      )

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "reuse stats", zip_url: STATS_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # The reuse edges refresh through the reference-producer seam after
      # every sync of THIS module (the workdir carries the stats file).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        Nabu::KitabReuse.new(catalog: catalog, journal: journal)
      end

      # A feature module mints no documents.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: kitab-reuse is an intertext instrument, not a " \
                          "text source — its data derives into the links journal"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: STATS_URL, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date" : "stats TSV landed (164 MB)")
      rescue Nabu::FileFetch::Error => e
        raise Nabu::FetchError, "kitab-reuse fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
