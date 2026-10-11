# frozen_string_literal: true

require_relative "nkjp_tei_parser"

module Nabu
  module Adapters
    # korba — the KorBa manually annotated subcorpus, version 2.0 (KorBa
    # ręczna; Elektroniczny Korpus Tekstów Polskich z XVII i XVIII w. (do
    # 1772 r.), Instytut Języka Polskiego PAN; P116-1): samples of 17th- and
    # 18th-century Polish texts transcribed in the KORBA 1/2 projects, with
    # MANUAL morphosyntactic annotation (the reference set the corpus's
    # tagger was trained on). Language: Middle Polish, `pl` (the stage claim
    # waits on the nabu-lects mint — config/postures.yml).
    #
    # == Shape (censused 2026-10-10)
    #
    # ONE zip from the project's download page (korba_xml.zip; the
    # /download_corpus link), a single top dir korba_corpus/ holding one
    # directory per text in the NKJP TEI P5 stand-off package (header.xml,
    # text.xml, ann_segmentation.xml, ann_morphosyntax.xml — the nkjp-tei
    # family) beside the corpus-level header files the text files
    # xi:include. ZipFetch strips the top dir; the whole upstream tree lands
    # in canonical/ (no materialized paths). The census copy (the live host
    # answered 502 on 2026-10-10; the Internet Archive's 2024-08-11 capture
    # of the same URL, upstream Last-Modified 2021-06-07, the corpus header
    # "Version 1.2 published" 2021-05-21, c. 0.5M tokens): 850 texts →
    # 850 documents / 6,034 passages / 510,205 tokens (494,601 with a
    # lemma), 0 parse errors; dates 1601–1775 on every text. The download
    # page now advertises version 2.0 (c. 850k segments) — the same NKJP
    # package format is expected; the first live sync re-censuses.
    #
    # Document = one text directory (urn :<dirname>, NFC — the directory
    # name IS the KORBA idno sans prefix). Passage = one <ab> block, cited
    # by its xml:id's numbering ("txt_1.10-ab" → 1.10); the text is the
    # TRANSCRIBED spelling of text.xml, verbatim modulo whitespace. Tokens
    # (gold — manual annotation) ride as annotations: form = translit (the
    # transcribed spelling), orth = the modernized spelling, lemma = the
    # disambiguated base, xpos = ctag[:msd] (the NKJP/KorBa tagset);
    # foreign-language segs carry "lang" and no interpretation (upstream
    # leaves them untagged).
    #
    # == Axes (the aggressive-mining policy)
    #
    # The header's original bibl: date (@when, or @notBefore/@notAfter, raw
    # prose kept) → MetadataDates :structured; pubPlace role=place → place,
    # role=region → region (the corpus's own regional classification);
    # author, publisher; textClass catRefs → facets genre / kind / subject /
    # text_form (prose/verse) verbatim codes (the kind fold over them is a
    # ruled kind_map table — pending). A text keyed from a MODERNIZED
    # edition (a nested bibl type="modernized") records that edition as
    # modernized_edition — its spelling is the editor's, declared.
    #
    # == License
    #
    # The download page, verbatim (Polish): "Pliki źródłowe podkorpusu
    # anotowanego ręcznie (wersja 2.0) można pobrać tutaj (licencja:
    # Creative Commons Attribution Share Alike)", the link targeting the
    # CC BY-SA 4.0 legal code (creativecommons.org/licenses/by-sa/4.0/
    # legalcode.pl). → attribution. Per-text headers carry the NKJP
    # template's availability boilerplate ("See the licence agreement.") —
    # the download page is the grant basis.
    class Korba < Nabu::Adapter
      ZIP_URL = "https://korba.edu.pl/download_corpus"
      URN_PREFIX = "urn:nabu:korba:"
      LANGUAGE = "pl"

      # textClass schemes → facet names (scheme "text" is the prose/verse
      # form; "ironic" is a yes/no flag, kept in metadata only).
      FACET_SCHEMES = { "genre" => "genre", "kind" => "kind", "subject" => "subject",
                        "text" => "text_form" }.freeze

      # The corpus's own absent-value sentinel for pubPlace place/region
      # ("unknown"; censused on ~40% of headers) — mints no place claim.
      UNKNOWN = "nieznane"
      UNKNOWN_KEYS = %w[place region].freeze

      # The corpus header (KorBa_manual_header.xml projectDesc): most
      # samples were annotated by two independent annotators with an
      # adjudicator; samples with "_s" attached to the id had one.
      SINGLE_SUFFIX = "_s"

      MANIFEST = Nabu::SourceManifest.new(
        id: "korba",
        name: "KorBa — manually annotated subcorpus 2.0 (17th–18th-c. Polish, IJP PAN)",
        license: "CC BY-SA 4.0 — the project's download page (korba.edu.pl/download), verbatim: " \
                 "\"Pliki źródłowe podkorpusu anotowanego ręcznie (wersja 2.0) można pobrać tutaj " \
                 "(licencja: Creative Commons Attribution Share Alike)\", linking the CC BY-SA 4.0 " \
                 "legal code. Cite: Elektroniczny Korpus Tekstów Polskich z XVII i XVIII w. (do " \
                 "1772 r.) — KorBa, Instytut Języka Polskiego PAN.",
        license_class: "attribution",
        upstream_url: "https://korba.edu.pl/download",
        parser_family: "nkjp-tei"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "korba_xml.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        notes = [result.not_modified ? "not modified (304)" : "korba_xml.zip unpacked",
                 attic_notes(result.atticked)].compact.join("; ")
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes)
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "korba fetch failed into #{workdir}: #{e.message}"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "*", "text.xml")).each do |path|
          dir = File.dirname(path)
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{Normalize.nfc(File.basename(dir))}",
            path: File.expand_path(dir), metadata: {}
          )
        end
      end

      def parse(document_ref)
        text = NkjpTeiParser.new.parse(document_ref.path)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: text.header["title"] && Normalize.nfc(text.header["title"]),
          metadata: metadata_for(text.header, File.basename(document_ref.path))
        )
        sequence = 0
        text.blocks.each do |block|
          body = Normalize.nfc(block.text)
          next if body.empty?

          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{citation(block.id)}", language: LANGUAGE, text: body,
            sequence: sequence += 1, annotations: annotations_for(block)
          )
        end
        raise Nabu::ParseError, "#{document_ref.id}: no text blocks" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      # "txt_1.10-ab" → "1.10" (upstream's own block numbering).
      def citation(ab_id)
        ab_id.delete_prefix("txt_").delete_suffix("-ab")
      end

      def metadata_for(header, dirname)
        meta = deep_nfc(header.except("title", "classes"))
        meta["annotation"] = dirname.end_with?(SINGLE_SUFFIX) ? "single annotator" : "two annotators + adjudicator"
        UNKNOWN_KEYS.each { |key| meta.delete(key) if meta[key] == UNKNOWN }
        classes = deep_nfc(header["classes"] || {})
        facets = FACET_SCHEMES.each_with_object({}) do |(scheme, facet), out|
          codes = classes[scheme]
          next if codes.nil? || codes.empty?

          raw = codes.join(" ")
          out[facet] = codes.size == 1 ? { "value" => codes.first, "raw" => raw } : { "values" => codes, "raw" => raw }
        end
        meta["classes"] = classes unless classes.empty?
        meta["facets"] = facets unless facets.empty?
        meta
      end

      def annotations_for(block)
        annotations = { "n" => block.n, "pages" => block.pages }.compact
        annotations["foreign"] = deep_nfc(block.foreign) unless block.foreign.empty?
        annotations["uncertain"] = deep_nfc(block.uncertain) unless block.uncertain.empty?
        annotations["tokens"] = deep_nfc(block.tokens) unless block.tokens.empty?
        annotations
      end

      def deep_nfc(value)
        case value
        when String then Normalize.nfc(value)
        when Hash then value.transform_values { |v| deep_nfc(v) }
        when Array then value.map { |v| deep_nfc(v) }
        else value
        end
      end
    end
  end
end
