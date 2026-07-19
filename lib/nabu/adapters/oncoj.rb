# frozen_string_literal: true

require_relative "oncoj_xml_parser"
require_relative "oncoj_lexicon_parser"
require_relative "../git_fetch"

module Nabu
  module Adapters
    # The Oxford-NINJAL Corpus of Old Japanese (P32-2): github.com/ONCOJ/data
    # at the PINNED "release" tag (commit fd34a1b2, 2021-12-26 — the
    # project's sanctioned periodic release; the project site
    # oncoj.ninjal.ac.jp continues to develop, so any re-pin to a later
    # release is an owner decision). 4,991 lemmatized, parsed poetic texts of
    # the Old Japanese period (Frellesvig et al., Oxford–NINJAL): the
    # complete Man'yōshū (4,693), Nihon shoki kayō (133), Kojiki kayō (112),
    # Bussokuseki-ka (21), Fudoki kayō (20), Shoku Nihongi kayō (8), Jōgū
    # Shōtoku Hōō Teisetsu (4). NB: Senmyō lives only on the continuing
    # project site, NOT in this release.
    #
    # == Shape
    #
    # Document = text (urn:nabu:oncoj:MYS.1.1 — upstream ids verbatim);
    # passage = the corpus's own LINE (lb markers, upstream ids as citation;
    # see OncojXmlParser for the two duplicate-id re-mints). Passage text is
    # the romanized analysis (upstream's own "transliteration" layer — pure
    # lowercase ASCII plus the "*" null-realization mark, censused, so no
    # display.yml row); the attested man'yōgana line rides annotations
    # ("manyogana"), tokens carry pos + writing-status segments + lemma.
    # The four censused unanalyzed crux lines invert honestly: text = the
    # man'yōgana itself, "unanalyzed" => true (and the parser keeps the two
    # singleton quirks — KK.6's mid-word line break, MYS.4.655's word-less
    # segments — see OncojXmlParser).
    #
    # == The lemma join (ojp enters the lemma-indexed languages)
    #
    # w/@lemma ids resolve against lexicon.xml (in this source's own sparse
    # cone) to the entry's first orth — exactly the headword the
    # oncoj-lexicon SIBLING shelf mints, so token lemmas and dictionary
    # headwords fold identically and `nabu define` resolves either way.
    # Measured on the full release: 5,792/5,802 distinct lemma ids resolve
    # (99.8%); 125,020/125,043 lemma-bearing word occurrences (99.98%).
    # Unresolved ids keep lemma_id and mint NO lemma form. A workdir without
    # lexicon.xml is a loud ParseError — the join is a promised feature.
    # Lemma tier stays the gold default: the corpus is hand-curated
    # scholarly annotation, not automatic tagging.
    #
    # == What is NOT ingested
    #
    # oncoj.csv and psd/ are upstream derivatives of the same annotation
    # (the format decision, reasons in test/fixtures/oncoj/README.md); the
    # constituency tree above the token layer stays upstream (journaled
    # residue — the line grain carries pos/lemma/script per token).
    class Oncoj < Nabu::Adapter
      REPO_URL = "https://github.com/ONCOJ/data"
      RELEASE_TAG = "release" # 2021-12-26, commit fd34a1b284c5dd1e8008df9d3abcb28cfaf464bf
      # The sparse cone: the per-text XML + the lemma-resolution lexicon +
      # the license/citation README. oncoj.csv (11.6 MB) and psd/ (9.7 MB)
      # stay outside — derivatives, never parsed.
      SPARSE_PATHS = ["xml/", "/lexicon.xml", "/README"].freeze

      LANGUAGE = "ojp"
      URN_PREFIX = "urn:nabu:oncoj"
      LEXICON_FILENAME = "lexicon.xml"

      # Corpus sigla → text names, per the project site's Texts list
      # (oncoj.ninjal.ac.jp); ids like "MYS.1.1" render "Man’yōshū 1.1".
      SIGLA = {
        "MYS" => "Man’yōshū", "KK" => "Kojiki kayō", "NSK" => "Nihon shoki kayō",
        "BS" => "Bussokuseki-ka", "FK" => "Fudoki kayō", "SNK" => "Shoku Nihongi kayō",
        "JSHT" => "Jōgū Shōtoku Hōō Teisetsu"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "oncoj",
        name: "ONCOJ — Oxford-NINJAL Corpus of Old Japanese (release 2021-12-26)",
        license: "CC BY 4.0 — upstream README §D verbatim: \"The corpus annotation (the grammatical " \
                 "analysis) is licensed under the Creative Commons Attribution 4.0 International " \
                 "License.\" (texts 7th–8th c., public domain). Prescribed citation (§C): " \
                 "\"National Institute for Japanese Language and Linguistics (2021) “Oxford-NINJAL " \
                 "Corpus of Old Japanese” http://oncoj.ninjal.ac.jp/ (accessed 26 December 2021)\"",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "oncoj-xml"
      )

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per xml/ text; the ref id IS the document urn (the
      # conformance identity the sync breaker relies on).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "xml", "*.xml")).each do |path|
          stem = File.basename(path, ".xml")
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{URN_PREFIX}:#{stem}", path: File.expand_path(path),
            metadata: { "upstream_id" => stem }
          )
        end
      end

      def parse(document_ref)
        parsed = parser.read(document_ref.path)
        lemmas = lemma_index(document_ref.path)
        document = Nabu::Document.new(
          urn: "#{URN_PREFIX}:#{parsed.text_id}", language: LANGUAGE,
          title: title_for(parsed.text_id), canonical_path: document_ref.path,
          metadata: { "corpus" => corpus_of(parsed.text_id), "upstream_id" => parsed.text_id }
        )
        parsed.lines.each_with_index do |line, sequence|
          document << build_passage(parsed.text_id, line, sequence, lemmas)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "oncoj: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   ref: RELEASE_TAG, sparse: SPARSE_PATHS)
      end

      private

      def parser
        OncojXmlParser.new
      end

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end

      # { lemma id => lexicon headword } from the workdir's own lexicon.xml,
      # memoized per file path (one parse serves the whole sync).
      def lemma_index(text_path)
        lexicon = File.join(File.dirname(text_path, 2), LEXICON_FILENAME)
        unless File.file?(lexicon)
          raise Nabu::ParseError,
                "oncoj: #{lexicon} not found — the lemma join needs the lexicon in the fetch cone"
        end

        @lemma_index ||= {}
        @lemma_index[lexicon] ||= OncojLexiconParser.new.headword_index(lexicon)
      end

      def title_for(text_id)
        corpus = corpus_of(text_id)
        rest = text_id.delete_prefix("#{corpus}.")
        name = SIGLA[corpus]
        name ? "#{name} #{rest}" : text_id
      end

      def corpus_of(text_id)
        text_id.split(".", 2).first.to_s
      end

      def build_passage(text_id, line, sequence, lemmas)
        tokens = line.tokens.map { |token| token_hash(token, lemmas) }
        annotations = { "line" => line.upstream_id, "manyogana" => line.manyogana, "tokens" => tokens }
        text = line.tokens.reject(&:compound).map(&:form).join(" ")
        if text.empty?
          # The censused unanalyzed cruxes: the attested script is all there is.
          text = line.manyogana
          annotations["unanalyzed"] = true
        end
        Nabu::Passage.new(
          urn: "#{URN_PREFIX}:#{text_id}:#{line.id}", language: LANGUAGE,
          text: Normalize.nfc(text), annotations: annotations, sequence: sequence
        )
      end

      def token_hash(token, lemmas)
        hash = { "form" => token.form }
        hash["pos"] = token.pos if token.pos && !token.pos.empty?
        if token.lemma_id
          hash["lemma_id"] = token.lemma_id
          lemma = lemmas[token.lemma_id]
          hash["lemma"] = lemma if lemma
        end
        if token.compound
          hash["compound"] = true
        else
          hash["segments"] = token.segments.map { |segment| { "text" => segment[:text], "script" => segment[:script] } }
        end
        hash
      end
    end
  end
end
