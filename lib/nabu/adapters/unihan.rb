# frozen_string_literal: true

require_relative "unihan_txt_parser"

module Nabu
  module Adapters
    # The Unihan adapter (P32-4): the Unicode Han Database — the Sinoxenic
    # character bridge's spine, one dictionary entry per CJK codepoint
    # (readings, definition, variant links), shelf keyed by "U+XXXX" so
    # KANJIDIC2 (same key) and the HDIC headword characters join it
    # verbatim. content_kind :dictionary, slug unihan, language zho (the
    # macro tag: Unihan is pan-CJK; the Japanese/Korean/Vietnamese strata
    # ride as fields of the character, not as separate shelves).
    #
    # == Upstream (verified 2026-07-19)
    #
    # Unihan.zip, 8,518,517 bytes, Last-Modified 2025-08-18 (Unicode
    # 17.0.0, in-file date 2025-07-24) at unicode.org/Public/UCD/latest/.
    # Eight member files; the adapter reads Unihan_Readings.txt (67,916
    # codepoints) + Unihan_Variants.txt — the carried-field census and the
    # censused-out fields are documented on UnihanTxtParser. 65,092
    # codepoints carry at least one carried field and mint entries.
    # The /latest/ URL moves with each Unicode release (annual cadence) —
    # sync_policy manual; the .zip-fetch.json Last-Modified pin plus the
    # in-file version headers date every canonical tree.
    #
    # == License (unicode.org/license.txt, read 2026-07-19, verbatim head)
    #
    # "UNICODE LICENSE V3 … Permission is hereby granted, free of charge,
    # to any person obtaining a copy of data files and any associated
    # documentation (the "Data Files") or software and any associated
    # documentation (the "Software") to deal in the Data Files or Software
    # without restriction, including without limitation the rights to use,
    # copy, modify, merge, publish, distribute, and/or sell copies …
    # provided that either (a) this copyright and permission notice appear
    # with all copies of the Data Files or Software, or (b) this copyright
    # and permission notice appear in associated Documentation."
    # → license_class "open" (the notice-preservation condition is the
    # MIT-style shape, not an attribution-class grant).
    #
    # == fetch
    #
    # HTTP-zip via Nabu::ZipFetch (the ORACC path: conditional GET on
    # Last-Modified, sha256 pin, staging, attic + mass-deletion guard);
    # canonical keeps the unpacked member .txt files. The probe HEADs the
    # zip (:http_zip); there is no probe-shaped license endpoint (the
    # license is a static page), so the license row honestly reads
    # unchecked between refetches.
    class Unihan < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "unihan",
        name: "Unihan — the Unicode Han Database",
        license: "Unicode License V3 (unicode.org/license.txt: \"Permission is hereby granted, " \
                 "free of charge, … to deal in the Data Files or Software without restriction …\" " \
                 "with notice preservation; © 1991-2026 Unicode, Inc.)",
        license_class: "open",
        upstream_url: "https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip",
        parser_family: "unihan-txt"
      )

      READINGS_FILE = "Unihan_Readings.txt"
      VARIANTS_FILE = "Unihan_Variants.txt"
      DICTIONARY_SLUG = "unihan"
      LANGUAGE = "zho"
      TITLE = "Unihan — the Unicode Han Database (Unicode Character Database)"

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The probe HEADs the zip itself: reachability + Last-Modified drift
      # vs the .zip-fetch.json pin. metadata_url nil — see the license note.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "Unihan.zip", zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # One DocumentRef for the whole per-codepoint shelf, anchored on the
      # Readings file (the spine); parse reads the Variants sibling from the
      # same directory. A workdir without the file yields nothing (the
      # day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", READINGS_FILE)).min&.then do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{READINGS_FILE}",
            path: File.expand_path(path),
            metadata: { "dictionary" => DICTIONARY_SLUG }
          )
        end
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        UnihanTxtParser.new
                       .entries(document_ref.path,
                                variants_path: File.join(File.dirname(document_ref.path), VARIANTS_FILE),
                                language: LANGUAGE)
                       .each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "unihan: #{document_ref.id}: #{e.message}"
      end

      # Download + unpack Unihan.zip via ZipFetch (conditional GET, sha pin,
      # staging, attic + guard contract). No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: manifest.upstream_url, dir: workdir,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "unihan fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
