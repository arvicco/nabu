# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one TEI EpiDoc / CapiTainS edition file — the first
    # parser family (architecture §3): a standalone, individually tested
    # component that adapters (Perseus, First1KGreek, Papyri.info) compose.
    #
    # The parser is streaming by contract: Perseus has >5 MB editions, so the
    # only Nokogiri entry point here is Nokogiri::XML::Reader — a
    # whole-document DOM is never built (CLAUDE.md "things that look like good
    # ideas but aren't"; enforced structurally by the test suite).
    #
    # == How a file is read
    #
    # One pass over the document. The teiHeader streams past first: every
    # <cRefPattern> of the CTS refsDecl is recorded; the pattern with the MOST
    # regex capture groups is the lowest/deepest citation level, its @n is the
    # unit to collect (e.g. "line", "verse"), and the last tei:* step of its
    # replacementPattern xpath names the leaf element (tei:l vs tei:div).
    # Citation levels come from the refsDecl ONLY — div nesting is not
    # trusted (see quirks). In the body, passages are the leaf citation units
    # inside div[@type="edition"]; the citation path is the @n values of
    # ancestor divs that ARE citation levels plus the leaf's own @n, joined
    # with "." (2 John: chapter@n + "." + verse@n; Hymns/Ausonius: l/@n alone).
    # A div counts as a citation level only when its @subtype matches a
    # cRefPattern unit name — that is the CapiTainS convention, and it is what
    # keeps structural divs out of the citation path.
    #
    # == Text extraction rules
    #
    # - Mixed content is concatenated; <note> subtrees are dropped (editorial
    #   noise, not text). TODO(app-crit): <app>/<lem>/<rdg>, <choice>/<corr>/
    #   <sic>, <gap>/<del>/<supplied> do not occur in the Perseus fixtures;
    #   decide their policy (likely: keep lem/corr, drop rdg/sic) when a
    #   source actually exercises them — don't invent upstream formats.
    # - <lb>, <pb>, <milestone> carry no text; each contributes a single
    #   space so words never fuse across a break (harmless under collapsing).
    # - Whitespace runs collapse to one space; ends are stripped; NFC via
    #   Nabu::Normalize.nfc at this boundary. Units left empty after cleaning
    #   are skipped, but a document yielding zero passages is a ParseError.
    # - text_normalized is just NFC(text.downcase) for now — per-language
    #   diacritic folding is a later enrichment concern. The re-normalization
    #   matters: Greek case mapping can produce non-NFC sequences.
    #
    # == Upstream quirks (verified against test/fixtures/perseus/)
    #
    # - div[@type="edition"]/@n carries the full CTS edition urn; it is
    #   cross-checked against the caller-supplied urn (mismatch → ParseError).
    # - The Homeric Hymns files carry over-escaped patterns straight from the
    #   upstream conversion: matchPattern="(\\w+)" and \'$1\' in the
    #   replacementPattern — literal backslashes. Group counting and leaf
    #   detection tolerate both spellings.
    # - Structural, NON-citeable divs exist: Ausonius wraps its lines in
    #   div[@subtype="section"], yet the refsDecl cites lines flat by @n
    #   (":1", never ":21.1"). Hence the subtype-must-match-a-unit-name rule.
    # - Two schema vintages: current epidoc RNG vs 8.19 + schematron PI
    #   (Ausonius). No parser impact; both use the TEI namespace.
    # - Secondary legacy refsDecls (bare <refState>, n="TEI.2") sit next to
    #   the CTS one; they contain no cRefPattern and are ignored.
    # - <head> elements appear inside edition/structural divs but outside the
    #   citation units, so they are naturally excluded from passage text.
    # - Editorial <milestone unit="card|Para|para"/> markers appear INSIDE
    #   citation units (mixed content); see the space rule above.
    #
    # == Public API
    #
    #   Nabu::Adapters::EpidocParser.new.parse(
    #     source,                    # String file path, or an open IO
    #     urn: "urn:cts:...",        # CTS edition urn (caller knows it)
    #     language: "grc",           # BCP-47, from the edition slug
    #     title: "Hymn 13 ...",      # optional; __cts__.xml is adapter territory
    #     canonical_path: "..."      # required only for IOs without #path
    #   ) # => Nabu::Document
    class EpidocParser
      # One citable unit as extracted from the stream: citation is the dotted
      # path (e.g. "2", "1.7"), text is cleaned NFC content.
      Unit = Data.define(:citation, :text)
      private_constant :Unit

      # Parse one edition file into a Nabu::Document with ordered Passages at
      # the lowest citation level. Raises Nabu::ParseError on malformed XML,
      # missing/empty CTS refsDecl, urn mismatch, or zero citable passages.
      def parse(source, urn:, language:, title: nil, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        units = extract_units(source, path: path, urn: urn)
        build_document(units, urn: urn, language: language, title: title, path: path)
      end

      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      def extract_units(source, path:, urn:)
        with_io(source) do |io|
          Extraction.new(reader: Nokogiri::XML::Reader(io, path), path: path, urn: urn).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      def build_document(units, urn:, language:, title:, path:)
        document = Document.new(urn: urn, language: language, title: title, canonical_path: path)
        units.each_with_index do |unit, sequence|
          document << Passage.new(
            urn: "#{urn}:#{unit.citation}",
            language: language,
            text: unit.text,
            text_normalized: Normalize.nfc(unit.text.downcase),
            annotations: {},
            sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable passages found in div[@type=\"edition\"]" if document.empty?

        document
      rescue ValidationError => e
        # Domain-level refusals (duplicate citation @n, invalid text, ...) are
        # parse problems of THIS document: quarantine, don't abort the batch.
        raise ParseError, "#{path}: #{e.message}"
      end

      # The single-pass Reader state machine. Header phase records
      # cRefPatterns; body phase tracks the div stack and captures the text of
      # leaf citation units.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        DROPPED_ELEMENTS = %w[note].freeze
        BREAK_ELEMENTS = %w[lb pb milestone].freeze

        CRefPattern = Data.define(:unit, :depth, :replacement)
        Scheme = Data.define(:depth, :leaf_element, :unit_names, :deepest_unit)
        Capture = Struct.new(:citation, :depth, :buffer, :drop_depths, keyword_init: true)
        private_constant :CRefPattern, :Scheme, :Capture

        def initialize(reader:, path:, urn:)
          @reader = reader
          @path = path
          @urn = urn
          @patterns = []
          @div_stack = []
          @in_edition = false
          @edition_seen = false
          @capture = nil
          @units = []
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no div[@type=\"edition\"] found" unless @edition_seen

          @units
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when *TEXT_NODE_TYPES then text_node(node)
          end
        end

        def start_element(node)
          name = local_name(node)
          return captured_start(node, name) if @capture

          case name
          when "cRefPattern" then record_pattern(node)
          when "div" then start_div(node)
          else start_leaf(node) if leaf_start?(name)
          end
        end

        def end_element(node)
          name = local_name(node)
          if @capture
            captured_end(node, name)
          elsif name == "div"
            entry = @div_stack.pop
            @in_edition = false if entry && entry[:edition]
          end
        end

        def text_node(node)
          return unless @capture && @capture.drop_depths.empty?

          @capture.buffer << node.value.to_s
        end

        # -- header: refsDecl -------------------------------------------------

        def record_pattern(node)
          match = node.attribute("matchPattern")
          @patterns << CRefPattern.new(
            unit: node.attribute("n"),
            # Capture-group count = citation depth. Tolerates the over-escaped
            # Homeric Hymns spelling "(\\w+)" — see file header.
            depth: match ? match.scan(/(?<!\\)\(/).size : 0,
            replacement: node.attribute("replacementPattern")
          )
        end

        def scheme
          @scheme ||= build_scheme
        end

        def build_scheme
          usable = @patterns.select { |pattern| pattern.depth.positive? }
          if usable.empty?
            raise ParseError, "#{@path}: no CTS cRefPattern found (missing or empty refsDecl in teiHeader)"
          end

          deepest = usable.max_by(&:depth)
          leaf = deepest.replacement.to_s.scan(/tei:([A-Za-z][\w.-]*)/).flatten.last
          unless leaf
            raise ParseError,
                  "#{@path}: cannot determine leaf element from replacementPattern #{deepest.replacement.inspect}"
          end

          Scheme.new(depth: deepest.depth, leaf_element: leaf,
                     unit_names: usable.map(&:unit).compact, deepest_unit: deepest.unit)
        end

        # -- body: div tracking and leaf capture ------------------------------

        def start_div(node)
          if node.attribute("type") == "edition"
            enter_edition(node)
          elsif @in_edition && leaf_div?(node)
            begin_capture(node, node.attribute("n"))
          else
            push_div(node, edition: false, citation: @in_edition && citation_div?(node))
          end
        end

        def enter_edition(node)
          scheme # force refsDecl validation before any body work
          actual = node.attribute("n")
          unless actual == @urn
            raise ParseError, "#{@path}: edition urn mismatch: expected #{@urn.inspect}, " \
                              "div[@type=\"edition\"]/@n is #{actual.inspect}"
          end

          @edition_seen = true
          return if node.empty_element?

          @in_edition = true
          push_div(node, edition: true, citation: false)
        end

        def push_div(node, edition:, citation:)
          return if node.empty_element?

          @div_stack << { n: node.attribute("n"), edition: edition, citation: citation }
        end

        # A div is a citation level only when its @subtype names a cRefPattern
        # unit — structural divs (Ausonius' subtype="section") fail this.
        def citation_div?(node)
          scheme.unit_names.include?(node.attribute("subtype"))
        end

        def leaf_div?(node)
          scheme.leaf_element == "div" && node.attribute("subtype") == scheme.deepest_unit
        end

        def leaf_start?(name)
          @in_edition && scheme.leaf_element != "div" && name == scheme.leaf_element
        end

        def start_leaf(node)
          begin_capture(node, node.attribute("n"))
        end

        def begin_capture(node, leaf_n)
          citation = citation_components(node, leaf_n).join(".")
          return if node.empty_element? # nothing to capture; empty unit → skipped

          @capture = Capture.new(citation: citation, depth: node.depth, buffer: +"", drop_depths: [])
        end

        def citation_components(node, leaf_n)
          components = @div_stack.select { |entry| entry[:citation] }.map { |entry| entry[:n] } << leaf_n
          if components.any? { |component| component.nil? || component.empty? }
            raise ParseError, "#{@path}: citation unit <#{local_name(node)}> is missing @n"
          end
          unless components.size == scheme.depth
            raise ParseError, "#{@path}: citation depth mismatch: refsDecl declares #{scheme.depth} " \
                              "component(s), found #{components.size} (#{components.inspect})"
          end

          components
        end

        def captured_start(node, name)
          if DROPPED_ELEMENTS.include?(name)
            @capture.drop_depths << node.depth unless node.empty_element?
          elsif BREAK_ELEMENTS.include?(name) && @capture.drop_depths.empty?
            @capture.buffer << " "
          end
          # Any other nested markup (<p>, <q>, <foreign>, ...) keeps its text:
          # the text nodes stream past and accumulate via #text_node.
        end

        def captured_end(node, name)
          if name == scheme.leaf_element && node.depth == @capture.depth
            finish_capture
          elsif DROPPED_ELEMENTS.include?(name) && @capture.drop_depths.last == node.depth
            @capture.drop_depths.pop
          end
        end

        def finish_capture
          text = @capture.buffer.gsub(/[[:space:]]+/, " ").strip
          citation = @capture.citation
          @capture = nil
          return if text.empty?

          @units << Unit.new(citation: citation, text: Normalize.nfc(text))
        end

        def local_name(node)
          node.name.split(":").last
        end
      end
      private_constant :Extraction
    end
  end
end
