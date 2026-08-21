# frozen_string_literal: true

require_relative "sentence_lines_parser"

module Nabu
  module Adapters
    # Şalom Ladino articles text corpus (P80-6): the Hugging Face dataset
    # `collectivat/salom-ladino-articles` — 10,685 Ladino (Judeo-Spanish,
    # `lad`) sentences compiled from 397 articles of the Judeo-Espanyol
    # section of Şalom newspaper (Istanbul), by Col·lectivaT and the
    # Sephardic Center of Istanbul; the corpus behind "Preparing an
    # Endangered Language for the Digital Age: The Case of Judeo-Spanish"
    # (EURALI 2022). Latin-script Turkish-style orthography.
    #
    # == Identity (the honest shape)
    #
    # Upstream ships ONE txt artifact, sentences SEGMENTED AND SHUFFLED —
    # article structure is not recoverable, so one document at sentence
    # grain is the honest shape (urn:nabu:salom:articles-2022, named for
    # the artifact's own 2022-01 extraction stamp). Passage identity is
    # the 1-based line number in the local canonical file (the tla-hf
    # precedent; the sentence-lines family keeps numbering physical —
    # upstream's censused `\n\n` tail mints nothing).
    #
    # == License (verbatim, dataset card, verified 2026-08-19)
    #
    # Card frontmatter `license: cc-by-4.0`; prose: "Original sentences
    # and articles belong to Şalom", citation requested → attribution.
    #
    # == fetch / sync policy
    #
    # One FileFetch single-file sync over the plain-HTTPS resolve URL
    # (the tla-hf hf-CLI-free lane; ~1 MB). A revised corpus would be a
    # new filename — an owner re-pin; sync_policy manual.
    class Salom < Nabu::Adapter
      FILENAME = "Salom-ladino-2022-01-ext-04_segmented_shuffled.txt"
      URL = "https://huggingface.co/datasets/collectivat/salom-ladino-articles/resolve/main/" \
            "#{FILENAME}".freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "salom",
        name: "Şalom Ladino articles text corpus (Col·lectivaT / Sephardic Center of Istanbul)",
        license: "CC BY 4.0 (dataset card frontmatter verbatim: \"license: cc-by-4.0\"; original " \
                 "sentences and articles belong to Şalom — cite the EURALI 2022 paper " \
                 "\"Preparing an Endangered Language for the Digital Age\")",
        license_class: "attribution",
        upstream_url: "https://huggingface.co/datasets/collectivat/salom-ladino-articles",
        parser_family: "sentence-lines"
      )

      URN = "urn:nabu:salom:articles-2022"

      def self.manifest
        MANIFEST
      end

      # One HEAD on the resolve URL against the workdir's FileFetch state
      # (reachability + Last-Modified drift). metadata_url nil: the
      # license lives on the dataset card, no probe-shaped endpoint.
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

      # The one articles ref, when the file is present (a workdir without
      # it is the day-one pre-fetch state); the same walk works under the
      # attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, FILENAME)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(
          source_id: manifest.id, id: URN, path: File.expand_path(path),
          metadata: { "language" => "lad",
                      "title" => "Şalom Judeo-Espanyol articles, sentence corpus (2022-01)" }
        )
      end

      # One `lad` passage per non-blank line, NFC at the boundary.
      def parse(document_ref)
        document = Nabu::Document.new(
          urn: document_ref.id, language: "lad", title: document_ref.metadata["title"],
          canonical_path: document_ref.path,
          metadata: { "articles" => 397, "note" => "sentences segmented and shuffled upstream — " \
                                                   "article structure not recoverable" }
        )
        @parser.each_sentence(document_ref.path) do |number, text|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{number}", language: "lad",
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
        raise Nabu::FetchError, "salom fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
