# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming reader for the INESS Menotec "get-sentences" export (P40-2) —
    # a SIBLING of ProielParser, not a composition of it. The Menotec token
    # vocabulary IS genuine PROIEL (lemma, part-of-speech, positional
    # morphology, head-id/relation dependency edges, <slash> secondary edges),
    # so this parser mints the SAME passage/annotation shape ProielParser does —
    # the tokens[] hashes carry identical keys, plus `foreign_ids` for
    # Menotec's Menota / island-id back-references, and passages key on
    # sentence/@id exactly as the PROIEL family. The token/morph mapping is
    # deliberately re-stated here rather than reached into ProielParser
    # (whose Extraction + TOKEN_ATTRIBUTES are private_constants), because the
    # ENVELOPE is irreconcilably different and composition would mean widening
    # that parser's contract for one source.
    #
    # == Why a sibling and not ProielParser
    #
    # ProielParser is a single-Reader streaming state machine over ONE
    # well-formed document: `<proiel>` root, a shared `<annotation>` vocabulary
    # block, a `<source>` metadata header it cross-checks (and hard-REQUIRES).
    # The INESS export has NONE of that. It is a BLANK-LINE-SEPARATED STREAM of
    # per-sentence fragments, each its OWN mini-document:
    #
    #   # text = <surface>
    #   # sent_id = <n>
    #   <?xml version="1.0" encoding="UTF-8"?>
    #   <sentence id="…" status="reviewed" presentation-before="…">
    #    <token id="…" form="…" lemma="…" part-of-speech="…" morphology="…"
    #           head-id="…" relation="…" presentation-after=" "
    #           foreign-ids="menota-id=w00001"/>
    #    <token …>
    #     <slash target-id="…" relation="xsub"/>
    #    </token>
    #   </sentence>
    #
    # The repeated `<?xml?>` declarations make the whole file un-parseable as
    # one document, so the reader SPLITS on blank lines and parses one
    # `<sentence>` fragment at a time (the file is read line-by-line — no giant
    # DOM). The `# text` / `# sent_id` comment headers are the tiger-xml
    # surface and sequence; the passage TEXT is reconstructed from the tokens'
    # own presentation attributes (the PROIEL convention), which reproduces the
    # `# text` header exactly, so the headers are informational only.
    #
    # == One document = one treebank
    #
    # A treebank's sentence ids are unique across its several upstream documents
    # (Alvíssmál's blocks continue the Edda's earlier poems), so the adapter
    # feeds ALL of a treebank's *.xml files here as one +paths+ list and gets
    # one Document whose passage urns are `<treebank-urn>:<sentence-@id>`.
    #
    # == Loud on surprises
    #
    # A block with no parseable `<sentence>`, a `<sentence>` without an @id,
    # malformed fragment XML, or a treebank that yields zero sentences all raise
    # Nabu::ParseError (naming the file) — the EpidocParser/ProielParser
    # discipline: a malformed export is quarantined, never papered over.
    class MenotecStreamParser
      # A finished sentence awaiting Passage construction.
      Sentence = Data.define(:id, :status, :text, :tokens)
      private_constant :Sentence

      # PROIEL token attribute → annotation key (ProielParser's map, re-stated),
      # plus Menotec's `foreign-ids`. Anything absent on a token is simply not
      # in the hash.
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
        "empty-token-sort" => "empty_token_sort",
        "foreign-ids" => "foreign_ids"
      }.freeze
      private_constant :TOKEN_ATTRIBUTES

      # +paths+: the treebank's document files, in the order the caller wants
      # them concatenated (filename order). +canonical_path+: the treebank dir.
      def parse(paths, urn:, language:, title: nil, canonical_path: nil)
        sentences = Array(paths).flat_map { |path| extract_file(path) }
        build_document(sentences, urn: urn, language: language, title: title,
                                  canonical_path: canonical_path || Array(paths).first)
      end

      private

      # Read one document file, split into blank-line-separated fragment blocks,
      # parse each block's single <sentence>. Line-by-line — no whole-file DOM.
      def extract_file(path)
        sentences = []
        block = []
        File.foreach(path) do |line|
          if line.strip.empty?
            flush_block(block, sentences, path)
            block = []
          else
            block << line
          end
        end
        flush_block(block, sentences, path)
        sentences
      end

      def flush_block(lines, sentences, path)
        return if lines.empty?

        fragment = lines.join[%r{<sentence\b[\s\S]*</sentence>}]
        if fragment.nil?
          raise ParseError, "#{path}: a fragment block carries no <sentence> element: " \
                            "#{lines.join.strip[0, 80].inspect}"
        end

        sentences << parse_sentence(fragment, path)
      end

      def parse_sentence(fragment, path)
        doc = Nokogiri::XML(fragment)
        node = doc.at_xpath("/sentence")
        raise ParseError, "#{path}: malformed <sentence> fragment: #{doc.errors.first}" if node.nil?

        id = node["id"]
        raise ParseError, "#{path}: a <sentence> fragment is missing its @id" if id.nil? || id.empty?

        tokens = node.element_children.select { |child| child.name == "token" }
        text = +""
        token_hashes = tokens.map do |token|
          text << surface(token)
          token_hash(token)
        end
        Sentence.new(id: id, status: node["status"], text: Normalize.nfc(text.strip), tokens: token_hashes)
      end

      # PROIEL surface encoding: whitespace/punctuation live in the token
      # presentation attributes. Empty (form-less) tokens add nothing.
      def surface(token)
        "#{token['presentation-before']}#{token['form']}#{token['presentation-after']}"
      end

      def token_hash(token)
        hash = {}
        TOKEN_ATTRIBUTES.each do |attribute, key|
          value = token[attribute]
          hash[key] = value unless value.nil?
        end
        hash
      end

      def build_document(sentences, urn:, language:, title:, canonical_path:)
        document = Document.new(urn: urn, language: language, title: title, canonical_path: canonical_path)
        sentences.each_with_index do |sentence, sequence|
          next if sentence.text.empty? # a sentence of only empty tokens has no surface text

          document << Passage.new(
            urn: "#{urn}:#{sentence.id}",
            language: language,
            text: sentence.text,
            annotations: annotations(sentence),
            sequence: sequence
          )
        end
        raise ParseError, "#{canonical_path}: no <sentence> elements found" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{canonical_path}: #{e.message}"
      end

      def annotations(sentence)
        result = { "tokens" => sentence.tokens }
        citation = sentence.tokens.filter_map { |token| token["citation_part"] }.first
        result["citation"] = citation if citation
        result["status"] = sentence.status if sentence.status
        result
      end
    end
  end
end
