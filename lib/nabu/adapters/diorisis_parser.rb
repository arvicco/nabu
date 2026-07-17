# frozen_string_literal: true

require "nokogiri"

require_relative "../betacode"

module Nabu
  module Adapters
    # Streaming parser for one Diorisis Ancient Greek Corpus XML file (P26-4)
    # — the `diorisis` parser family. A standalone component the Diorisis
    # adapter composes; same call shape as the other parser families
    # (#parse(source, urn:, language:, title:, metadata:, canonical_path:)).
    #
    # == The format (censused from the full 820-file zip, 2026-07-18)
    #
    #   <TEI.2>                                ← TEI P4-shaped, NO namespace,
    #     <teiHeader> … </teiHeader>             NO XML declaration
    #     <text><body>
    #       <sentence id="1" location="1.1.1">
    #         <word form="qeou\s" id="1">
    #           <lemma id="48291" entry="θεός" POS="noun" TreeTagger="false"
    #                  disambiguated="n/a">
    #             <analysis morph="masc acc pl"/>
    #           </lemma>
    #         </word>
    #         <punct mark=","/>
    #       </sentence>
    #     </body></text>
    #   </TEI.2>
    #
    # The body inventory is CLOSED (whole-corpus census: body/sentence/word/
    # lemma/analysis/punct and nothing else); the header is the ADAPTER's
    # concern (identity, provenance, license) — this parser reads only the
    # body and streams everything else past.
    #
    # Streaming by contract: 76 of the 820 files exceed 5 MB (Polybius
    # 76.1 MB), so the only Nokogiri entry point is Nokogiri::XML::Reader —
    # a whole-document DOM is never built (house rule; pinned structurally
    # by the test suite, as for ProielParser).
    #
    # == Text reconstruction (word forms are Beta Code)
    #
    # word/@form is TLG Beta Code ("*dhmh/thr'" = Δημήτηρ'); the census found
    # NO character outside the existing Nabu::Betacode inventory (letters,
    # capitals, breathings/accents/iota-subscript/diaeresis, length marks —
    # apostrophes and hyphens pass through). Decoded HERE, once, at the
    # adapter boundary. punct/@mark is kept VERBATIM and glued to the left
    # (no space before, one space after): the marks are already display
    # characters of a MIXED inventory (",", ".", ":", "—", ".\"", ")·" …),
    # and ")" in Beta Code is a breathing mark, so decoding punct would
    # fabricate combining characters — verbatim is the only honest choice.
    #
    # == Passage minting (sentence = passage)
    #
    # - urn = "<document-urn>:<sentence/@id>" — sentence ids are unique per
    #   file (censused: 0 duplicates across 538,011 sentences) and the zip is
    #   a frozen artifact, so the minting is stable. @location is NOT usable
    #   as identity: it repeats (poetry lines spanning sentences), is empty
    #   in 142 files, and carries free-shape strings ("APr.Α", "6,7",
    #   "fragment") — it rides as the verbatim citation instead.
    # - sequence = document order from 0.
    #
    # == Annotations (the silver lemma payload)
    #
    # annotations = {
    #   "tokens" => [ {"id","form" (decoded),"lemma" (NFC'd entry),"lemma_id",
    #                  "pos","tree_tagger","disambiguated","analyses"}, … ],
    #   "location" => <sentence/@location, when non-empty>
    # }
    #
    # - "lemma" is lemma/@entry — already Unicode Greek upstream, NFC'd here
    #   (429 of 10.05M entries arrive non-NFC). A lemma element WITHOUT an
    #   entry attribute (<lemma id="unknown">, 153,593 words) yields a
    #   lemma-less token: the word keeps its surface form in text and tokens,
    #   and the Indexer honestly mints no lemma row for it.
    # - "tree_tagger" (true) and "disambiguated" (the upstream 1/n confidence
    #   fraction, verbatim string) appear ONLY where TreeTagger actually
    #   disambiguated (TreeTagger="true", 1.84M words); the "false"/"n/a"
    #   majority stays absent — lean keys, upstream truth preserved.
    # - "analyses" lists every candidate analysis/@morph in file order.
    #   These are Perseus-style prose morph strings ("fem acc sg (attic epic
    #   ionic)"), a THIRD morphology dialect — deliberately NOT wired into
    #   the --morph façade in this packet (MorphFacets speaks UD + PROIEL;
    #   honest absence over a wrong mapping).
    # - punct contributes to text only, never a token — the Indexer's
    #   surface_forms and the fold contract see words exactly.
    class DiorisisParser
      # A finished sentence awaiting Passage construction.
      Sentence = Data.define(:id, :location, :text, :tokens)
      private_constant :Sentence

      # Same signature family as the other parsers.
      def parse(source, urn:, language:, title: nil, metadata: {}, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        sentences = extract_sentences(source, path: path)
        build_document(sentences, urn: urn, language: language, title: title,
                                  metadata: metadata, path: path)
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

      def build_document(sentences, urn:, language:, title:, metadata:, path:)
        document = Document.new(urn: urn, language: language, title: title,
                                canonical_path: path, metadata: metadata)
        sentences.each_with_index do |sentence, sequence|
          next if sentence.text.empty? # defensive: an all-punct sentence has no surface text

          document << Passage.new(
            urn: "#{urn}:#{sentence.id}",
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
        location = sentence.location
        result["location"] = location if location && !location.empty?
        result
      end

      # The single-pass Reader state machine. Reacts only to <sentence>,
      # <word>, <lemma>, <analysis> and <punct>; the teiHeader and everything
      # else streams past untouched.
      class Extraction
        READER = Nokogiri::XML::Reader
        private_constant :READER

        def initialize(reader:, path:)
          @reader = reader
          @path = path
          @sentences = []
          @sentence_ordinal = 0
          @current = nil # {id:, location:, text: +"", tokens: []}
          @word = nil    # the open word's token hash
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
          when "word" then start_word(node)
          when "lemma" then add_lemma(node)
          when "analysis" then add_analysis(node)
          when "punct" then add_punct(node)
          end
        end

        def end_element(node)
          case node.name
          when "word" then finish_word
          when "sentence" then finish_sentence
          end
        end

        def start_sentence(node)
          @sentence_ordinal += 1
          id = node.attribute("id")
          if id.nil? || id.empty?
            raise ParseError,
                  "#{@path}: <sentence> ##{@sentence_ordinal} (document order) is missing its @id"
          end

          @current = { id: id, location: node.attribute("location"), text: +"", tokens: [] }
          finish_sentence if node.empty_element? # defensive: <sentence/> with no words
        end

        # Beta Code decodes at this boundary; the pristine decoded form joins
        # the surface text space-separated and rides the token.
        def start_word(node)
          return unless @current

          form = Betacode.decode(node.attribute("form").to_s)
          @word = { "id" => node.attribute("id"), "form" => form }.compact
          @current[:text] << " " unless @current[:text].empty?
          @current[:text] << form
          finish_word if node.empty_element? # defensive: a <word/> without a lemma child
        end

        # lemma/@entry is Unicode Greek, NFC'd here (429 upstream are not).
        # No entry attribute = unlemmatized (id="unknown") — the token stays
        # lemma-less. TreeTagger/disambiguated ride only where disambiguation
        # actually happened (see class note).
        def add_lemma(node)
          return unless @word

          entry = node.attribute("entry")
          if entry && !entry.empty?
            @word["lemma"] = Normalize.nfc(entry)
            lemma_id = node.attribute("id")
            @word["lemma_id"] = lemma_id if lemma_id && !lemma_id.empty?
            pos = node.attribute("POS")
            @word["pos"] = pos if pos && !pos.empty?
          end
          return unless node.attribute("TreeTagger") == "true"

          @word["tree_tagger"] = true
          confidence = node.attribute("disambiguated")
          @word["disambiguated"] = confidence if confidence && confidence != "n/a"
        end

        def add_analysis(node)
          return unless @word&.key?("lemma")

          morph = node.attribute("morph")
          (@word["analyses"] ||= []) << morph if morph && !morph.empty?
        end

        # Verbatim, glued to the left (class note): no space before the mark;
        # the next word re-opens with its separating space.
        def add_punct(node)
          return unless @current

          @current[:text] << node.attribute("mark").to_s
        end

        def finish_word
          @current[:tokens] << @word if @current && @word
          @word = nil
        end

        def finish_sentence
          current = @current
          @current = nil
          return unless current

          @sentences << Sentence.new(
            id: current[:id], location: current[:location],
            text: Normalize.nfc(current[:text].strip), tokens: current[:tokens]
          )
        end
      end
      private_constant :Extraction
    end
  end
end
