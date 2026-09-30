# frozen_string_literal: true

require "json"

module Nabu
  module Adapters
    # ACLT — the Annotated Corpus of Luwian Texts (P110-2, Q110):
    # Yakubovich's annotated edition of the Hieroglyphic Luwian
    # inscriptions, served at luwian.web-corpora.net on Arkhangelskiy's
    # Tsakorpus platform and delivered for this library as the platform's
    # per-inscription JSON (tsakorpus.readthedocs.io data_model).
    #
    # == Acquisition (ManualDrop — docs/manual/aclt.md)
    #
    # A personal grant, delivered by email as ONE 7z archive — no public
    # fetch URL exists. The owner drops `luwian_aclt.7z` into
    # incoming/aclt/; sync validates (7z magic), moves it into
    # canonical/aclt/ with `.manual-fetch.json` provenance, and extracts
    # the archive's own `luwian_aclt/json/` tree beside it (declared via
    # materialized_paths — the Q59-a rule). A refreshed corpus drops the
    # same way; the sha pin makes an identical re-drop a no-op.
    #
    # == The format and identity (FROZEN minting)
    #
    # One JSON file = one inscription: meta {title, region} + sentences[],
    # the corpus's clause units in TWO representations — lang 0 the broad
    # transcription (words[] carrying morphological analyses: lex,
    # gr.pos/case/gender/num, trans_en glosses) and lang 1 the
    # sign-by-sign hieroglyphic transliteration — grouped lang-0-first,
    # SAME order and count (censused 2026-09-30: 267 files, 0 mismatches),
    # so pairing is the positional zip; the para_alignment ids agree.
    #
    # Document urn = urn:nabu:aclt:<title slug> (the TLHdig scheme: NFC,
    # downcase, whitespace → "." — "KARKAMIŠ A4b" → karkamiš.a4b);
    # passage per clause pair, urn :s<n> in corpus order, text = the
    # broad transcription verbatim (its leading "[lines § n]" marker is
    # upstream's own rendering of the citation that also rides the
    # "line" annotation); the signs/lemmas/gloss layers ride as
    # annotations (the hittite-glossed aligned-layer shape). Upstream's
    # one tombstone file (KARKAMIŠ B39a, "- delete", zero analyzed
    # words) skips by rule.
    #
    # == Language and license
    #
    # hlu (Hieroglyphic Luwian — the nabu-lects anchor; the corpus is the
    # hieroglyphic tradition only, xlu untouched). License: personal
    # grant → research_private; credit the corpus + Yakubovich's
    # editorship as provenance, Tsakorpus named as the technical channel
    # (both promised on the thread).
    class Aclt < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "aclt",
        name: "ACLT — Annotated Corpus of Luwian Texts (Yakubovich)",
        license: "Personal research grant (I. Yakubovich, 2026-09-28; corpus JSON " \
                 "delivered by T. Arkhangelskiy, Tsakorpus platform, 2026-09-29) — not redistributable",
        license_class: "research_private",
        upstream_url: "https://luwian.web-corpora.net/luwian_corpus/search",
        parser_family: "tsakorpus-json"
      )

      ARCHIVE = "luwian_aclt.7z"
      JSON_DIR = File.join("luwian_aclt", "json")
      LANGUAGE = "hlu"
      SEVEN_ZIP_MAGIC = "7z\xBC\xAF\x27\x1C".b

      def self.manifest = MANIFEST

      # A ManualDrop source has no fetch URL to drift against; the probe
      # HEADs the public search UI for liveness only (also the watch
      # surface should a public export ever appear).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "luwian.web-corpora.net", zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # The extracted json tree is the fetch's own artifact beside the
      # held archive (Q59-a): declared, hashed into the tree identity.
      def self.materialized_paths = ["luwian_aclt"]

      def self.drop_dir(workdir)
        File.expand_path(File.join("..", "..", "incoming", "aclt"), workdir)
      end

      def self.manual_acquisition
        @manual_acquisition ||= ManualDrop::Spec.new(
          slug: "aclt",
          upstream_url: "personal grant — the corpus JSON arrives by email from the ACLT team " \
                        "(the public search UI is #{MANIFEST.upstream_url})",
          steps: [
            "Receive (or request a refresh of) the corpus archive from the ACLT team by email",
            "Save the attachment as downloaded — no re-archiving"
          ],
          files: [
            ManualDrop::FileSpec.new(
              name: ARCHIVE,
              description: "the per-inscription Tsakorpus JSON corpus, one 7z archive",
              required: true,
              sniff: lambda { |path|
                File.binread(path, 6) == SEVEN_ZIP_MAGIC ? nil : "not a 7z archive (bad magic bytes)"
              }
            )
          ],
          refresh_hint: "A newer corpus export drops the same way; the sha pin makes an " \
                        "identical re-drop a no-op."
        )
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = Nabu::ManualDrop.sync!(
          spec: self.class.manual_acquisition, drop_dir: self.class.drop_dir(workdir),
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        extract!(workdir) if result.ingested || Dir.glob(File.join(workdir, JSON_DIR, "*.json")).empty?
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date (held manual ingest)" : nil)
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", "luwian-hieroglyph-en_*.json")).filter_map do |path|
          meta = JSON.parse(File.read(path, encoding: "UTF-8")).fetch("meta")
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:aclt:#{slug(meta.fetch('title'))}",
            path: File.expand_path(path),
            metadata: { "title" => meta.fetch("title"), "region" => meta.fetch("region") }
          )
        end.sort_by(&:id).each(&block)
      end

      def parse(document_ref)
        data = JSON.parse(File.read(document_ref.path, encoding: "UTF-8"))
        transcription, signs = data.fetch("sentences").partition { |s| s["lang"].zero? }
        if transcription.sum { |s| analyzed_words(s).size }.zero?
          raise Nabu::DocumentSkipped.new("upstream tombstone", reason: "no analyzed words (upstream tombstone)")
        end

        document = build_document(document_ref, data.fetch("meta"))
        transcription.zip(signs).each_with_index do |(clause, sign_clause), index|
          document << build_passage(document_ref.id, clause, sign_clause, index)
        end
        document
      rescue JSON::ParserError, KeyError => e
        raise Nabu::ParseError, "aclt: #{document_ref.id}: #{e.message}"
      end

      private

      # bsdtar ships with macOS and reads 7z natively; extraction lands
      # the archive's own luwian_aclt/json/ tree (materialized_paths).
      def extract!(workdir)
        Nabu::Shell.run("bsdtar", "-xf", File.join(workdir, ARCHIVE), "-C", workdir)
      end

      # The TLHdig manuscript-slug scheme (the hittite-glossed sibling):
      # NFC, downcase, whitespace → ".".
      def slug(title)
        title.strip.unicode_normalize(:nfc).downcase.gsub(/\s+/, ".")
      end

      def build_document(document_ref, meta)
        region = meta.fetch("region")
        Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE,
          title: Normalize.nfc(meta.fetch("title")),
          canonical_path: document_ref.path,
          metadata: {
            "region" => Normalize.nfc(region),
            "facets" => { "region" => { "value" => Normalize.nfc(region) } },
            "text_nature" => "annotated edition (Tsakorpus JSON)"
          }
        )
      end

      def build_passage(urn, clause, sign_clause, index)
        words = analyzed_words(clause)
        annotations = {
          "line" => Normalize.nfc(clause.dig("meta", "line").to_s.strip),
          "signs" => Normalize.nfc(sign_clause&.fetch("text", "").to_s.strip),
          "lemmas" => join_layer(words, "lex"),
          "gloss" => join_layer(words, "trans_en")
        }.reject { |_, v| v.empty? }
        Nabu::Passage.new(
          urn: "#{urn}:s#{index + 1}", language: LANGUAGE,
          text: Normalize.nfc(clause.fetch("text").strip),
          sequence: index + 1, annotations: annotations
        )
      end

      def analyzed_words(clause)
        clause.fetch("words", []).select { |w| w["wtype"] == "word" }
      end

      # One slot per analyzed word; a word's alternative analyses (ana is
      # an array) join with "/", the word slots with " | " (the
      # hittite-glossed layer shape).
      def join_layer(words, field)
        Normalize.nfc(
          words.map { |w| Array(w["ana"]).filter_map { |a| a[field] }.uniq.join("/") }.join(" | ")
        )
      end
    end
  end
end
