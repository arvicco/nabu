# frozen_string_literal: true

require_relative "tla_jsonl_parser"

module Nabu
  module Adapters
    # The TLA Hugging Face adapter (P28-2): the Thesaurus Linguae Aegyptiae's
    # OFFICIAL Hugging Face org (`thesaurus-linguae-aegyptiae`), ONE source
    # with two dataset rows (the starling-BASES / wiktionary-recon EXTRACTS
    # configuration verdict — same org, same JSONL shape, same license, same
    # fetch machinery):
    #
    #   tla-hf:demotic-v18       — tla-demotic-v18-premium: 13,383 fully
    #                              intact, unambiguously readable, fully
    #                              lemmatized Demotic sentences (of 31,156;
    #                              TLA corpus v18, 2023) — the only bulk
    #                              demotic artifact anywhere. 7,284,199 B.
    #   tla-hf:late-egyptian-v19 — tla-late_egyptian-v19-premium: 3,606 Late
    #                              Egyptian sentences (of 12,361; corpus v19,
    #                              2024), WITH the Unicode hieroglyph layer.
    #                              1,904,138 B.
    #
    # These are the TLA's FRESHNESS channel (corpus v18/v19, 2023–2025) —
    # curated sentence-grain extracts from the live database — versus the
    # frozen 2018 AES snapshot (docs/02-sources row 15). Sentence records
    # carry Leiden Unified transliteration, `<TLA lemma ID>|<lemma>` pairs
    # (the SAME stable lemma space AED/AES use — the dictionary join, once an
    # AED shelf lands), UPOS, glossing, a German translation, and pre-cooked
    # dateNotBefore/dateNotAfter integers (wired into the date axis by
    # Store::AxisBuilder::TlaHfDates at passage grain).
    #
    # == Identity (FROZEN minting)
    #
    # Upstream ships NO sentence/text ids (censused 2026-07-18) — a record's
    # identity is its 1-based line number in the canonical train.jsonl:
    # urn:nabu:tla-hf:demotic-v18:207. Deterministic and stable while the
    # sha-pinned artifact is unchanged (FileFetch pins the body); a changed
    # upstream file is a new fetch and honestly re-mints — the file-order
    # precedent (starling baltet). German translations are -de sibling
    # documents (…:demotic-v18-de:207, the damaskini -en pattern), minted
    # from the same parse when the registry opts in (`translations: true`).
    #
    # == Language (the honest verdict, journaled backlog P28-2)
    #
    # Both dataset cards tag the data `egy` (ISO 639-3 Egyptian) + `de`; the
    # cards' prose "egy-Egyd" / "egy-Egyp, egy-Egyh" are SCRIPT subtags
    # (ISO 15924 Demotic/hieroglyphic/hieratic), while the stored passage
    # surface is Latin-script transliteration — so a script subtag would
    # misdescribe what we hold. Passages are `egy`; the STAGE (Demotic /
    # Late Egyptian) rides as a document facet (`stage`), the damaskini Norm
    # precedent — never an invented subtag. Translations are `deu`.
    #
    # == License
    #
    # CC BY-SA 4.0. Verbatim, both dataset cards (retrieved 2026-07-18):
    # frontmatter `license: cc-by-sa-4.0`; prose "License: CC BY-SA 4.0 Int.
    # (creativecommons.org/licenses/by-sa/4.0/); for required attribution,
    # see citation recommendations below." — the cards' citation (ed. Richter
    # & Werning, BBAW / Fischer-Elfert & Dils, SAW Leipzig) is the required
    # attribution and travels in the manifest. license_class "attribution",
    # MCP-safe. See test/fixtures/tla-hf/README.md for the full quotes.
    #
    # == fetch / sync policy
    #
    # Two FileFetch single-file syncs over the plain-HTTPS resolve URLs
    # (huggingface.co/datasets/<org>/<name>/resolve/main/train.jsonl — the
    # hf-CLI-free lane; the CDN redirect rides RedirectFollow), each in ITS
    # OWN subdir (FileFetch is one-file-per-dir by design), attics under
    # <workdir>/.attic/<subdir>/ — the wiktionary-recon choreography: both
    # prepare (tree untouched), the mass-deletion breaker sees the whole
    # set, then both complete. ~9.2 MB total for the owner's first sync.
    # sync_policy: manual (versioned artifacts — a v20 would be a NEW
    # dataset name, an owner decision); enabled: false until the owner-fired
    # first real sync.
    class TlaHf < Nabu::Adapter
      HF_BASE = "https://huggingface.co/datasets/thesaurus-linguae-aegyptiae"

      MANIFEST = Nabu::SourceManifest.new(
        id: "tla-hf",
        name: "Thesaurus Linguae Aegyptiae — official Hugging Face datasets " \
              "(Demotic v18 + Late Egyptian v19, premium)",
        license: "CC BY-SA 4.0 (verbatim, both dataset cards: \"License: CC BY-SA 4.0 Int.; " \
                 "for required attribution, see citation recommendations below.\" — cite: ed. " \
                 "T. S. Richter & D. A. Werning on behalf of the Berlin-Brandenburgische Akademie " \
                 "der Wissenschaften and H.-W. Fischer-Elfert & P. Dils on behalf of the " \
                 "Sächsische Akademie der Wissenschaften zu Leipzig)",
        license_class: "attribution",
        upstream_url: "https://huggingface.co/thesaurus-linguae-aegyptiae",
        parser_family: "tla-jsonl"
      )

      URN_PREFIX = "urn:nabu:tla-hf:"

      # One dataset per row; iteration order is registry order. Slugs mint
      # the urns (urn:nabu:tla-hf:<slug>[:‑de]:<line>); `stage` is the
      # document facet pair [value, upstream's own phrase].
      DATASETS = {
        "demotic-v18" => {
          subdir: "demotic-v18",
          dataset: "tla-demotic-v18-premium",
          url: "#{HF_BASE}/tla-demotic-v18-premium/resolve/main/train.jsonl",
          title: "TLA Demotic sentences, corpus v18, premium",
          corpus_version: "v18",
          stage: %w[demotic Demotic]
        }.freeze,
        "late-egyptian-v19" => {
          subdir: "late-egyptian-v19",
          dataset: "tla-late_egyptian-v19-premium",
          url: "#{HF_BASE}/tla-late_egyptian-v19-premium/resolve/main/train.jsonl",
          title: "TLA Late Egyptian sentences, corpus v19, premium",
          corpus_version: "v19",
          stage: ["late-egyptian", "Late Egyptian"]
        }.freeze
      }.freeze

      FILENAME = "train.jsonl"

      def self.manifest
        MANIFEST
      end

      # One HEAD per resolve URL against its subdir's FileFetch state
      # (reachability + Last-Modified drift). metadata_url nil: the license
      # lives on the dataset cards, no probe-shaped endpoint.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        DATASETS.values.map do |dataset|
          Nabu::Adapter::HttpProbeTarget.new(
            label: dataset.fetch(:dataset), zip_url: dataset.fetch(:url), metadata_url: nil,
            state_subdir: dataset.fetch(:subdir), state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      # +translations+: when true (the registry row's posture — German
      # coverage is 100%, censused), discover also yields one -de sibling
      # ref per dataset, parsed from the same records.
      def initialize(translations: false)
        super()
        @translations = translations
        @parser = TlaJsonlParser.new
      end

      # One DocumentRef per dataset file found (plus -de siblings when opted
      # in), DATASETS order. A workdir without a file yields fewer refs (the
      # day-one pre-fetch state); the same walk works under the attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        DATASETS.each do |slug, dataset|
          path = Dir.glob(File.join(workdir, dataset.fetch(:subdir), "**", FILENAME)).first
          next if path.nil?

          refs(slug, dataset, path).each(&block)
        end
      end

      # Originals: one `egy` passage per record — text is the NFC-normalized
      # transliteration, gold tokens (form/lemma_id/lemma/upos/gloss) ride in
      # annotations, hieroglyphs/authors verbatim where the dataset ships
      # them. -de refs (metadata "kind" => "translation") mint one German
      # passage per record, suffix-aligned for Query::Parallel.
      def parse(document_ref)
        slug = document_ref.metadata.fetch("dataset_slug")
        dataset = DATASETS.fetch(slug)
        if document_ref.metadata["kind"] == "translation"
          parse_translation(document_ref)
        else
          parse_original(document_ref, dataset)
        end
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download both artifacts two-phase (the wiktionary-recon FileFetch
      # choreography): all prepare with the live tree untouched, the breaker
      # sees the combined doomed set, then all complete. Report: last
      # fetch's sha (the single-pin convention), per-dataset shas in notes.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.values.last.sha, fetched_at: Time.now,
                              notes: fetch_notes(fetches))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "tla-hf fetch failed into #{workdir}: #{e.message}"
      end

      private

      def refs(slug, dataset, path)
        urn = "#{URN_PREFIX}#{slug}"
        metadata = { "dataset_slug" => slug, "language" => "egy",
                     "title" => dataset.fetch(:title) }
        refs = [Nabu::DocumentRef.new(source_id: manifest.id, id: urn,
                                      path: File.expand_path(path), metadata: metadata)]
        if @translations
          refs << Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{urn}-de", path: File.expand_path(path),
            metadata: metadata.merge("kind" => "translation", "language" => "deu",
                                     "title" => "#{dataset.fetch(:title)} — German translation")
          )
        end
        refs
      end

      def parse_original(document_ref, dataset)
        document = Nabu::Document.new(
          urn: document_ref.id, language: "egy", title: document_ref.metadata["title"],
          canonical_path: document_ref.path, metadata: document_metadata(dataset)
        )
        @parser.each_record(document_ref.path) do |record|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{record.number}", language: "egy",
            text: Normalize.nfc(record.transliteration),
            annotations: annotations(record), sequence: record.number - 1
          )
        end
        raise ParseError, "#{document_ref.path}: no records" if document.empty?

        document
      end

      def document_metadata(dataset)
        stage_value, stage_raw = dataset.fetch(:stage)
        {
          "dataset" => dataset.fetch(:dataset),
          "corpus_version" => dataset.fetch(:corpus_version),
          "facets" => { "stage" => { "value" => stage_value, "raw" => stage_raw } }
        }
      end

      # Token fields verbatim (the ConlluParser stance — the fold happens at
      # the index); hieroglyphs (incl. <g>JSesh</g> fallbacks) and the
      # authors credit ride verbatim where present.
      def annotations(record)
        result = {
          "tokens" => record.tokens.map do |token|
            { "form" => token.form, "lemma_id" => token.lemma_id, "lemma" => token.lemma,
              "upos" => token.upos, "gloss" => token.gloss }
          end
        }
        result["hieroglyphs"] = record.hieroglyphs if record.hieroglyphs
        result["authors"] = record.authors if record.authors
        result
      end

      # One `deu` passage per record, cited by the same line number as its
      # original — the Query::Parallel verse-pair contract. Coverage is 100%
      # upstream (translation is a required field), so no honest skips arise.
      def parse_translation(document_ref)
        document = Nabu::Document.new(
          urn: document_ref.id, language: "deu", title: document_ref.metadata["title"],
          canonical_path: document_ref.path, metadata: { "kind" => "translation" }
        )
        @parser.each_record(document_ref.path) do |record|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{record.number}", language: "deu",
            text: Normalize.nfc(record.translation), sequence: record.number - 1
          )
        end
        raise ParseError, "#{document_ref.path}: no records" if document.empty?

        document
      end

      def file_fetches(workdir, progress)
        DATASETS.transform_values do |dataset|
          Nabu::FileFetch.new(
            url: dataset.fetch(:url), dir: File.join(workdir, dataset.fetch(:subdir)),
            filename: FILENAME,
            attic_dir: File.join(workdir, ATTIC_DIRNAME, dataset.fetch(:subdir)),
            progress: progress
          )
        end
      end

      def fetch_notes(fetches)
        shas = fetches.map { |slug, fetch| "#{slug} #{fetch.sha[0, 8]}" }
        [shas.join(" · "), attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end
