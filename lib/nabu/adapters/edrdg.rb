# frozen_string_literal: true

require "zlib"

require_relative "kanjidic2_parser"
require_relative "jmdict_parser"

module Nabu
  module Adapters
    # The EDRDG adapter (P32-4): KANJIDIC2 + JMdict from the Electronic
    # Dictionary Research and Development Group — ONE source, TWO
    # dictionaries (the lexica LSJ/L&S precedent): kanjidic2 is the
    # per-kanji shelf (13,108 characters; on/kun/nanori readings, English
    # meanings) whose "U+XXXX" entry ids join Unihan by codepoint, and
    # jmdict (JMdict_e, 217,951 entries) is the modern-Japanese gloss
    # backstop behind it. Language jpn for both.
    #
    # == License (edrdg.org/edrdg/licence.html, read 2026-07-19)
    #
    # Verbatim: "The dictionary files are made available under a Creative
    # Commons Attribution-ShareAlike Licence (V4.0)." — the statement names
    # JMDICT and KANJIDIC2 explicitly, copyright "James William BREEN and
    # The Electronic Dictionary Research and Development Group" →
    # license_class "attribution". The licence prescribes acknowledgement
    # of usage and source; project URLs it offers for that purpose:
    # edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project and
    # edrdg.org/wiki/index.php/KANJIDIC_Project.
    #
    # == fetch / sync policy — NIGHTLY upstream
    #
    # Both files are REBUILT NIGHTLY upstream (verified: Last-Modified
    # 2026-07-19 03:30 GMT on both, in-file build stamps 2026-07-19,
    # database_version 2026-200). A nightly-churning upstream must not look
    # frozen: sync_policy manual states the honest posture — each
    # owner-fired sync adopts that night's build, and the per-dictionary
    # .file-fetch.json Last-Modified pins plus the in-file build stamps
    # (kanjidic2 <date_of_creation>, JMdict's "JMdict created:" comment)
    # date what canonical actually holds. Single-file HTTP via
    # Nabu::FileFetch, one subdir per dictionary (each with its own state
    # file and attic — two files in one dir would doom each other under
    # FileFetch's stale-sibling rule). Canonical keeps the .gz bodies
    # verbatim; parse streams through Zlib::GzipReader (stdlib). The
    # fixtures are plain trimmed slices, so discover accepts both shapes
    # under one stable ref id (the mw zip/plain precedent).
    class Edrdg < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "edrdg",
        name: "EDRDG — KANJIDIC2 + JMdict (Electronic Dictionary Research and Development Group)",
        license: "CC BY-SA 4.0 (verbatim, edrdg.org/edrdg/licence.html: \"The dictionary files are " \
                 "made available under a Creative Commons Attribution-ShareAlike Licence (V4.0).\"; " \
                 "© James William Breen and the EDRDG)",
        license_class: "attribution",
        upstream_url: "http://ftp.edrdg.org/pub/Nihongo/",
        parser_family: "edrdg-xml"
      )

      LANGUAGE = "jpn"

      # The two dictionaries, keyed by dictionary slug, in discover order.
      # `plain` is the fixture/hand-unpacked shape; `gz` is the canonical
      # post-fetch shape (kept verbatim as fetched).
      DICTIONARIES = {
        "kanjidic2" => {
          gz: "kanjidic2.xml.gz", plain: "kanjidic2.xml",
          url: "http://ftp.edrdg.org/pub/Nihongo/kanjidic2.xml.gz",
          title: "KANJIDIC2 — kanji information file (EDRDG)",
          parser: Kanjidic2Parser
        }.freeze,
        "jmdict" => {
          gz: "JMdict_e.gz", plain: "JMdict_e.xml",
          url: "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz",
          title: "JMdict — Japanese-Multilingual Dictionary, English glosses (EDRDG)",
          parser: JmdictParser
        }.freeze
      }.freeze

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The probe HEADs each .gz: reachability + Last-Modified drift vs the
      # per-dictionary .file-fetch.json pin — which, for this nightly
      # upstream, is EXPECTED to drift within a day of any sync.
      # metadata_url nil: the licence is a static page, not a probe shape.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        DICTIONARIES.map do |slug, config|
          Nabu::Adapter::HttpProbeTarget.new(
            label: config.fetch(:gz), zip_url: config.fetch(:url), metadata_url: nil,
            state_subdir: slug, state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      # One DocumentRef per dictionary under ONE stable id regardless of
      # shape: a plain XML (fixtures) wins over the .gz (the real
      # post-fetch canonical). A workdir with neither yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        DICTIONARIES.each do |slug, config|
          path, gzip = dictionary_file(workdir, config)
          next if path.nil?

          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{slug}:#{config.fetch(:plain)}",
            path: File.expand_path(path),
            metadata: gzip ? { "dictionary" => slug, "gzip" => "true" } : { "dictionary" => slug }
          )
        end
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        config = DICTIONARIES.fetch(slug)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: LANGUAGE,
          title: config.fetch(:title), canonical_path: document_ref.path
        )
        each_entry(document_ref, config) { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "edrdg: #{document_ref.id}: #{e.message}"
      rescue Zlib::Error => e
        raise Nabu::ParseError, "edrdg: #{document_ref.id}: corrupt gzip: #{e.message}"
      end

      # Download both .gz files via FileFetch (conditional GET, sha pin,
      # attic + guard contract), one subdir each. No network in tests:
      # WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        results = DICTIONARIES.to_h do |slug, config|
          dir = File.join(workdir, slug)
          [slug, Nabu::FileFetch.sync!(
            url: config.fetch(:url), dir: dir, filename: config.fetch(:gz),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, slug), progress: progress,
            guard: ->(doomed) { guard_mass_deletion!(dir, doomed, force: force) }
          )]
        end
        report(results)
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "edrdg fetch failed into #{workdir}: #{e.message}"
      end

      private

      # [path, gzip?] — plain first, then gz; nil when neither exists.
      def dictionary_file(workdir, config)
        plain = Dir.glob(File.join(workdir, "**", config.fetch(:plain))).min
        return [plain, false] if plain

        gz = Dir.glob(File.join(workdir, "**", config.fetch(:gz))).min
        gz ? [gz, true] : [nil, false]
      end

      def each_entry(document_ref, config, &)
        io = open_io(document_ref)
        begin
          config.fetch(:parser).new.entries(io).each(&)
        ensure
          io.close
        end
      end

      def open_io(document_ref)
        if document_ref.metadata["gzip"]
          Zlib::GzipReader.open(document_ref.path)
        else
          File.open(document_ref.path)
        end
      end

      def report(results)
        notes = results.map { |slug, result| "#{slug}=#{result.sha[0, 12]}" }.join(" ")
        atticked = results.values.flat_map(&:atticked)
        notes = "#{notes} · #{attic_notes(atticked)}" unless atticked.empty?
        Nabu::FetchReport.new(
          sha: results.values.last.sha, fetched_at: Time.now, notes: notes,
          repos: results.to_h { |slug, result| [DICTIONARIES.fetch(slug).fetch(:url), result.sha] }
        )
      end
    end
  end
end
