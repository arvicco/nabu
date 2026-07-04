# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one PROIEL treebank XML file — the third parser
    # family (architecture §3), sibling to EpidocParser and ConlluParser. A
    # standalone, individually tested component that adapters (Proiel, and
    # later TOROT — which reuses this family) compose. Same call shape as the
    # other parsers: #parse(source, urn:, language:, title:, canonical_path:).
    #
    # The parser is streaming by contract: real PROIEL sources reach ~29 MB
    # (cic-off.xml is ~2 MB, the NT gospels far larger), so the only Nokogiri
    # entry point is Nokogiri::XML::Reader — a whole-document DOM is never
    # built (CLAUDE.md "things that look like good ideas but aren't"; enforced
    # structurally by the test suite, as for EpidocParser).
    #
    # == The format
    #
    #   <proiel schema-version="2.1">
    #     <annotation> … </annotation>          ← controlled vocabularies; SKIPPED
    #     <source id="cic-off" language="lat">
    #       <title>…</title> …bibliographic children…
    #       <div id="3172">
    #         <sentence id="86000" status="reviewed">
    #           <token id="…" form="…" lemma="…" part-of-speech="…"
    #                  morphology="…" head-id="…" relation="…"
    #                  citation-part="1.1" presentation-before="(" presentation-after=" "/>
    #           …
    #         </sentence>
    #       </div>
    #     </source>
    #   </proiel>
    #
    # The <annotation> block is deliberately NOT slurped: it merely LABELS the
    # terse codes (relation "adv", part-of-speech "G-", morphology field/value
    # tables). Every token already carries those codes on its own attributes,
    # so the dictionaries add bulk without adding information the store needs;
    # decoding them is a downstream/enrichment concern. Because the state
    # machine only reacts to <source>/<sentence>/<token>, the whole
    # <annotation> subtree streams past untouched with no special-casing.
    #
    # == Passage minting (sentence = passage)
    #
    # - urn = "<document-urn>:<sentence-id>", the sentence/@id verbatim. Those
    #   ids are the stable upstream database keys (86000, 88119, …) — NOT
    #   contiguous, NOT document-order, so they are used as-is, never renumbered.
    #   A <sentence> without an @id is a Nabu::ParseError naming the file and the
    #   sentence's document position (a missing id means the file is malformed,
    #   not something to paper over — same discipline as ConlluParser's sent_id).
    # - sequence = kept-sentence order from 0.
    # - text = per token, presentation-before + form + presentation-after
    #   concatenated (PROIEL's surface-text encoding: the presentation attrs ARE
    #   the inter-token spacing and punctuation). NFC at this boundary.
    #   text_normalized is minted by Passage.new (P6-4 per-language search
    #   form, Normalize.search_form) — the parser passes only pristine text.
    #
    # == Empty tokens
    #
    # Tokens carrying `empty-token-sort` (and no `form`) are null/elided nodes
    # of the dependency graph (PROIEL's "C"/"V"/"P" empties; heavy in TOROT).
    # They contribute NOTHING to the surface text but ARE kept in the token
    # annotations — the tree is incomplete without them.
    #
    # == Annotations (the treebank payload)
    #
    # annotations = {
    #   "tokens" => [ {"id","form","lemma","part_of_speech","morphology",
    #                  "head_id","relation","citation_part","information_status",
    #                  "empty_token_sort"}, … ],   # nil attrs dropped, keys lean
    #   "citation" => <first token's citation-part, when derivable>,
    #   "status"   => <sentence/@status, when present>
    # }
    # <slash> secondary-edge children of a token are ignored (secondary
    # dependencies are not carried downstream; the basic tree lives in
    # head-id/relation).
    #
    # == Cross-checks (honest mismatch surfacing, EpidocParser spirit)
    #
    # - <source id> must equal the tail of the caller-supplied document urn
    #   (mismatch → ParseError): the adapter mints the urn from the same id, so a
    #   divergence means the file on disk is not the document the caller asked for.
    # - Caller-supplied +language+ wins, but if <source language> disagrees it is
    #   a ParseError rather than a silent override — a language mismatch is a
    #   cataloguing error worth surfacing, not smoothing over.
    # - Zero sentences → ParseError.
    #
    # == Upstream quirks (verified against test/fixtures/proiel/)
    #
    # - schema-version="2.1" is the ATTRIBUTE PROIEL emits, though the bundled
    #   xsd is labelled 2.0; the parser keys off structure, not the version.
    # - <div> MAY lack an @id (seen in TOROT); divs are structural only — the
    #   parser never reads div attributes, so this is a non-issue here.
    # - <source> headers are sparse and vary per source (TOROT omits most
    #   children); every child except id/language is optional and ignored — the
    #   ADAPTER, not the parser, reads <title>/<license> for its metadata.
    class ProielParser
      # A finished sentence awaiting Passage construction: its upstream id, the
      # sentence status, the reconstructed surface text, and the token hashes.
      Sentence = Data.define(:id, :status, :text, :tokens)
      private_constant :Sentence

      # PROIEL token attribute → annotation key, in the order the store keeps
      # them. Anything absent on a token is simply not in the hash.
      TOKEN_ATTRIBUTES = {
        "id" => "id",
        "form" => "form",
        "lemma" => "lemma",
        "part-of-speech" => "part_of_speech",
        "morphology" => "morphology",
        "head-id" => "head_id",
        "relation" => "relation",
        "citation-part" => "citation_part",
        "information-status" => "information_status",
        "empty-token-sort" => "empty_token_sort"
      }.freeze
      private_constant :TOKEN_ATTRIBUTES

      # Same signature family as EpidocParser#parse / ConlluParser#parse.
      def parse(source, urn:, language:, title: nil, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        sentences = extract_sentences(source, path: path, urn: urn, language: language)
        build_document(sentences, urn: urn, language: language, title: title, path: path)
      end

      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      def extract_sentences(source, path:, urn:, language:)
        with_io(source) do |io|
          Extraction.new(
            reader: Nokogiri::XML::Reader(io, path), path: path, urn: urn, language: language
          ).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      def build_document(sentences, urn:, language:, title:, path:)
        document = Document.new(urn: urn, language: language, title: title, canonical_path: path)
        sentences.each_with_index do |sentence, sequence|
          text = sentence.text
          next if text.empty? # a sentence of only empty tokens has no surface text

          document << Passage.new(
            urn: "#{urn}:#{sentence.id}",
            language: language,
            text: text,
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
        citation = sentence.tokens.filter_map { |token| token["citation_part"] }.first
        result["citation"] = citation if citation
        result["status"] = sentence.status if sentence.status
        result
      end

      # The single-pass Reader state machine. Reacts only to <source> (metadata
      # cross-check), <sentence> (passage boundary), and <token> (text + token
      # annotations); everything else — <annotation>, <div>, <slash>, header
      # children — streams past untouched.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        private_constant :READER, :TEXT_NODE_TYPES

        def initialize(reader:, path:, urn:, language:)
          @reader = reader
          @path = path
          @urn = urn
          @language = language
          @sentences = []
          @sentence_ordinal = 0
          @current = nil # {id:, status:, text: +"", tokens: []}
          @source_seen = false
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no <source> element found" unless @source_seen

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
          when "source" then start_source(node)
          when "sentence" then start_sentence(node)
          when "token" then add_token(node)
          end
        end

        def end_element(node)
          finish_sentence if node.name == "sentence" && @current
        end

        # <source> carries the cross-check attributes. Reject a file whose source
        # id is not the document the caller's urn names, or whose language
        # contradicts the caller — both are cataloguing errors, surfaced not
        # smoothed (see file header).
        def start_source(node)
          @source_seen = true
          source_id = node.attribute("id")
          expected = @urn.split(":").last
          unless source_id == expected
            raise ParseError, "#{@path}: source id mismatch: urn tail is #{expected.inspect}, " \
                              "<source id> is #{source_id.inspect}"
          end

          source_language = node.attribute("language")
          return if source_language.nil? || source_language == @language

          raise ParseError, "#{@path}: language mismatch: caller says #{@language.inspect}, " \
                            "<source language> is #{source_language.inspect}"
        end

        def start_sentence(node)
          @sentence_ordinal += 1
          id = node.attribute("id")
          if id.nil? || id.empty?
            raise ParseError,
                  "#{@path}: <sentence> ##{@sentence_ordinal} (document order) is missing its @id"
          end

          @current = { id: id, status: node.attribute("status"), text: +"", tokens: [] }
          finish_sentence if node.empty_element? # defensive: <sentence/> with no tokens
        end

        def add_token(node)
          return unless @current

          @current[:text] << surface(node)
          @current[:tokens] << token_hash(node)
        end

        # PROIEL surface encoding: the whitespace/punctuation lives in the
        # presentation attributes, not between elements. Empty tokens have no
        # form and (normally) no presentation attrs, so they add nothing.
        def surface(node)
          "#{node.attribute('presentation-before')}#{node.attribute('form')}#{node.attribute('presentation-after')}"
        end

        def token_hash(node)
          hash = {}
          TOKEN_ATTRIBUTES.each do |attribute, key|
            value = node.attribute(attribute)
            hash[key] = value unless value.nil?
          end
          hash
        end

        def finish_sentence
          current = @current
          @current = nil
          @sentences << Sentence.new(
            id: current[:id],
            status: current[:status],
            text: Normalize.nfc(current[:text].strip),
            tokens: current[:tokens]
          )
        end
      end
      private_constant :Extraction
    end
  end
end
