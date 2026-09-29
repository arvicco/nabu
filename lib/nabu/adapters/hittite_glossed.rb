# frozen_string_literal: true

require "csv"
require "digest"
require "fileutils"

require_relative "../url_download"
require_relative "../normalize"

module Nabu
  module Adapters
    # hittite-glossed — "Glossed Hittite Texts with German Translation
    # for Machine Learning" (P109-3): 7,099 Hittite texts / 170,496
    # glossed word rows in ONE CSV from a versioned Zenodo record
    # (DOI 10.5281/zenodo.14266302 v1.0, license cc-by-4.0 on the
    # record, re-verified 2026-09-29; paper
    # aclanthology.org/2025.alp-1.10/). Beside the held TLHdig
    # fragment mass this is the desk's glossed layer: every token
    # carries broad transcription, syllabic transliteration, a
    # morphological gloss, and a German translation gloss.
    #
    # == Grain
    #
    # Document = one text (the txtid publication id — KUB/KBo/IBoT…,
    # the same manuscript-id family TLHdig URNs carry; slugged the
    # TLHdig way: NFC, downcase, whitespace → "."). Passage = one
    # manuscript line: consecutive same-lnr token runs in file order,
    # ordinal urns (:l1…) because upstream indexes a handful of
    # tablets under TWO CTH numbers, repeating their lines — the line
    # label rides as the "line" annotation, and on those multi-CTH
    # texts each passage also carries its "cth". Passage text = the
    # word tokens space-joined; the transliteration joins the same
    # way; gloss and German ride " | "-joined so token alignment
    # survives (empty gloss slots — 27 corpus-wide — keep their
    # position).
    #
    # == Axes (№R-70)
    #
    # The CSV's axis-shaped field is cth_number: emitted as the same
    # "cth" facet shape TLHdig emits ({"value" =>, "raw" => "CTH n"}),
    # so the two sources join on the catalog surface. No date or
    # place fields exist in the asset — undatable/unplaced are honest.
    class HittiteGlossed < Nabu::Adapter
      FILE_NAME = "7000_hitt_txts_wGloss.csv"
      FILE_URL = "https://zenodo.org/api/records/14266302/files/#{FILE_NAME}/content".freeze
      RELEASE_SHA256 = "25fd1e44940f4327ce2448c7d25eb728f2ecb345bb76c94f05fed66cca0e0129"
      URN_PREFIX = "urn:nabu:hittite-glossed:"
      LANGUAGE = "hit"

      MANIFEST = Nabu::SourceManifest.new(
        id: "hittite-glossed",
        name: "Glossed Hittite Texts with German Translation (Zenodo)",
        license: "CC BY 4.0 (the Zenodo record's license field, 10.5281/zenodo.14266302 v1.0, " \
                 "read 2026-09-29). Cite the record and the ALP 2025 paper " \
                 "(aclanthology.org/2025.alp-1.10)",
        license_class: "open",
        upstream_url: "https://doi.org/10.5281/zenodo.14266302",
        parser_family: "glossed-csv"
      )

      def self.manifest = MANIFEST

      # UrlDownload keeps no state file — the probe HEADs the versioned
      # file URL for liveness only.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "corpus csv", zip_url: FILE_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        target = File.join(workdir, FILE_NAME)
        downloaded = Nabu::UrlDownload.new.fetch(FILE_URL, dir: workdir)
        FileUtils.mv(downloaded, target) unless downloaded == target
        sha = Digest::SHA256.file(target).hexdigest
        verify_pin!(sha)
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: ["#{FILE_NAME} (#{File.size(target)} bytes), v1.0 sha pin verified"])
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, FILE_NAME)
        return unless File.file?(path)

        texts(path).each_key do |txtid|
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{slug(txtid)}",
            path: File.expand_path(path), metadata: { "txtid" => txtid }
          )
        end
      end

      def parse(document_ref)
        txtid = document_ref.metadata.fetch("txtid")
        rows = texts(document_ref.path)[txtid] or
          raise Nabu::ParseError, "#{document_ref.id}: text #{txtid.inspect} not in the CSV (stale ref?)"

        cths = rows.map { |row| row["cth_number"].to_s.strip }.reject(&:empty?).uniq
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE,
          canonical_path: document_ref.path,
          title: title_for(txtid, cths), metadata: metadata_for(cths)
        )
        build_lines(rows).each_with_index do |line, index|
          document << build_passage(document_ref.id, line, index, multi_cth: cths.size > 1)
        end
        raise Nabu::ParseError, "#{document_ref.id}: no lines parsed" if document.empty?

        document
      end

      private

      def verify_pin!(sha)
        return if sha == @pin

        raise Nabu::FetchError,
              "hittite-glossed: downloaded CSV sha #{sha} does not match the pinned #{@pin} — " \
              "upstream minted a new artifact; re-verify the record and bump the pin"
      end

      # txtid → its token rows in file order, memoized per (path,
      # mtime): discover + 7,099 parses must not re-read a 170k-row
      # CSV per document.
      def texts(path)
        key = [path, File.mtime(path)]
        return @texts_cache if defined?(@texts_key) && @texts_key == key

        @texts_key = key
        @texts_cache = CSV.foreach(path, headers: true, encoding: "UTF-8")
                          .group_by { |row| row["txtid"] }
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end

      # The TLHdig manuscript-slug scheme: NFC, downcase, whitespace
      # runs → "." — censused collision-free over all 7,099 txtids.
      def slug(txtid)
        txtid.strip.unicode_normalize(:nfc).downcase.gsub(/\s+/, ".")
      end

      def title_for(txtid, cths)
        base = Normalize.nfc(txtid.strip)
        cths.size == 1 ? "#{base} (CTH #{cths.first})" : base
      end

      def metadata_for(cths)
        meta = {}
        unless cths.empty?
          meta["cth_numbers"] = cths
          meta["facets"] = { "cth" => { "value" => cths.first, "raw" => "CTH #{cths.first}" } }
        end
        meta
      end

      # Consecutive same-lnr runs, in file order.
      def build_lines(rows)
        rows.chunk_while { |a, b| a["lnr"] == b["lnr"] && a["cth_number"] == b["cth_number"] }
      end

      def build_passage(urn, tokens, index, multi_cth:)
        annotations = {
          "line" => Normalize.nfc(tokens.first["lnr"].to_s.strip),
          "translit" => join_layer(tokens, "translit", " "),
          "gloss" => join_layer(tokens, "gloss", " | "),
          "trans_de" => join_layer(tokens, "trans_de", " | ")
        }
        annotations["cth"] = tokens.first["cth_number"].to_s.strip if multi_cth
        Nabu::Passage.new(
          urn: "#{urn}:l#{index + 1}", language: LANGUAGE,
          text: join_layer(tokens, "word", " "),
          sequence: index + 1, annotations: annotations
        )
      end

      def join_layer(tokens, field, separator)
        Normalize.nfc(tokens.map { |row| row[field].to_s.strip }.join(separator))
      end
    end
  end
end
