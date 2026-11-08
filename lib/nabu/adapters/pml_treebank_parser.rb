# frozen_string_literal: true

require "nokogiri"
require "stringio"

require_relative "source_read"

module Nabu
  module Adapters
    # Streaming reader for an ALDT treebank serialized in PML (Prague Markup
    # Language) — the `aldt-pml` parser family (P164), first composed by
    # Adapters::Llct1 (the Late Latin Charter Treebank 1). Deliberately
    # scoped to the one PML instance the library holds: the
    # `aldt_treebank` schema TrEd writes for Latin Dependency Treebank
    # (LDT/AGDT-style) annotation. No general PML machinery (schema
    # resolution, references, list/sequence types) — none is needed.
    #
    # == The format (censused from the real LLCT1 v1.2 bytes, 2026-11-08)
    #
    #   <aldt_treebank xmlns="http://ufal.mff.cuni.cz/pdt/pml/">
    #     <head><schema href="aldt_schema.xml"/></head>
    #     <aldt_meta>…annotator placeholders…</aldt_meta>
    #     <aldt_trees>
    #       <LM id="2934402" document_id="CDL" subdoc="16" date="714" …>   ← a sentence tree
    #         <LM id="1" relation="AuxP" form="In" lemma="in1" pos="preposition" …>
    #           <LM id="2" relation="ADV" form="nomine" lemma="nomen1" … case="ablative">
    #           …
    #       </LM>
    #     </aldt_trees>
    #   </aldt_treebank>
    #   <?tred-pattern …?> <?tred-hint …?>                                 ← TrEd display PIs
    #
    # Every node is an <LM>. A DIRECT child of <aldt_trees> is a sentence
    # tree: its @id is a corpus-wide sentence key (2934402 …) and its other
    # attributes are sentence/document metadata (the adapter's to read).
    # Every NESTED <LM> is a word node: @id is its 1-based word position
    # in the sentence (document order of the XML is TREE order, not word
    # order — "Domini Dei" arrives as id 3 then 4 under id 5), annotation
    # rides attributes, and the dependency head is the PARENT element (no
    # head attribute exists): a child of the sentence root heads to "0".
    #
    # == Two entry points
    #
    # - PmlTreebankParser.tree_spans(PmlTreebankParser.read(path)) — a
    #   LEXICAL pass over the bytes
    #   (no XML parse) returning each sentence tree's byte span and root
    #   attributes. Upstream ships the whole treebank as ONE 42 MB file, so
    #   an adapter that documents a sub-file grain (LLCT1: the charter)
    #   cuts its document's trees by byte range instead of re-reading the
    #   corpus once per document. The scan tracks <LM>/</LM> depth inside
    #   <aldt_trees>; attribute values carry no raw "<" or ">" (TrEd escapes
    #   them; the LLCT1 census found none), which is what makes a tag regex
    #   sound here. PmlTreebankParser.fragment re-wraps chosen spans as a
    #   well-formed <aldt_trees> document.
    # - #trees(source, path:) / #parse — the Nokogiri::XML::Reader pass
    #   (never a DOM: 42 MB) over a whole file or a fragment.
    #
    # == Passage minting (sentence tree = passage)
    #
    # - urn = "<document-urn>:<tree @id>" (the corpus-wide sentence key —
    #   the GLAUx struct_id / PROIEL precedent); sequence = tree order.
    # - text = word forms in WORD order (@id), space-separated; a
    #   single-character punctuation form (, . ; :) glues LEFT. Lacuna
    #   markers ("....." — the editions' gaps) stay spaced words. NFC.
    # - annotations = { "tokens" => [ {upstream attributes verbatim, in
    #   upstream order …, "head"}, … ] } — lemma screened and split as
    #   below.
    #
    # == Lemma placeholders (the lemma pool stays clean — the GLAUx rule)
    #
    # LLCT1 lemmatizes punctuation and unresolvable words with placeholder
    # values: "unknown1" (26,469 nodes — commas, periods, lacunae and the
    # odd unresolved word), "other" (727), and punctuation lemmas
    # "semicolon1"/"comma1". These are not dictionary forms: the token
    # keeps the value under "lemma_placeholder" and carries NO "lemma" key,
    # so the lemma index never mints "unknown".
    #
    # == Homograph indices (split, never lost)
    #
    # Every real LDT lemma ends in a homograph index ("nomen1", "dico2" —
    # 'say' vs dico1 'dedicate'; census: 221,345 ×1, 3,726 ×2, 35 ×3). The
    # lemma index keys on the dictionary form, so the token's "lemma" is
    # the form WITHOUT the index and "lemma_homograph" keeps the digit —
    # upstream's value is exactly lemma + lemma_homograph (the
    # lexicon-tei precedent strips homograph digits at parse; here the
    # digit rides beside it). Done at parse rather than as a LemmaKeys
    # strip row so the shared lemma-key core stays untouched.
    class PmlTreebankParser
      NAMESPACE = "http://ufal.mff.cuni.cz/pdt/pml/"
      TREES_ELEMENT = "aldt_trees"

      # A sentence tree: its corpus-wide id, its root attributes (minus id)
      # and its word tokens in word order.
      Tree = Data.define(:id, :attributes, :tokens)

      # A sentence tree's byte span in the file and its root attributes
      # (minus id).
      Span = Data.define(:id, :offset, :length, :attributes)

      PLACEHOLDER_LEMMAS = %w[unknown1 other].freeze
      PUNCTUATION_FORM = /\A[[:punct:]]+\z/
      HOMOGRAPH = /\A(?<lemma>.*\D)(?<index>\d+)\z/
      GLUE_LEFT = /\A[,.;:]\z/
      LM_TAG = %r{<(/?)LM\b[^>]*?(/?)>}n
      ATTRIBUTE = /([\w:.-]+)="([^"]*)"/n
      ENTITIES = { "&lt;" => "<", "&gt;" => ">", "&quot;" => '"', "&apos;" => "'", "&amp;" => "&" }.freeze
      private_constant :PLACEHOLDER_LEMMAS, :PUNCTUATION_FORM, :HOMOGRAPH, :GLUE_LEFT, :LM_TAG, :ATTRIBUTE, :ENTITIES

      # +path+ through the encoding belt (invalid UTF-8 is a ParseError),
      # as a BINARY buffer: the span scan and the fragment cut work in byte
      # offsets. A caller cutting several documents from one file reads it
      # once and passes the buffer on.
      def self.read(path)
        SourceRead.utf8_file(path, label: "aldt-pml").b
      end

      # The lexical span scan over a #read buffer (class note). Returns
      # Spans in file order; [] when the buffer has no <aldt_trees>.
      def self.tree_spans(bytes)
        start = bytes.index("<#{TREES_ELEMENT}") or return []
        finish = bytes.index("</#{TREES_ELEMENT}>", start) || bytes.bytesize
        scan_spans(bytes, start, finish)
      end

      # The chosen [offset, length] byte ranges of a #read buffer,
      # re-wrapped as one well-formed <aldt_trees> UTF-8 document (the PML
      # namespace kept). A range past the buffer is a ParseError naming
      # +path+ (SourceRead.slice — never a short cut).
      def self.fragment(bytes, ranges, path:)
        body = ranges.map do |offset, length|
          SourceRead.slice(bytes, offset: offset, length: length, what: "#{path}: tree span")
        end
        wrapped = %(<#{TREES_ELEMENT} xmlns="#{NAMESPACE}">\n).b
        wrapped << body.join("\n".b) << "\n</#{TREES_ELEMENT}>\n".b
        wrapped.force_encoding(Encoding::UTF_8)
      end

      def self.scan_spans(bytes, start, finish)
        spans = []
        depth = 0
        open = nil
        position = start
        while (match = LM_TAG.match(bytes, position)) && match.begin(0) < finish
          position = match.end(0)
          closing = !match[1].empty?
          self_closing = !match[2].empty?
          if closing
            depth -= 1
            spans << span(bytes, open, match.end(0)) if depth.zero?
          else
            open = match.begin(0) if depth.zero?
            if self_closing
              spans << span(bytes, open, match.end(0)) if depth.zero?
            else
              depth += 1
            end
          end
        end
        spans
      end
      private_class_method :scan_spans

      def self.span(bytes, offset, stop)
        tag_end = bytes.index(">", offset)
        tag = SourceRead.slice(bytes, offset: offset, length: tag_end - offset + 1, what: "tree start tag")
        attributes = tag.scan(ATTRIBUTE).to_h do |name, value|
          [name.force_encoding(Encoding::UTF_8),
           value.gsub(/&(?:lt|gt|quot|apos|amp);/n, ENTITIES).force_encoding(Encoding::UTF_8)]
        end
        id = attributes.delete("id")
        Span.new(id: id, offset: offset, length: stop - offset, attributes: attributes)
      end
      private_class_method :span

      # Every sentence tree of +source+ (a path or an IO), via
      # Nokogiri::XML::Reader. Malformed XML is a ParseError naming +path+.
      def trees(source, path:)
        with_io(source) { |io| Extraction.new(Nokogiri::XML::Reader(io, path)).call }
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # One Document, one Passage per sentence tree (class note). The
      # caller (the adapter) owns urn, title, metadata and the license.
      def parse(source, urn:, language:, canonical_path:, title: nil, metadata: {}, license_override: nil)
        document = Document.new(urn: urn, language: language, title: title, canonical_path: canonical_path,
                                metadata: metadata, license_override: license_override)
        trees(source, path: canonical_path).each_with_index do |tree, sequence|
          text = surface(tree.tokens)
          next if text.empty?

          document << Passage.new(urn: "#{urn}:#{tree.id}", language: language, text: text,
                                  annotations: { "tokens" => tree.tokens.map { |t| lemma_screened(t) } },
                                  sequence: sequence)
        end
        raise ParseError, "#{canonical_path}: no sentence trees for #{urn}" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{canonical_path}: #{e.message}"
      end

      private

      # A path reads through the belt; an IO (a #fragment) is the caller's.
      def with_io(source)
        yield(source.is_a?(String) ? StringIO.new(SourceRead.utf8_file(source, label: "aldt-pml")) : source)
      end

      def surface(tokens)
        text = +""
        tokens.each do |token|
          form = token["form"].to_s
          next if form.empty?

          text << " " unless text.empty? || form.match?(GLUE_LEFT)
          text << form
        end
        Normalize.nfc(text.strip)
      end

      def lemma_screened(token)
        lemma = token["lemma"]
        return token unless lemma
        if PLACEHOLDER_LEMMAS.include?(lemma) || punctuation?(token)
          return token.except("lemma").merge("lemma_placeholder" => lemma)
        end

        match = HOMOGRAPH.match(lemma)
        return token unless match

        token.merge("lemma" => match[:lemma], "lemma_homograph" => match[:index])
      end

      def punctuation?(token)
        token["pos"] == "punctuation" || token["form"].to_s.match?(PUNCTUATION_FORM)
      end

      # The Reader state machine: an <LM> with no open <LM> above it is a
      # sentence tree; every <LM> inside one is a word whose head is the
      # enclosing <LM> ("0" when that is the tree root).
      class Extraction
        READER = Nokogiri::XML::Reader
        private_constant :READER

        def initialize(reader)
          @reader = reader
          @trees = []
          @stack = []
          @current = nil
        end

        def call
          @reader.each do |node|
            next unless node.name == "LM"

            case node.node_type
            when READER::TYPE_ELEMENT then open_node(node)
            when READER::TYPE_END_ELEMENT then close_node
            end
          end
          @trees
        end

        private

        def open_node(node)
          attributes = node.attributes.transform_values { |v| Normalize.nfc(v) }
          if @stack.empty?
            @current = { id: attributes.delete("id"), attributes: attributes, tokens: [] }
            @stack.push("0")
          else
            @current[:tokens] << attributes.merge("head" => @stack.last)
            @stack.push(attributes["id"])
          end
          close_node if node.empty_element?
        end

        def close_node
          @stack.pop
          return unless @stack.empty? && @current

          tokens = @current[:tokens].sort_by { |t| t["id"].to_i }
          @trees << Tree.new(id: @current[:id], attributes: @current[:attributes], tokens: tokens)
          @current = nil
        end
      end
      private_constant :Extraction
    end
  end
end
