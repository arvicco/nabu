# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one GLAUx treebank XML file — the `glaux` parser
    # family (P44-1), a sibling to ProielParser and DiorisisParser and the
    # analysis-side complement to the Perseus/First1K editions the catalog
    # already holds. A standalone, individually tested component the Glaux
    # adapter composes; the adapter owns identity, the per-text license census
    # and fetch, the parser owns the body.
    #
    # == The format (censused from the real bytes, 2026-07-24)
    #
    #   <treebank version="2" xml:lang="grc">
    #     <sentence struct_id="27421" id="1" document_id="0003-002" analysis="auto">
    #       <word id="100477566" form="μνῆμα" div_book="7" div_chapter="7.45"
    #             lemma="μνῆμα" postag="n-s---nn-" head="1000023731" relation="SBJ"
    #             animacy="concrete" sense="grave.n.02"/>
    #       …
    #       <word id="1000023731" form="E" lemma="E" postag="z--------" head="0"
    #             relation="PRED" artificial="elliptic" div_book="7" div_chapter="7.45"/>
    #     </sentence>
    #   </treebank>
    #
    # The body inventory is CLOSED (treebank/sentence/word); every word is a
    # self-closing element carrying its full annotation on attributes. Files
    # reach 31 MB upstream, so the only Nokogiri entry point is
    # Nokogiri::XML::Reader — a whole-document DOM is never built (house rule,
    # pinned structurally by the test suite, as for ProielParser).
    #
    # == Encoding (NFD → NFC at the boundary)
    #
    # GLAUx is encoded in Unicode NFD (README, verbatim: "the GLAUx corpus is
    # encoded in Unicode-NFD … diacritics are separate characters"). Every
    # form and lemma is NFC-normalized HERE, once, at the adapter boundary
    # (house rule; grc is NOT on the NFC-exempt list). μνῆμα arrives as
    # μ ν η U+0342 μ α and stores as μ ν U+1FC6 μ α.
    #
    # == Passage minting (sentence = passage)
    #
    # - urn = "<document-urn>:<sentence/@struct_id>". struct_id is GLAUx's own
    #   global sentence database key (27421, 1152757, …) — unique corpus-wide,
    #   stable, and non-contiguous: the PROIEL precedent (its sentence db-keys),
    #   NOT the per-document @id, which is a mere 1..n document-order ordinal.
    #   A <sentence> without a @struct_id is a ParseError naming the file and
    #   the sentence's document position (malformed, never papered over).
    # - sequence = kept-sentence document order from 0.
    # - text = word forms in document order, space-separated; punctuation words
    #   (postag begins "u") glue LEFT with no preceding space (the diorisis
    #   idiom); artificial elliptic tokens (form "E") contribute NOTHING to the
    #   surface (see below). NFC at this boundary.
    #
    # == Artificial and punctuation tokens (the lemma pool stays clean)
    #
    # Elliptic reconstruction tokens (artificial="elliptic", form/lemma "E",
    # postag z---------) are NOT real words: they are dependency-graph nodes
    # the annotators inserted to head elided material. They RIDE in the token
    # annotations (the tree is incomplete without them — the PROIEL empty-token
    # precedent) but carry NO "lemma" key and add nothing to the surface text,
    # so the silver lemma index never mints a bogus "e" lemma. Punctuation
    # words (postag "u--------": AuxK/AuxX/AuxZ) likewise keep their token (the
    # tree edge is real) and their surface mark, but drop the "lemma" key — a
    # comma is not a dictionary form. Only real words feed the lemma lane.
    #
    # == Annotations (the treebank payload the standing lanes consume)
    #
    # annotations = {
    #   "tokens" => [ {"id","form","lemma","postag","head","relation",
    #                  "animacy","sense","artificial"}, … ],  # nil keys dropped
    #   "analysis" => <sentence/@analysis, e.g. "auto">,       # the tier signal
    #   "book" / "chapter" / "citation" => <div_book / div_chapter>
    # }
    #
    # The Indexer reads per-token "lemma" + "form" for the lemma index (source
    # tier from sources.yml `lemma_tier: silver`). "postag" is the AGDT 9-place
    # positional morphology; it rides on the token verbatim but is DELIBERATELY
    # NOT wired into the --morph façade (Nabu::Query::MorphFacets speaks the UD
    # and PROIEL positional schemes, and the AGDT layout differs — an incorrect
    # mapping would be dishonest; the diorisis prose-morph precedent, "honest
    # absence over a wrong mapping"). "analysis" records the gold/silver signal
    # per sentence; the source-wide tier stays the conservative silver floor.
    class GlauxParser
      # A finished sentence awaiting Passage construction.
      Sentence = Data.define(:struct_id, :analysis, :book, :chapter, :text, :tokens)
      private_constant :Sentence

      # GLAUx word attribute → annotation key, in stored order. Anything absent
      # on a word is simply not in the hash. div_book/div_chapter are read for
      # the citation but do not ride each token (they repeat per word).
      TOKEN_ATTRIBUTES = {
        "id" => "id",
        "form" => "form",
        "lemma" => "lemma",
        "postag" => "postag",
        "head" => "head",
        "relation" => "relation",
        "animacy" => "animacy",
        "sense" => "sense",
        "artificial" => "artificial"
      }.freeze
      private_constant :TOKEN_ATTRIBUTES

      # Same signature family as the other parser families. +license_override+
      # (P10-4) rides to the Document unchanged; +language+ is the caller's
      # (grc) — the parser is metadata-agnostic.
      def parse(source, urn:, language:, title: nil, metadata: {}, license_override: nil,
                canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        sentences = extract_sentences(source, path: path)
        build_document(sentences, urn: urn, language: language, title: title,
                                  metadata: metadata, license_override: license_override, path: path)
      end

      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      def extract_sentences(source, path:)
        with_io(source) do |io|
          Extraction.new(reader: Nokogiri::XML::Reader(io, path), path: path).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      def build_document(sentences, urn:, language:, title:, metadata:, license_override:, path:)
        document = Document.new(urn: urn, language: language, title: title,
                                canonical_path: path, metadata: metadata,
                                license_override: license_override)
        sentences.each_with_index do |sentence, sequence|
          next if sentence.text.empty? # an all-artificial/all-punct sentence has no surface

          document << Passage.new(
            urn: "#{urn}:#{sentence.struct_id}",
            language: language,
            text: sentence.text,
            annotations: annotations(sentence),
            sequence: sequence
          )
        end
        raise ParseError, "#{path}: no <sentence> elements found" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      def annotations(sentence)
        result = { "tokens" => sentence.tokens }
        result["analysis"] = sentence.analysis if sentence.analysis
        result["book"] = sentence.book if sentence.book
        result["chapter"] = sentence.chapter if sentence.chapter
        citation = sentence.chapter || sentence.book
        result["citation"] = citation if citation
        result
      end

      # The single-pass Reader state machine. Reacts only to <sentence>
      # (passage boundary) and <word> (text + token annotations); the treebank
      # wrapper streams past untouched.
      class Extraction
        READER = Nokogiri::XML::Reader
        private_constant :READER

        def initialize(reader:, path:)
          @reader = reader
          @path = path
          @sentences = []
          @sentence_ordinal = 0
          @current = nil
        end

        def call
          @reader.each { |node| process(node) }
          @sentences
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          end
        end

        def start_element(node)
          case node.name
          when "sentence" then start_sentence(node)
          when "word" then add_word(node)
          end
        end

        def end_element(node)
          finish_sentence if node.name == "sentence" && @current
        end

        def start_sentence(node)
          @sentence_ordinal += 1
          struct_id = node.attribute("struct_id")
          if struct_id.nil? || struct_id.empty?
            raise ParseError,
                  "#{@path}: <sentence> ##{@sentence_ordinal} (document order) is missing its " \
                  "@struct_id — the corpus-wide stable sentence key the passage urn is minted from"
          end

          @current = {
            struct_id: struct_id, analysis: node.attribute("analysis"),
            book: nil, chapter: nil, text: +"", tokens: []
          }
          finish_sentence if node.empty_element? # defensive: <sentence/> with no words
        end

        # A word is a self-closing element: build its token, contribute its
        # surface, and record the first real word's citation. NFC at the
        # boundary (GLAUx is NFD upstream).
        def add_word(node)
          return unless @current

          form = normalize(node.attribute("form"))
          artificial = !node.attribute("artificial").nil?
          punctuation = node.attribute("postag").to_s.start_with?("u")

          append_surface(form, artificial: artificial, punctuation: punctuation)
          capture_citation(node) unless artificial || punctuation
          @current[:tokens] << token_hash(node, form: form, drop_lemma: artificial || punctuation)
        end

        def append_surface(form, artificial:, punctuation:)
          return if artificial || form.nil? || form.empty?

          text = @current[:text]
          text << " " unless text.empty? || punctuation
          text << form
        end

        def capture_citation(node)
          @current[:book] ||= presence(node.attribute("div_book"))
          @current[:chapter] ||= presence(node.attribute("div_chapter"))
        end

        # form NFC'd already; lemma NFC'd here; other attrs verbatim. The lemma
        # is dropped for artificial/punctuation tokens so the lemma index stays
        # clean (class note).
        def token_hash(node, form:, drop_lemma:)
          hash = {}
          TOKEN_ATTRIBUTES.each do |attribute, key|
            next if key == "lemma" && drop_lemma

            value = attribute == "form" ? form : node.attribute(attribute)
            next if value.nil?

            hash[key] = key == "lemma" ? normalize(value) : value
          end
          hash
        end

        def finish_sentence
          current = @current
          @current = nil
          return unless current

          @sentences << Sentence.new(
            struct_id: current[:struct_id], analysis: current[:analysis],
            book: current[:book], chapter: current[:chapter],
            text: Normalize.nfc(current[:text].strip), tokens: current[:tokens]
          )
        end

        def normalize(value)
          value.nil? ? nil : Normalize.nfc(value)
        end

        def presence(value)
          value if value && !value.empty?
        end
      end
      private_constant :Extraction
    end
  end
end
