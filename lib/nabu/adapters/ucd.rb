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
    # == fetch: the whole UCD in ONE versioned zip + the security pin (P86-1)
    #
    # The unikemet/cigs posture, not /latest/: /Public/17.0.0/ is immutable, so
    # the pin never drifts under us. A new Unicode release (annual cadence) is a
    # NEW pin the owner re-points — sync_policy manual. №R-49(a) widened the
    # ingest from UnicodeData.txt alone to the useful-context member set
    # (Blocks, Scripts, NameAliases, DerivedAge, Jamo, NamesList, radicals,
    # Tangut/Nushu sources…), and they all ride UCD.zip — one artifact, one
    # pin, the Unihan.zip ZipFetch mechanics exactly. №R-49(b) adds
    # confusables.txt, which lives in the SEPARATE /Public/security/ tree with
    # its OWN version cadence (16.0.0 current while the UCD is at 17.0.0 —
    # UTS #39 data lags the main release); it lands under canonical/ucd/
    # security/, FileFetch, its own immutable pin.
    #
    # == License (https://www.unicode.org/license.txt)
    #
    # UNICODE LICENSE V3 (MIT-style: "Permission is hereby granted, free of
    # charge, to any person obtaining a copy of data files…") → class open,
    # exactly the held Unihan/Unikemet class.
    class Ucd < Nabu::Adapter
      VERSION = "17.0.0"
      ZIP_URL = "https://www.unicode.org/Public/#{VERSION}/ucd/UCD.zip".freeze

      # UTS #39 security data: its own version line, deliberately pinned where
      # it actually exists (the security tree had no 17.0.0 as of 2026-08-28).
      SECURITY_VERSION = "16.0.0"
      SECURITY_DIRNAME = "security"
      CONFUSABLES_URL =
        "https://www.unicode.org/Public/security/#{SECURITY_VERSION}/confusables.txt".freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ucd",
        name: "UCD — Unicode Character Database core (universal character-identity instrument)",
        license: "UNICODE LICENSE V3 (unicode.org/license.txt, verbatim: \"Permission is hereby " \
                 "granted, free of charge, to any person obtaining a copy of data files and any " \
                 "associated documentation…\") — MIT-style, the Unihan/Unikemet class",
        license_class: "open",
        upstream_url: ZIP_URL,
        parser_family: "ucd-txt"
      )

      def self.manifest = MANIFEST

      # Two unicode.org pins — HEAD for liveness, Last-Modified or URL
      # identity for drift: the UCD.zip artifact and the security-tree
      # confusables file (its own cadence, its own state under security/).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [
          Nabu::Adapter::HttpProbeTarget.new(
            label: "UCD.zip", zip_url: ZIP_URL, metadata_url: nil,
            state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
          ),
          Nabu::Adapter::HttpProbeTarget.new(
            label: "confusables.txt", zip_url: CONFUSABLES_URL, metadata_url: nil,
            state_subdir: SECURITY_DIRNAME, state_file: Nabu::FileFetch::STATE_FILE
          )
        ]
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

      # The zip lands the whole member tree; `keep:` shields the sibling
      # security/ pin (a different fetch's files) from the zip's
      # upstream-deletion sweep. The confusables FileFetch then lands/refreshes
      # security/confusables.txt under its own state file.
      def fetch(workdir, progress: nil, force: false)
        zip = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, keep: ["#{SECURITY_DIRNAME}/"],
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        confusables = Nabu::FileFetch.sync!(
          url: CONFUSABLES_URL, dir: File.join(workdir, SECURITY_DIRNAME),
          filename: "confusables.txt",
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        FetchReport.new(sha: zip.sha, fetched_at: Time.now,
                        notes: fetch_notes(zip, confusables))
      rescue Nabu::ZipFetch::Error, Nabu::FileFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "ucd fetch failed into #{workdir}: #{e.message}"
      end

      private

      def fetch_notes(zip, confusables)
        parts = []
        parts << "UCD.zip already up to date" if zip.respond_to?(:not_modified) && zip.not_modified
        parts << "confusables (security #{SECURITY_VERSION}) already up to date" if confusables.not_modified
        parts.empty? ? nil : parts.join("; ")
      end
    end
  end
end
