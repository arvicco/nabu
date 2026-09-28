# frozen_string_literal: true

require "csv"
require "digest"
require "fileutils"
require_relative "../url_download"

module Nabu
  module Adapters
    # ŠKZ — the trilingual inscription of Šābuhr I at the Kaʿba-ye
    # Zartošt (P107-3b, Q96.3): Shamsian & Berti's sentence- and
    # word-aligned dataset (Zenodo doi 10.5281/zenodo.15050878, CC BY
    # 4.0). THE first real Parthian document in the library, aligned
    # word-for-word with its Middle Persian and Greek versions.
    #
    # == Shape (fixture-verified 2026-09-28)
    #
    # SKZ-sentence-level.csv: one row per ŠKZ line ("ŠKZ Line N"),
    # columns Greek / Parthian transliteration / Parthian transcription
    # / Middle Persian transcription (upstream header typos and all).
    # alignment-pairs.csv: 1,012 word triples — fetched into canonical,
    # DECLARED residue v1 (the shared :l<n> line citation across the
    # three version documents is the served alignment; the word-pair
    # layer awaits the alignment-hub look).
    #
    # == Identity
    #
    # Three version documents — urn:nabu:shkz:{grc,xpr,pal} — each with
    # one passage per line at the SHARED citation :l<n>. Parthian
    # serves the TRANSCRIPTION as text with the transliteration riding
    # annotations (both upstream columns kept).
    class Shkz < Nabu::Adapter
      RECORD = "https://zenodo.org/api/records/15050878/files"
      SENTENCES_URL = "#{RECORD}/SKZ-sentence-level.csv/content".freeze
      PAIRS_URL = "#{RECORD}/alignment-pairs.csv/content".freeze
      SENTENCES_FILE = "SKZ-sentence-level.csv"
      PAIRS_FILE = "alignment-pairs.csv"
      URN_PREFIX = "urn:nabu:shkz:"
      LINE_LABEL = /(\d+)\s*\z/

      # version key => [language, column index, transliteration column]
      VERSIONS = {
        "grc" => ["grc", 1, nil],
        "xpr" => ["xpr", 3, 2],
        "pal" => ["pal", 4, nil]
      }.freeze

      TITLES = {
        "grc" => "ŠKZ — the Greek version",
        "xpr" => "ŠKZ — the Parthian version",
        "pal" => "ŠKZ — the Middle Persian version"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "shkz",
        name: "ŠKZ — the trilingual Kaʿba-ye Zartošt inscription (aligned)",
        license: "CC BY 4.0 (the Zenodo record). Credit Shamsian & Berti, \"Word-level " \
                 "Alignment and Named Entities in the Trilingual Inscription at Ka'ba-ye " \
                 "Zartošt\" (doi 10.5281/zenodo.15050878)",
        license_class: "open",
        upstream_url: "https://doi.org/10.5281/zenodo.15050878",
        parser_family: "shkz-csv"
      )

      def self.manifest = MANIFEST

      # UrlDownload keeps no state file — the probe HEADs the stable
      # upstream URL for liveness only; drift honestly reads unknown.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "sentence csv", zip_url: SENTENCES_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, SENTENCES_FILE)
        return unless File.file?(path)

        VERSIONS.keys.sort.each do |key|
          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{key}",
                                      path: path, metadata: { "version" => key })
        end
      end

      def parse(document_ref)
        key = document_ref.metadata.fetch("version")
        language, column, translit_column = VERSIONS.fetch(key)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language,
          canonical_path: document_ref.path, title: TITLES.fetch(key),
          metadata: { "version" => key,
                      "alignment" => "line citations are shared across the three versions; " \
                                     "the word-pair layer rides canonical as a declared residue" }
        )
        rows(document_ref.path).each do |row|
          label = row[0].to_s[LINE_LABEL, 1] or next
          text = clean(row[column])
          next if text.empty?

          annotations = {}
          if translit_column && !clean(row[translit_column]).empty?
            annotations["transliteration"] = clean(row[translit_column])
          end
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:l#{label}", language: language,
            text: text, sequence: document.passages.size + 1,
            annotations: annotations
          )
        end
        document
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        shas = [[SENTENCES_URL, SENTENCES_FILE], [PAIRS_URL, PAIRS_FILE]].map do |url, name|
          downloaded = Nabu::UrlDownload.new.fetch(url, dir: workdir)
          target = File.join(workdir, name)
          FileUtils.mv(downloaded, target) unless downloaded == target
          Digest::SHA256.file(target).hexdigest
        end
        Nabu::FetchReport.new(sha: Digest::SHA256.hexdigest(shas.join("\n")), fetched_at: Time.now,
                              notes: ["#{SENTENCES_FILE} + #{PAIRS_FILE}"])
      end

      private

      def rows(path)
        @rows_cache ||= {}
        @rows_cache[path] ||= CSV.read(path, encoding: "UTF-8")[1..] || []
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end

      def clean(value)
        Normalize.nfc(value.to_s.gsub(/\s+/, " ").strip)
      end
    end
  end
end
