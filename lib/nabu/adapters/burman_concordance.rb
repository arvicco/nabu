# frozen_string_literal: true

require "digest"
require_relative "../url_download"
require_relative "../burman_crosswalk"

module Nabu
  module Adapters
    # The Burman concordance (P77-r19, №R-33 PKG-1): Annie Burman's
    # "Digital Concordance of Etruscan, Faliscan and Early Latin
    # Inscriptions from Etruria" (Uppsala; Zenodo 7801485 v1.0.0,
    # PUBLIC DOMAIN per the deposit — legalcode.txt is CC0) — 14,986
    # rows crosswalking Trismegistos, CIE, Rix ET1, Meiser ET2, TLE,
    # Bakkum, five CIL volumes and the CII series, one row per
    # inscription.
    #
    # A LINKS INSTRUMENT, the trismegistos shape: discover mints no
    # documents — the data is links-graph edges. The producer
    # (Nabu::BurmanCrosswalk) reads the canonical CSV and mints
    # kind=reference edges from the held open-etruscan documents
    # (CIE-keyed, urn cie-<n>) to the same `tm:<id>` identity urns the
    # TrismegistosCrosswalk aggregates — plugging the Etruscan corpus
    # into the existing same-inscription hub, the full concordance line
    # riding each edge's detail.
    class BurmanConcordance < Nabu::Adapter
      CSV_URL = "https://zenodo.org/records/7801485/files/" \
                "A%20Digital%20Concordance%20of%20Etruscan,%20Faliscan%20and%20Etrurian%20Latin%201.0.0.csv"
      CSV_FILENAME = "burman-concordance.csv"

      MANIFEST = Nabu::SourceManifest.new(
        id: "burman-concordance",
        name: "Burman — Digital Concordance of Etruscan, Faliscan and Early Latin Inscriptions",
        license: "Public Domain / CC0 (the Zenodo deposit's license field + in-record " \
                 "legalcode.txt, record 7801485 v1.0.0, read 2026-08-17)",
        license_class: "open",
        upstream_url: "https://zenodo.org/records/7801485",
        parser_family: "burman-crosswalk",
        credit: "Annie Cecilia Burman (Uppsala University), A Digital Concordance of " \
                "Etruscan, Faliscan and Early Latin Inscriptions from Etruria, v1.0.0, " \
                "Zenodo, doi:10.5281/zenodo.7801485"
      )

      def self.manifest
        MANIFEST
      end

      # P79-2: UrlDownload keeps no state file — the probe HEADs the
      # Zenodo CSV for liveness only; drift honestly reads unknown.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "concordance csv", zip_url: CSV_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # The capability flag SyncRunner keys the reference pass on — without
      # it the producer below is never invoked (the 2026-08-18 first sync:
      # a clean fetch, zero edges, silently).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        Nabu::BurmanCrosswalk.new(catalog: catalog, journal: journal)
      end

      # One stable-URL CSV; downloaded under its house name so the
      # producer's read path never depends on Zenodo's escaping.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        target = File.join(workdir, CSV_FILENAME)
        downloaded = Nabu::UrlDownload.new.fetch(CSV_URL, dir: workdir)
        FileUtils.mv(downloaded, target) unless downloaded == target
        Nabu::FetchReport.new(sha: Digest::SHA256.file(target).hexdigest, fetched_at: Time.now,
                              notes: ["#{CSV_FILENAME} (#{File.size(target)} bytes)"])
      end

      # A links instrument mints no documents — empty by design, not by
      # accident (the trismegistos/bridging shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: burman-concordance is a links instrument, not a " \
                          "text source — its crosswalk rides the links journal " \
                          "(Nabu::BurmanCrosswalk); parse is unreachable"
      end
    end
  end
end
