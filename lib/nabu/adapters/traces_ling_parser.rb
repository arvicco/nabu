# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one TraCES TEI-Ling file (P46-2) — the
    # `traces-teiling` family. A TEI-Ling export is a flat stream of
    # feature structures, one per orthographic Gǝʿǝz word:
    #
    #   <fs type="graphunit" xml:id="W…">
    #     <f name="fidäl">በወርኀ</f>
    #     <f name="translit">ba-warḫa</f>
    #     <f name="analysis"><fs type="tokens">
    #       <f name="lit" fVal="ba"><fs type="morpho">
    #         <f name="pos">Preposition</f> … <f name="lex">L79528…--በ</f>
    #       </fs></f>
    #       <f name="lit" fVal="warḫa"> … </f>
    #     </fs></f>
    #   </fs>
    #
    # One graphunit = one passage: text is the fidäl form verbatim (NFC is
    # a no-op on Ethiopic), citation "w<k>" positional (the export carries
    # no chapter/verse apparatus; the graphunit @xml:id UUID rides the "id"
    # annotation for upstream addressability). Annotations:
    #
    #   "translit" — the project transliteration of the whole graphunit
    #   "tokens"   — one hash per analyzed token (a proclitic-fused word
    #                splits into several): "form" (the lit @fVal), every
    #                morpho feature verbatim under its upstream name
    #                (pos/tam/person/gender/number/case/state…), and the
    #                `lex` lemma link split into "lex_id" (the L-prefixed
    #                DILLMANN ENTRY ID — the cross-shelf crosswalk) +
    #                "lemma" (the fidäl lemma after the "--").
    #
    # A graphunit with an empty fidäl emits nothing and consumes no
    # ordinal. Unnamed morpho features (seen only in the stray Alpheios
    # export, which discover skips) are ignored defensively.
    #
    # == Streaming, namespace-blind
    #
    # The biggest export ("MM") is ~16 MB — over the house >5 MB DOM
    # threshold — so the only Nokogiri entry point is Nokogiri::XML::Reader,
    # one pass. Three upstream files use a nonstandard `https://` TEI
    # namespace URI; the parser matches LOCAL NAMES only, never the URI.
    class TracesLingParser
      def parse(path, urn:, language:, title: nil)
        extraction = File.open(path, "r") do |io|
          Extraction.new(reader: Nokogiri::XML::Reader(io, path)).call
        end
        build_document(extraction, urn: urn, language: language, title: title, path: path)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      private

      def build_document(extraction, urn:, language:, title:, path:)
        metadata = { "corresp" => extraction.corresp }.compact
        document = Document.new(urn: urn, language: language, title: title,
                                canonical_path: path, metadata: metadata)
        extraction.units.each_with_index do |unit, sequence|
          document << Passage.new(
            urn: "#{urn}:w#{sequence + 1}", language: language,
            text: Normalize.nfc(unit.fetch(:fidal)),
            annotations: annotations_for(unit), sequence: sequence
          )
        end
        raise ParseError, "#{path}: no graphunits with fidäl text" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      def annotations_for(unit)
        {
          "id" => unit[:id],
          "translit" => unit[:translit],
          "tokens" => (unit[:tokens] unless unit[:tokens].empty?)
        }.compact
      end

      # The single-pass Reader state machine over the graphunit stream.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        private_constant :READER, :TEXT_NODE_TYPES

        Result = Data.define(:units, :corresp)

        def initialize(reader:)
          @reader = reader
          @corresp = nil
          @units = []
          @unit = nil     # the open graphunit, or nil
          @token = nil    # the open token (f name="lit"), or nil
          @feature = nil  # the open leaf feature accumulator, or nil
        end

        def call
          @reader.each { |node| process(node) }
          Result.new(units: @units, corresp: @corresp)
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when *TEXT_NODE_TYPES then @feature[1] << node.value.to_s if @feature
          end
        end

        def start_element(node)
          case local_name(node)
          when "TEI" then @corresp ||= presence(node.attribute("corresp"))
          when "fs" then start_fs(node)
          when "f" then start_f(node)
          end
        end

        def start_fs(node)
          return unless node.attribute("type") == "graphunit" && @unit.nil?

          @unit = { id: presence(node.attribute("xml:id")), fidal: +"", translit: +"",
                    tokens: [], depth: node.depth }
          close_unit(node) if node.empty_element?
        end

        # <f> plays three roles: the graphunit's leaf features (fidäl,
        # translit), the token opener (name="lit", form in @fVal), and the
        # morpho leaves inside a token.
        def start_f(node)
          return unless @unit

          name = presence(node.attribute("name")) or return
          if name == "lit"
            @token = { "form" => presence(node.attribute("fVal")) }.compact
            @unit[:tokens] << @token
          elsif leaf_feature?(name) && !node.empty_element?
            @feature = [name, +""]
          end
        end

        # A leaf worth accumulating: the graphunit's own fidäl/translit, or
        # any named morpho feature once a token is open ("analysis" is the
        # container, never a leaf).
        def leaf_feature?(name)
          %w[fidäl translit].include?(name) || (@token && name != "analysis")
        end

        def end_element(node)
          case local_name(node)
          when "fs" then close_unit(node) if @unit && node.depth == @unit[:depth]
          when "f" then close_f
          end
        end

        def close_f
          return unless @feature

          name, value = @feature
          @feature = nil
          value = value.gsub(/[[:space:]]+/, " ").strip
          return if value.empty?

          case name
          when "fidäl" then @unit[:fidal] << value
          when "translit" then @unit[:translit] << value
          when "lex" then store_lex(value)
          else @token[name] = value if @token
          end
        end

        # "L2d417be9…--ሞተ" → the Dillmann entry id + the fidäl lemma.
        # A lex without the separator (or without an id half) is kept
        # verbatim under "lex" — never guessed at.
        def store_lex(value)
          return unless @token

          id, lemma = value.split("--", 2)
          if lemma && !id.to_s.empty?
            @token["lex_id"] = id
            @token["lemma"] = lemma unless lemma.empty?
          else
            @token["lex"] = value
          end
        end

        def close_unit(_node)
          unit = @unit
          @unit = nil
          @token = nil
          @feature = nil
          return if unit[:fidal].strip.empty?

          unit[:fidal] = unit[:fidal].strip
          unit[:translit] = presence(unit[:translit].strip)
          @units << { id: unit[:id], fidal: unit[:fidal], translit: unit[:translit],
                      tokens: unit[:tokens] }.compact
        end

        def presence(value)
          value if value && !value.empty?
        end

        def local_name(node)
          node.name.split(":").last
        end
      end
      private_constant :Extraction
    end
  end
end
