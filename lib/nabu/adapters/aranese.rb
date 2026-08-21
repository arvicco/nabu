# frozen_string_literal: true

require_relative "sentence_lines_parser"

module Nabu
  module Adapters
    # ES-OC (Spanish–Aranese) Parallel Corpus (P80-6): the Hugging Face
    # dataset `projecte-aina/ES-OC_Parallel_Corpus` — BSC Language
    # Technologies Unit, built for the WMT24 shared task "Translation into
    # Low-Resource Languages of Spain". Two line-aligned txt files,
    # 419,908 pairs censused 2026-08-19 (~51 MB each side) — the largest
    # openly licensed Aranese (Occitan of the Val d'Aran) text mass there
    # is.
    #
    # == Provenance honesty (the card's own words — structural, not prose)
    #
    # The corpus is "MAINLY SYNTHETIC", generated with the rule-based
    # translator Apertium: synthetic Spanish from the authentic Aranese
    # PILAR monolingual dataset, synthetic Aranese from the Spanish side
    # of OPUS pairs, plus pairs from the shared-task Diccionari der
    # Aranés. Upstream does not mark which rows are which and warns of
    # possible misalignments. The caveat travels in the MANIFEST LICENSE
    # FIELD and in every parsed document's metadata ("provenance") — held
    # as what it is, never presented as an attested corpus.
    #
    # == Identity and language
    #
    # The Aranese side is the original document (urn:nabu:aranese:corpus,
    # bare `oci` — Aranese is a Gascon variety; the registry distinguishes
    # no Occitan dialects, the lo-congres coarseness stance); the Spanish
    # side rides as the -es sibling (`spa`), line-aligned for
    # Query::Parallel. Passage identity is the 1-based line number (the
    # tla-hf precedent; the sentence-lines family). Equal line counts ARE
    # the format: when both files are present, parse checks the sibling's
    # line count and treats a mismatch as damage.
    #
    # == License (verbatim, dataset card, verified 2026-08-19)
    #
    # Card frontmatter `license: cc-by-sa-4.0`; prose: "This work is
    # licensed under an Attribution-Share Alike 4.0 International" →
    # attribution (the house BY-SA class, the tla-hf precedent).
    #
    # == fetch / sync policy / scale
    #
    # Two FileFetch single-file syncs over the plain-HTTPS resolve URLs,
    # each in its own subdir, two-phase (the tla-hf choreography). ~103 MB
    # total; at LIVE scale the corpus mints 2 documents / ~840k passages —
    # the largest single load of the pack (sync progress narrates, the
    # no-silent-passes rule); sync_policy manual.
    class Aranese < Nabu::Adapter
      HF_BASE = "https://huggingface.co/datasets/projecte-aina/ES-OC_Parallel_Corpus"

      MANIFEST = Nabu::SourceManifest.new(
        id: "aranese",
        name: "ES-OC Parallel Corpus — Spanish–Aranese (BSC projecte-aina, WMT24)",
        license: "CC BY-SA 4.0 (dataset card verbatim: \"This work is licensed under an " \
                 "Attribution-Share Alike 4.0 International\"; the corpus is by the card's own " \
                 "words mainly synthetic — Apertium-generated from PILAR/OPUS — held honestly " \
                 "as such)",
        license_class: "attribution",
        upstream_url: HF_BASE,
        parser_family: "sentence-lines"
      )

      URN = "urn:nabu:aranese:corpus"

      # The two sides: subdir, filename, resolve URL. The arn side is the
      # original; the es side parses only as the -es sibling.
      SIDES = {
        "arn" => { filename: "es-arn_corpus.arn", url: "#{HF_BASE}/resolve/main/es-arn_corpus.arn" }.freeze,
        "es" => { filename: "es-arn_corpus.es", url: "#{HF_BASE}/resolve/main/es-arn_corpus.es" }.freeze
      }.freeze

      def self.manifest
        MANIFEST
      end

      # One HEAD per resolve URL against its subdir's FileFetch state
      # (reachability + Last-Modified drift). metadata_url nil: the
      # license lives on the dataset card, no probe-shaped endpoint.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        SIDES.map do |subdir, side|
          Nabu::Adapter::HttpProbeTarget.new(
            label: side.fetch(:filename), zip_url: side.fetch(:url), metadata_url: nil,
            state_subdir: subdir, state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      # +translations+: when true (the registry row's posture — the
      # Spanish side is the point of a parallel corpus), discover also
      # yields the -es sibling ref over the es-side file.
      def initialize(translations: false)
        super()
        @translations = translations
        @parser = SentenceLinesParser.new
      end

      # The Aranese-side ref when its file is present, plus the -es
      # sibling when opted in AND the es file is present (each side needs
      # its own file; fewer files yield fewer refs — the day-one pre-fetch
      # state). The same walk works under the attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        arn_path = side_path(workdir, "arn")
        if File.file?(arn_path)
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: URN, path: File.expand_path(arn_path),
            metadata: { "language" => "oci", "title" => "ES-OC Parallel Corpus — Aranese side" }
          )
        end
        es_path = side_path(workdir, "es")
        return unless @translations && File.file?(es_path)

        yield Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{URN}-es", path: File.expand_path(es_path),
          metadata: { "kind" => "translation", "language" => "spa",
                      "title" => "ES-OC Parallel Corpus — Spanish side" }
        )
      end

      # One passage per non-blank line, NFC at the boundary — `oci` for
      # the original, `spa` for the -es sibling. When the OTHER side's
      # file is also on disk, the line counts must agree (alignment IS the
      # format; censused 419,908 = 419,908 — a mismatch is damage).
      def parse(document_ref)
        translation = document_ref.metadata["kind"] == "translation"
        language = translation ? "spa" : "oci"
        check_alignment!(document_ref, translation)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, title: document_ref.metadata["title"],
          canonical_path: document_ref.path, metadata: document_metadata(translation)
        )
        @parser.each_sentence(document_ref.path) do |number, text|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{number}", language: language,
            text: Normalize.nfc(text), sequence: number - 1
          )
        end
        raise ParseError, "#{document_ref.path}: no sentences" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download both sides two-phase (the tla-hf FileFetch choreography):
      # both prepare with the live tree untouched, the breaker sees the
      # combined doomed set, then both complete. Report: last fetch's sha
      # (the single-pin convention), per-side shas in notes.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.values.last.sha, fetched_at: Time.now,
                              notes: fetch_notes(fetches))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "aranese fetch failed into #{workdir}: #{e.message}"
      end

      private

      def side_path(workdir, subdir)
        File.join(workdir, subdir, SIDES.fetch(subdir).fetch(:filename))
      end

      def document_metadata(translation)
        metadata = {
          "provenance" => "mainly synthetic (Apertium-generated from PILAR/OPUS — the dataset " \
                          "card's own words; rows are unmarked upstream)"
        }
        metadata["kind"] = "translation" if translation
        metadata
      end

      # The sibling's physical line count must match — checked only when
      # the other side's file is on disk (a lone side still parses; the
      # loader never sees half a pair after a completed fetch).
      def check_alignment!(document_ref, translation)
        workdir = File.expand_path(File.join(File.dirname(document_ref.path), ".."))
        other = side_path(workdir, translation ? "arn" : "es")
        return unless File.file?(other)

        own_count = line_count(document_ref.path)
        other_count = line_count(other)
        return if own_count == other_count

        raise ParseError, "#{document_ref.path}: #{own_count} line(s) against the sibling's " \
                          "#{other_count} — the two sides must stay line-aligned " \
                          "(alignment IS the format; upstream censused equal)"
      end

      def line_count(path)
        count = 0
        File.foreach(path) { count += 1 }
        count
      end

      def file_fetches(workdir, progress)
        SIDES.to_h do |subdir, side|
          [subdir, Nabu::FileFetch.new(
            url: side.fetch(:url), dir: File.join(workdir, subdir),
            filename: side.fetch(:filename),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir),
            progress: progress
          )]
        end
      end

      def fetch_notes(fetches)
        shas = fetches.map { |subdir, fetch| "#{subdir} #{fetch.sha[0, 8]}" }
        [shas.join(" · "), attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end
