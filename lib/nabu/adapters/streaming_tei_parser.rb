# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The shared skeleton of the streaming TEI parser families — the
    # boilerplate every one-pass Nokogiri::XML::Reader family had been
    # hand-cloning: canonical-path resolution, the Reader extraction seam
    # (malformed XML → ParseError naming the path), the positional collision
    # tolerance, and the Document assembly. Its nested Walker carries the
    # Reader state machine's dispatch scaffold and its small helpers.
    #
    # What stays in a subclass is everything that makes a family a family:
    # its #parse signature and the metadata it merges, its header mining,
    # its citation grammar, its unit shaping. A subclass supplies
    #
    #   #extraction_class   → its Walker subclass (constructed with
    #                         reader:, path:, plus any extract options;
    #                         #call returns what #parse consumes)
    #   #no_passages_message (optional) → the empty-document wording
    #
    # and may override #build_document wholesale where its passage
    # assembly genuinely differs. Keep per-source logic OUT of this file:
    # it sits in every composing family's derivation closure, so an edit
    # here re-derives all of them — correct for a skeleton fix, and the
    # reason nothing source-specific belongs here.
    class StreamingTeiParser
      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      # One streaming pass: the family's Walker over a Reader on +source+.
      # +options+ pass through to the Walker's constructor verbatim.
      def extract(source, path:, **options)
        with_io(source) do |io|
          extraction_class.new(reader: Nokogiri::XML::Reader(io, path), path: path, **options).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def extraction_class
        raise NotImplementedError, "#{self.class} must define #extraction_class (its Walker subclass)"
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      # The house collision tolerance: a duplicate citation disambiguates
      # deterministically in document order (":b2", ":b3", …), never
      # quarantines the document.
      def disambiguate_collisions(units)
        seen = Hash.new(0)
        units.map do |unit|
          seen[unit.citation] += 1
          count = seen[unit.citation]
          count == 1 ? unit : unit.with(citation: "#{unit.citation}:b#{count}")
        end
      end

      # Units (citation/text/annotations) → a Document: whitespace runs
      # collapse to one space, ends strip, NFC at the adapter boundary;
      # sequence is document order. No passages, or any model validation
      # failure, is a ParseError naming the path.
      def build_document(units, urn:, language:, title:, path:, metadata:, license_override: nil)
        document = Document.new(urn: urn, language: language, title: title,
                                canonical_path: path, metadata: metadata,
                                license_override: license_override)
        units.each_with_index do |unit, sequence|
          document << Passage.new(
            urn: "#{urn}:#{unit.citation}",
            language: language,
            text: Normalize.nfc(unit.text.gsub(/[[:space:]]+/, " ").strip),
            annotations: unit.annotations,
            sequence: sequence
          )
        end
        raise ParseError, "#{path}: #{no_passages_message}" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      def no_passages_message = "no citable passages found in <text><body>"

      # The Reader state machine's scaffold. A subclass's constructor calls
      # super(reader:, path:) and sets up its own state; it owns its #call
      # (typically `@reader.each { |node| process(node) }` plus the result
      # shaping) and the three event handlers #start_element, #end_element
      # and #text_node. #dropping? reads the conventional @drop_depth (the
      # depth of a subtree being skipped, or nil).
      class Walker
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        private_constant :READER, :TEXT_NODE_TYPES

        def initialize(reader:, path:)
          @reader = reader
          @path = path
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when *TEXT_NODE_TYPES then text_node(node)
          end
        end

        def dropping? = !@drop_depth.nil?

        def flatten(value)
          presence(value&.gsub(/[[:space:]]+/, " ")&.strip)
        end

        def presence(value)
          value if value && !value.empty?
        end

        def local_name(node)
          node.name.split(":").last
        end
      end
    end
  end
end
