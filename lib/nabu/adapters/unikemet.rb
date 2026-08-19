# frozen_string_literal: true

require_relative "../hieroglyphs"

module Nabu
  module Adapters
    # Unikemet — Unicode's normative Egyptian Hieroglyph data file
    # (Unikemet.txt, a UCD member since 15.0; 5,067 signs at 17.0 with
    # Gardiner-plus catalog codes, descriptions, functions, phonetic values
    # and the JSesh/Hieroglyphica/IFAO concordances), registered as a
    # FEATURE MODULE (the osl shape): discover mints NO documents, no
    # migration, no catalog table. The data is the Nabu::Hieroglyphs read
    # seam over canonical/unikemet/Unikemet.txt — the Egyptian sign spine
    # of the P65-2 `nabu char` card, exactly Unihan's role for the Han card.
    #
    # == fetch: one flat file on the VERSIONED release URL
    #
    # The cigs posture, not Unihan's /latest/: /Public/17.0.0/ is immutable,
    # so the pin never drifts under us. A new Unicode release (annual
    # cadence, next 18.0) is a NEW pin the owner re-points — sync_policy
    # manual.
    #
    # == License (https://www.unicode.org/license.txt, verbatim opening)
    #
    # "UNICODE LICENSE V3 … Permission is hereby granted, free of charge,
    # to any person obtaining a copy of data files and any associated
    # documentation…" (MIT-style) → class open. The same license class as
    # the held Unihan source.
    class Unikemet < Nabu::Adapter
      DUMP_URL = "https://www.unicode.org/Public/17.0.0/ucd/Unikemet.txt"
      FILENAME = Nabu::Hieroglyphs::FILE

      MANIFEST = Nabu::SourceManifest.new(
        id: "unikemet",
        name: "Unikemet — Unicode Egyptian Hieroglyph data (sign spine instrument)",
        license: "UNICODE LICENSE V3 (unicode.org/license.txt, verbatim: \"Permission is hereby " \
                 "granted, free of charge, to any person obtaining a copy of data files and any " \
                 "associated documentation…\") — MIT-style, the Unihan class",
        license_class: "open",
        upstream_url: DUMP_URL,
        parser_family: "unikemet-txt"
      )

      def self.manifest
        MANIFEST
      end

      # P79-2: one unicode.org dump via FileFetch — HEAD for liveness,
      # Last-Modified (unicode.org serves it) or URL identity for drift.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "Unikemet.txt", zip_url: DUMP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # A feature module mints no documents (the osl/cigs shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: unikemet is a sign-spine instrument, not a text " \
                          "source — its data rides the Nabu::Hieroglyphs read seam over " \
                          "Unikemet.txt (P65-2); parse is unreachable"
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
        raise Nabu::FetchError, "unikemet fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
