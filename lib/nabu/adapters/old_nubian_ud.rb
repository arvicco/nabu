# frozen_string_literal: true

require_relative "conllu_parser"
require_relative "../normalize"

module Nabu
  module Adapters
    # The Old Nubian UD treebank (github.com/Innokentii-Smirnov/
    # OldNubianUDTreebank; Innokentii Smirnov): the first machine-readable
    # treebank of Old Nubian (ISO 639-3 onw), the written language of the
    # medieval Nile Nubian kingdoms — 124 sentences annotated in Universal
    # Dependencies (UPOS, FEATS, basic dependency tree, lemmas) with a
    # morpheme layer in MISC (MSeg segmentation, MGloss morpheme gloss, Gloss
    # lexical gloss; CorrectForm on three tokens). A thin composition of the
    # shared ConlluParser (the old-tibetan mold), git-fetched.
    #
    # == Shape (censused 2026-10-14, upstream HEAD 64a7b043)
    #
    # ONE treebank file, OldNubian.conllu: 124 sentences / 1,544 syntactic
    # words / 186 multiword-token ranges. Every block carries exactly three
    # comments — `sent_id` (ordinal 0–124; 69 is absent), `text`,
    # `translation` — and nothing document-level: no text, manuscript,
    # date or place identifier anywhere in the file. By the content
    # itself: sentences 0–68 are the Miracle of Saint Menas (sentence 0 is
    # its own incipit, "the miracle which the holy martyr of Christ Mina
    # did"), translated and glossed in Russian; 70–117 a homily on church
    # offerings and the eucharist, translated and glossed in English;
    # 118–124 short fragments (119–121 the Emmanuel verse, Isaiah 7:14 /
    # Matthew 1:23); 118 and 122–124 carry empty translations. The file
    # does not mark these divisions, so the whole treebank is ONE document
    # (urn :OldNubian, the file stem) and passages are cited by sent_id —
    # a deliberate coarseness, declared: splitting by inferred text
    # boundaries would invent structure upstream does not state.
    #
    # The text lane is a LATIN TRANSLITERATION (ṅ, ė, ȧ, š, ǧ, ï, macrons
    # — 7,450 Latin letters, zero Coptic-block characters), not the
    # manuscripts' Coptic-derived Old Nubian alphabet → metadata script
    # "Latn". Lacunae and restorations ride verbatim ([*****], [p]).
    #
    # == Normalization at the boundary
    #
    # Upstream is not NFC: 171 lines write ǧ as g + U+030C (395
    # occurrences). ConlluParser NFCs the passage text; the token columns
    # it leaves verbatim, so this adapter NFCs the token annotations as
    # well (the house rule — normalize at the adapter boundary) and token
    # forms match their passage text.
    #
    # == Translations
    #
    # The `# translation` comment rides the parser's sentence-comment
    # whitelist (annotations "translations" => {"translation" => …}),
    # verbatim in its own language (Russian 0–68, English 70–121); empty
    # values mint nothing.
    #
    # == Annotation tier
    #
    # lemma_tier stays the gold default: the repo's scripts derive only the
    # MISC morpheme fields (add_segmentations from MorphosyntacticWords.tsv,
    # add_morpheme_glossing from the Converter/Linearizer tables); nothing
    # upstream marks the core columns as a tagger's output.
    #
    # == Sidecars (censused, not ingested)
    #
    # MorphosyntacticWords.tsv (989 rows: MSeg, lemma, feats, gloss, upos,
    # form — the segmentation lexicon extracted from and re-applied to the
    # treebank), the four glossing tables (Converter.txt, Linearizer.txt,
    # MorphemicConverter.txt, MorphemicLinearizer.txt), three shell wrappers
    # (add.sh, add_morpheme_glossing.sh, extract.sh) and the git submodule
    # MorphemeSegmentationForUniversalDependencies (the author's Python
    # tool). All are tooling or derivations of the .conllu — discovery
    # reads the one treebank file at the repo root only.
    #
    # == License
    #
    # LICENSE.txt (added by the repository author, Innokentii Smirnov,
    # 2026-10-13), verbatim: "The treebank is licensed under the
    # Attribution-NonCommercial-ShareAlike 4.0 International." → CC BY-NC-SA
    # 4.0 → nc. Grant verified 2026-10-14.
    class OldNubianUd < Nabu::Adapter
      REPO_URL = "https://github.com/Innokentii-Smirnov/OldNubianUDTreebank"
      TREEBANK = "OldNubian.conllu"
      URN_PREFIX = "urn:nabu:old-nubian-ud:"
      LANGUAGE = "onw"
      SCRIPT = "Latn"

      MANIFEST = Nabu::SourceManifest.new(
        id: "old-nubian-ud",
        name: "Old Nubian UD Treebank (Innokentii Smirnov)",
        license: "CC BY-NC-SA 4.0 — the repository's LICENSE.txt (Innokentii Smirnov, 2026-10-13), " \
                 "verbatim: \"The treebank is licensed under the Attribution-NonCommercial-ShareAlike " \
                 "4.0 International.\" Cite: Innokentii Smirnov, Old Nubian UD Treebank.",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "conllu"
      )

      def self.manifest = MANIFEST

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, TREEBANK)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{File.basename(path, '.conllu')}",
                                    path: File.expand_path(path), metadata: {})
      end

      def parse(document_ref)
        parsed = ConlluParser.new.parse(
          document_ref.path, urn: document_ref.id, language: LANGUAGE, title: "Old Nubian UD Treebank",
                             metadata: { "file" => TREEBANK, "script" => SCRIPT }, sentence_comments: true
        )
        nfc_tokens(parsed)
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Whole-repo git fetch (fetch objects → breaker → attic → ff-merge;
      # architecture §8). The submodule is not initialized — tooling only.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url = REPO_URL

      def nfc_tokens(parsed)
        document = Nabu::Document.new(urn: parsed.urn, language: parsed.language, title: parsed.title,
                                      canonical_path: parsed.canonical_path, metadata: parsed.metadata)
        parsed.each { |passage| document << passage.with(annotations: deep_nfc(passage.annotations)) }
        document
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
