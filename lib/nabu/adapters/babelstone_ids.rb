# frozen_string_literal: true

require_relative "ids_txt_parser"

module Nabu
  module Adapters
    # The BabelStone IDS adapter (P37-4, survey-ratified): Andrew West's
    # Ideographic Description Sequences for every CJK Unified Ideograph —
    # the decomposition spine behind `nabu char`'s structure card and the
    # `search --char-component` transitive-containment index. One
    # DictionaryEntry per codepoint (97,680 at Unicode 16.0), keyed "U+XXXX"
    # so it joins Unihan/KANJIDIC2 verbatim. content_kind :dictionary,
    # slug babelstone-ids, language zho (pan-CJK — IDS is repertoire-wide,
    # not language-scoped). Single UTF-8 file, sha-pinned FileFetch.
    #
    # == Why BabelStone and not cjkvi-ids (P37-0 survey verdict)
    #
    # cjkvi-ids is GPLv2 on the DATA (the maintainer's explicit choice) and
    # stale since 2019; West's file is an independent, heavily-corrected
    # re-derivation at Unicode 16.0 that inherits no copyleft, under a
    # public-domain dedication in prose. The survey ruled cjkvi-ids OUT
    # (dominated), CHISE JOURNAL (GPLv2+ superset, wanted only for
    # dictionary-source glyph-grain decomposition), BabelStone IN.
    #
    # == License (IDS.TXT header §2, verbatim, read 2026-07-20) — `open`
    #
    # "…as IDS descriptions for CJK ideographs are facts not original
    # creative compositions, IDS sequences in themselves are not eligible
    # for copyright protection … Therefore, anyone is free to make use of
    # the IDS data provided in this file for personal or commercial
    # purposes without asking permission or providing attribution. I
    # furthermore waive any copyright claims to the presentation format of
    # the IDS data used in this file…" (Andrew West / 魏安). A public-domain
    # dedication + explicit format waiver — the CC0 posture in prose →
    # license_class "open". Provenance (header §1): West's re-derivation of
    # data from Kawabata Taichi, John Knightley, IRG submissions, in a
    # format he designed that reproduces no pre-existing source's form.
    #
    # == fetch / sync policy
    #
    # Single-file HTTP via Nabu::FileFetch (conditional GET on Last-Modified,
    # sha256 body pin, attic + mass-deletion guard) from babelstone.co.uk.
    # Actively maintained (West targets JMJ glyph checks for Unicode 17.0)
    # but low-cadence and version-stamped in the header → sync_policy manual,
    # enabled: false until the owner-fired first sync. The :http_zip probe
    # HEADs the file (reachability + Last-Modified drift vs the
    # .file-fetch.json pin); metadata_url nil — the licence lives inside the
    # fetched file, re-read at every real fetch.
    class BabelstoneIds < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "babelstone-ids",
        name: "BabelStone IDS — Ideographic Description Sequences for CJK Ideographs (Andrew West)",
        license: "Public-domain dedication (verbatim, IDS.TXT header §2: \"…IDS sequences in " \
                 "themselves are not eligible for copyright protection … anyone is free to make " \
                 "use of the IDS data provided in this file for personal or commercial purposes " \
                 "without asking permission or providing attribution.\"; © Andrew West / 魏安)",
        license_class: "open",
        upstream_url: "https://www.babelstone.co.uk/CJK/IDS.TXT",
        parser_family: "ids-txt"
      )

      FILENAME = "IDS.TXT"
      DICTIONARY_SLUG = "babelstone-ids"
      LANGUAGE = "zho"
      TITLE = "BabelStone IDS — Ideographic Description Sequences for CJK Ideographs"

      def self.manifest = MANIFEST

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # One DocumentRef for the whole per-codepoint shelf, anchored on the
      # single IDS.TXT. A workdir without the file yields nothing (the
      # day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", FILENAME)).min&.then do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{FILENAME}",
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
        IdsTxtParser.new
                    .entries(document_ref.path, language: LANGUAGE)
                    .each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "babelstone-ids: #{document_ref.id}: #{e.message}"
      end

      # Download the single upstream file via FileFetch. No network in tests.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "babelstone-ids fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
