# frozen_string_literal: true

module Nabu
  module Adapters
    # UCD — the Unicode Character Database core (UnicodeData.txt), registered
    # as a FEATURE MODULE (the unikemet/unihan shape): discover mints NO
    # documents, parse is unreachable, no catalog table. P85: the universal
    # identity backbone of the `nabu char` redesign (№R-44 = Shape C) — a
    # character's NAME, general category, numeric value and canonical
    # decomposition for EVERY code point at once, the "any character, any
    # writing system" floor. Ruby gives script membership and normalization
    # natively but NOT names or numeric values; UnicodeData.txt is the one
    # small, permissive file that supplies them.
    #
    # == fetch: one flat file on the VERSIONED release URL
    #
    # The unikemet/cigs posture, not /latest/: /Public/17.0.0/ is immutable, so
    # the pin never drifts under us. A new Unicode release (annual cadence) is a
    # NEW pin the owner re-points — sync_policy manual. UnicodeData.txt is the
    # core; Blocks.txt (block NAMES) is a planned follow-on (FileFetch is
    # single-file, so a second file needs its own handling).
    #
    # == License (https://www.unicode.org/license.txt)
    #
    # UNICODE LICENSE V3 (MIT-style: "Permission is hereby granted, free of
    # charge, to any person obtaining a copy of data files…") → class open,
    # exactly the held Unihan/Unikemet class.
    class Ucd < Nabu::Adapter
      VERSION = "17.0.0"
      FILENAME = "UnicodeData.txt"
      DUMP_URL = "https://www.unicode.org/Public/#{VERSION}/ucd/#{FILENAME}".freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ucd",
        name: "UCD — Unicode Character Database core (universal character-identity instrument)",
        license: "UNICODE LICENSE V3 (unicode.org/license.txt, verbatim: \"Permission is hereby " \
                 "granted, free of charge, to any person obtaining a copy of data files and any " \
                 "associated documentation…\") — MIT-style, the Unihan/Unikemet class",
        license_class: "open",
        upstream_url: DUMP_URL,
        parser_family: "ucd-txt"
      )

      def self.manifest = MANIFEST

      # One unicode.org dump via FileFetch — HEAD for liveness, Last-Modified
      # (unicode.org serves it) or URL identity for drift.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: DUMP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # A feature module mints no documents (the unikemet/unihan shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: ucd is a character-identity instrument, not a text " \
                          "source — its data rides the (planned) Nabu::Ucd read seam over " \
                          "UnicodeData.txt; parse is unreachable"
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
        raise Nabu::FetchError, "ucd fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
