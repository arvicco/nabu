# frozen_string_literal: true

require_relative "sentence_lines_parser"

module Nabu
  module Adapters
    # Common Voice Sardinian sentence text (P80-6): the `sc` locale's
    # sentence-collector file in Mozilla's common-voice repository —
    # server/data/sc/sentence-collector.txt, 5,237 sentences censused
    # 2026-08-19. THE TEXT SIDE ONLY — no audio, ever: the audio datasets
    # are account-gated (they fail the automation bar) and out of scope by
    # owner rule; the sentence text is CC0 on a stable public raw URL.
    #
    # == Identity and language
    #
    # One document (urn:nabu:cv-sardinian:sentence-collector); passage
    # identity is the 1-based line number in the local canonical file (the
    # tla-hf precedent — upstream ships no sentence ids; the
    # sentence-lines family keeps numbering physical). `sc` is Common
    # Voice's ISO 639-1 code for Sardinian — passages are `srd` (the
    # registry's own bare-anchor identity example). The artifact ends
    # WITHOUT a trailing newline (censused; the family yields the final
    # sentence regardless).
    #
    # == License (verified 2026-08-19)
    #
    # server/data/LICENSE in the same tree is the full text of CC0 1.0
    # Universal — Common Voice accepts sentence submissions only under
    # CC0/public domain → class open.
    #
    # == fetch / sync policy
    #
    # One FileFetch single-file sync over the raw.githubusercontent URL
    # (the plain-HTTPS lane; ~260 kB). The file tracks the repo's main
    # branch — a living collection, so drift rides Last-Modified/sha
    # against the FileFetch state; sync_policy manual (owner-fired).
    class CvSardinian < Nabu::Adapter
      URL = "https://raw.githubusercontent.com/common-voice/common-voice/" \
            "main/server/data/sc/sentence-collector.txt"
      FILENAME = "sentence-collector.txt"

      MANIFEST = Nabu::SourceManifest.new(
        id: "cv-sardinian",
        name: "Common Voice Sardinian sentence text (the sc sentence collector)",
        license: "CC0 1.0 Universal (server/data/LICENSE is the full CC0 text — Common Voice " \
                 "accepts sentences only under CC0/public domain; the TEXT side only, no audio)",
        license_class: "open",
        upstream_url: "https://github.com/common-voice/common-voice",
        parser_family: "sentence-lines"
      )

      URN = "urn:nabu:cv-sardinian:sentence-collector"

      def self.manifest
        MANIFEST
      end

      # One HEAD on the raw URL against the workdir's FileFetch state
      # (reachability + Last-Modified drift). metadata_url nil: the
      # license lives in server/data/LICENSE, no probe-shaped endpoint.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      def initialize
        super
        @parser = SentenceLinesParser.new
      end

      # The one sentence-collector ref, when the file is present (a
      # workdir without it is the day-one pre-fetch state); the same walk
      # works under the attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, FILENAME)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(
          source_id: manifest.id, id: URN, path: File.expand_path(path),
          metadata: { "language" => "srd", "title" => "Common Voice Sardinian sentences" }
        )
      end

      # One `srd` passage per non-blank line, NFC at the boundary.
      def parse(document_ref)
        document = Nabu::Document.new(
          urn: document_ref.id, language: "srd", title: document_ref.metadata["title"],
          canonical_path: document_ref.path, metadata: {}
        )
        @parser.each_sentence(document_ref.path) do |number, text|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{number}", language: "srd",
            text: Normalize.nfc(text), sequence: number - 1
          )
        end
        raise ParseError, "#{document_ref.path}: no sentences" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # One FileFetch single-file sync (the cigs shape).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: URL, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date" : nil)
      rescue Nabu::FileFetch::Error => e
        raise Nabu::FetchError, "cv-sardinian fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
