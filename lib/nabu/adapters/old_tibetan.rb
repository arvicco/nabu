# frozen_string_literal: true

require_relative "conllu_parser"
require_relative "../normalize"

module Nabu
  module Adapters
    # The Old Tibetan Corpus adapter (P48-3): tibetan-nlp/old-tibetan-corpus
    # — the Old Tibetan Annals (OTA, OTDO Pt_1288) and the Old Tibetan
    # Chronicle (OTC, Pt_1287), the two foundational Dunhuang historical
    # texts: OTDO's Wylie converted to Unicode Tibetan, segmented and
    # POS-tagged, then HAND-CORRECTED in BRAT (segmentation + POS +
    # verb-argument dependencies) by Faggionato/Garrett/Meelen (AHRC
    # "Lexicography in Motion", 2017–2020). Censused 2026-07-28: otannals
    # 546 sentences / ~5.6k syllable-tokens (every sentence with Dotson
    # 2009's aligned English as `# text_en`), otchronicle 1,577 / ~11.8k
    # (no translation lane). A thin composition of the shared ConlluParser
    # — the files are clean 10-column CoNLL-U with mandatory sent_id + text
    # (the digiliblt counter-case does not apply).
    #
    # == Identity + the language ruling
    #
    #   document urn  urn:nabu:old-tibetan:<stem>       (otannals, otchronicle)
    #   sibling urn   urn:nabu:old-tibetan:<stem>-en    (the Dotson lane)
    #   passage urn   <document-urn>:<citation>         (…:otannals:000:T55)
    #
    # sent_ids are `<stem>:<section>:<brat-id>` (unique per file, NOT
    # ordinal — file order is the sequence); the citation hook strips the
    # redundant `<stem>:` prefix (the damaskini mold), so original and -en
    # sibling share citation suffixes — what `show --parallel` aligns on.
    # Language `otb` (ISO 639-3 Old Tibetan — the Dunhuang orthography with
    # the reversed gi-gu, ྀ): NOT `xct` (soas-tibetan's classical lane),
    # NOT `bo` (kaikki's modern dictionary shelf).
    #
    # == The annotation layers, honestly labeled
    #
    # Gold by upstream's own claim: segmentation, POS (UPOS), and the
    # verb-argument dependency layer (bespoke deprels arg1/arg2/arg2:lvc/…
    # on an otherwise all-root HEAD lane) — hand-corrected in BRAT. NOT
    # gold: the LEMMA column, the ot2ct-NORMALIZED Classical Tibetan
    # citation form (`√`-marked: ནས་√cv, འཇིག་√2) — a constraint-grammar
    # pipeline product the hand-correction claim does not cover → the
    # registry row pins `lemma_tier: silver`, every lemma hit labeled (the
    # cdli/ebl defensive-honesty precedent). Lemmas ride verbatim, √ marks
    # and all (canonical means canonical).
    #
    # == The -en sibling (the elephantine mold)
    #
    # With `translations: true` (the registry posture) discover also yields
    # one <urn>-en ref per text; parse mints the English document from the
    # same file's `# text_en` comments (kind: translation, language eng,
    # Dotson 2009). A text without a single text_en (the Chronicle) skips
    # by rule (DocumentSkipped), never a fake empty document.
    #
    # == fetch / sync policy
    #
    # Whole-repo GitFetch (the repo is ~5 MB; the cg3/brat/text lanes are
    # small renderings of the same texts). archive/*.conllu (legacy
    # NORMALIZED exports — they would double-load the texts in the wrong
    # orthography) are censused discovery skips. Upstream is dormant since
    # 2021 → sync_policy manual, wired: false until the owner-fired first
    # sync.
    #
    # == License (verified 2026-07-28; recorded choice)
    #
    # Repo LICENSE: MIT (Copyright (c) 2018 Tibetan NLP) → attribution.
    # The Zenodo twin of this dataset lists only "Other (Open)" — the MIT
    # grant in THIS repo (which is also what fetch takes) is the recorded
    # license basis. The upstream README additionally stamps each text
    # CC BY 4.0 in its metadata table — both grants are attribution-class.
    # Cite Faggionato, Garrett & Meelen (the repo's citation line) +
    # Dotson 2009 for the Annals translation.
    class OldTibetan < Nabu::Adapter
      REPO_URL = "https://github.com/tibetan-nlp/old-tibetan-corpus"

      MANIFEST = Nabu::SourceManifest.new(
        id: "old-tibetan",
        name: "Old Tibetan Corpus — the Annals and the Chronicle (tibetan-nlp)",
        license: "MIT (repo LICENSE verbatim: \"MIT License / Copyright (c) 2018 Tibetan NLP\"; " \
                 "the Zenodo twin lists only 'Other (Open)' — the MIT GitHub grant is the " \
                 "recorded basis; per-text README metadata additionally stamps CC BY 4.0). " \
                 "Cite Christian Faggionato, Edward Garrett & Marieke Meelen; the Annals " \
                 "translation is Dotson 2009",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "conllu"
      )

      CONLLU_DIR = "conllu"
      ARCHIVE_DIR = "archive"
      LANGUAGE = "otb"
      TRANSLATION_LANGUAGE = "eng"
      URN_PREFIX = "urn:nabu:old-tibetan:"
      TRANSLATION_SUFFIX = "-en"

      # The two texts, upstream-README-censused (titles, OTDO shelfmarks,
      # the Dotson translation credit on the Annals).
      TEXTS = {
        "otannals" => { title: "Old Tibetan Annals", otdo: "Pt_1288",
                        translator: "Brandon Dotson" },
        "otchronicle" => { title: "Old Tibetan Chronicle", otdo: "Pt_1287" }
      }.freeze

      def self.manifest
        MANIFEST
      end

      # +translations+: when true (the registry row's posture), discover
      # also yields one -en sibling ref per text.
      def initialize(translations: false)
        super()
        @translations = translations
      end

      # One DocumentRef per conllu/*.conllu (plus -en siblings when opted
      # in), sorted by urn. A pre-fetch workdir yields nothing; the archive/
      # legacy lane is the censused skip below.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # archive/*.conllu are legacy NORMALIZED exports of the same texts —
      # ingesting them would double-load in the wrong orthography. Visible
      # skips, never silent.
      def discovery_skips(workdir)
        skipped = Dir.glob(File.join(workdir, ARCHIVE_DIR, "*.conllu")).size
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      # Originals compose the shared ConlluParser (citation hook strips the
      # `<stem>:` prefix); -en refs (metadata "kind" => "translation") mint
      # the Dotson sibling from the same file's text_en lane.
      def parse(document_ref)
        if document_ref.metadata["kind"] == "translation"
          parse_translation(document_ref)
        else
          parse_original(document_ref)
        end
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Whole-repo git fetch (fetch objects → breaker → attic → ff-merge;
      # architecture §8).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end

      def document_refs(workdir)
        Dir.glob(File.join(workdir, CONLLU_DIR, "*.conllu")).flat_map do |path|
          urn = "#{URN_PREFIX}#{File.basename(path, '.conllu')}"
          refs = [Nabu::DocumentRef.new(source_id: manifest.id, id: urn,
                                        path: File.expand_path(path), metadata: {})]
          if @translations
            refs << Nabu::DocumentRef.new(
              source_id: manifest.id, id: "#{urn}#{TRANSLATION_SUFFIX}",
              path: File.expand_path(path), metadata: { "kind" => "translation" }
            )
          end
          refs
        end.sort_by(&:id)
      end

      def parse_original(document_ref)
        stem = stem_of(document_ref)
        entry = TEXTS.fetch(stem, {})
        ConlluParser.new.parse(
          document_ref.path, urn: document_ref.id, language: LANGUAGE,
                             title: entry.fetch(:title, stem),
                             metadata: { "text_id" => stem, "otdo" => entry[:otdo] }.compact,
                             citation: ->(sent_id) { sent_id.delete_prefix("#{stem}:") }
        )
      end

      # The Dotson lane: stream the same file's sentence blocks, one
      # passage per block that carries a `# text_en`; a text without a
      # single one skips by rule.
      def parse_translation(document_ref)
        stem = stem_of(document_ref)
        entry = TEXTS.fetch(stem, {})
        document = Nabu::Document.new(
          urn: document_ref.id, language: TRANSLATION_LANGUAGE,
          title: "#{entry.fetch(:title, stem)} (English translation)",
          canonical_path: document_ref.path,
          metadata: { "kind" => "translation", "text_id" => stem,
                      "translator" => entry[:translator] }.compact
        )
        append_translations(document, document_ref, stem: stem)
        if document.empty?
          raise DocumentSkipped.new("#{document_ref.path}: no text_en lane upstream",
                                    reason: "no text_en translation lane")
        end

        document
      end

      def append_translations(document, document_ref, stem:)
        sequence = 0
        each_translated_block(document_ref.path) do |sent_id, text_en|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{sent_id.delete_prefix("#{stem}:")}",
            language: TRANSLATION_LANGUAGE,
            text: Nabu::Normalize.nfc(text_en),
            annotations: {},
            sequence: sequence
          )
          sequence += 1
        end
      end

      # Stream the CoNLL-U comment lanes only: yield [sent_id, text_en] for
      # each block carrying both. Blank line closes a block (ConlluParser's
      # grammar, comments-only view).
      def each_translated_block(path)
        sent_id = nil
        text_en = nil
        File.open(path, "r:UTF-8") do |io|
          io.each_line do |raw|
            line = raw.chomp
            if line.empty?
              yield sent_id, text_en if sent_id && text_en
              sent_id = text_en = nil
            elsif (value = comment_value(line, "sent_id"))
              sent_id = value
            elsif (value = comment_value(line, "text_en"))
              text_en = value
            end
          end
        end
        yield sent_id, text_en if sent_id && text_en
      end

      def comment_value(line, key)
        match = line.match(/\A#\s?#{Regexp.escape(key)}\s*=\s*(.*)\z/)
        value = match && match[1]
        value unless value.nil? || value.empty?
      end

      def stem_of(document_ref)
        File.basename(document_ref.path, ".conllu")
      end
    end
  end
end
