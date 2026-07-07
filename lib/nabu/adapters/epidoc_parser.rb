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
    # == Structural retry (P6-1) — when the subtype convention fails
    #
    # A large quarantine class (the Iliad among it) declares a sound citation
    # scheme whose cRefPattern unit names do NOT match the body's div
    # subtypes: case shifts (unit "book" vs subtype "Book" — the Iliad),
    # renamed labels (unit "book" vs subtype "chapter" — Nicomachus), unit
    # names absent from the header (<cRefPattern> with no @n at all —
    # Diodorus grc6). For all of them the deepest cRefPattern's
    # replacementPattern xpath still states the real citation structure
    # explicitly: which elements carry the citation components ($1..$D) and
    # which are structural (bare steps, e.g. Ausonius' section div appears as
    # a bare tei:div step). So when — and ONLY when — the subtype pass raises
    # a citation-shape ParseError (depth mismatch, missing @n, no citable
    # passages, duplicate urn), the file is re-read matching the body against
    # that xpath with strict axis semantics: a child-axis step must match a
    # direct child of the previous match, a descendant-axis step may match at
    # any depth below it, and an element that fails a required predicate (a
    # $-bound step missing @n) is not selected — exactly what a CTS resolver
    # evaluating the declared xpath would do. Files whose declaration
    # genuinely contradicts the body fail both passes and stay quarantined,
    # with a message naming both failures.
    #
    # FROZEN-URN SAFETY: the retry runs strictly after the subtype pass has
    # raised. Every document that parsed cleanly before P6-1 succeeds in the
    # unchanged first pass and never reaches the retry, so its urns and
    # passage text are byte-identical by construction; documents that were
    # quarantined never entered the catalog, so their urns are free to
    # define. (Verified empirically against the live catalog before commit:
    # read-only re-parse of all loaded perseus/first1k documents → identical
    # urns + text; see the P6-1 worklog entry.)
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
    # - text_normalized is minted by Passage.new itself (P6-4): the
    #   per-language search form via Normalize.search_form — marks stripped,
    #   downcased, grc final-sigma / lat v-u,j-i rules; conventions.md §9.
    #   The parser passes only the pristine NFC text.
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
    #     canonical_path: "...",     # required only for IOs without #path
    #     division_types: ["edition"] # body divs accepted as the citation root
    #   ) # => Nabu::Document
    #
    # == division_types (P7-4)
    #
    # English translation files anchor their body in div[@type="translation"]
    # where original-language editions use div[@type="edition"]. Acceptance is
    # a PER-PARSE parameter, not a global widening, because composite
    # original-language files exist that embed a translation div NEXT TO their
    # edition div (3 in canonical-greekLit) — under the default ["edition"]
    # those parse byte-identically to before, the frozen-urn standard. The
    # Perseus adapter passes ["translation", "edition"] for translation refs
    # (785 of 786 perseus-eng files use "translation"; one uses "edition"; none
    # carries both, verified against the 2026-07-03 snapshot).
    class EpidocParser
      # One citable unit as extracted from the stream: citation is the dotted
      # path (e.g. "2", "1.7"), text is cleaned NFC content.
      Unit = Data.define(:citation, :text)
      private_constant :Unit

      # Citation-shape failures of the subtype pass that the structural retry
      # may honestly recover (see the file header). Everything else (malformed
      # XML, missing refsDecl, no edition div, urn mismatch) is final.
      RETRYABLE_ERRORS = [
        /citation depth mismatch/,
        /citation unit <[^>]+> is missing @n/,
        /no citable passages found/,
        /duplicate passage urn/
      ].freeze
      private_constant :RETRYABLE_ERRORS

      # The default citation-root acceptance: original-language editions.
      DIVISION_TYPES = ["edition"].freeze

      # Parse one edition file into a Nabu::Document with ordered Passages at
      # the lowest citation level. Raises Nabu::ParseError on malformed XML,
      # missing/empty CTS refsDecl, urn mismatch, or zero citable passages.
      def parse(source, urn:, language:, title: nil, canonical_path: nil, division_types: DIVISION_TYPES)
        path = resolve_canonical_path(source, canonical_path)
        attempt(source, path: path, urn: urn, language: language, title: title,
                        division_types: division_types, structural: false)
      rescue ParseError => e
        raise unless RETRYABLE_ERRORS.any? { |pattern| pattern.match?(e.message) } && rewind_for_retry(source)

        begin
          attempt(source, path: path, urn: urn, language: language, title: title,
                          division_types: division_types, structural: true)
        rescue ParseError => retry_error
          raise ParseError, "#{e.message}; structural retry (refsDecl replacementPattern xpath) " \
                            "also failed: #{retry_error.message.delete_prefix("#{path}: ")}"
        end
      end

      private

      def attempt(source, path:, urn:, language:, title:, division_types:, structural:)
        units = extract_units(source, path: path, urn: urn, division_types: division_types, structural: structural)
        build_document(units, urn: urn, language: language, title: title, path: path,
                              division_types: division_types)
      end

      # The retry re-reads the document: trivially possible for a file path,
      # possible for rewindable IOs, impossible for streams (the original
      # error stands).
      def rewind_for_retry(source)
        return true if source.is_a?(String)
        return false unless source.respond_to?(:rewind)

        begin
          source.rewind
          true
        rescue SystemCallError, IOError
          false
        end
      end

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      def extract_units(source, path:, urn:, division_types:, structural:)
        with_io(source) do |io|
          Extraction.new(reader: Nokogiri::XML::Reader(io, path), path: path, urn: urn,
                         division_types: division_types, structural: structural).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      def build_document(units, urn:, language:, title:, path:, division_types: DIVISION_TYPES)
        document = Document.new(urn: urn, language: language, title: title, canonical_path: path)
        units.each_with_index do |unit, sequence|
          document << Passage.new(
            urn: "#{urn}:#{unit.citation}",
            language: language,
            text: unit.text,
            annotations: {},
            sequence: sequence
          )
        end
        if document.empty?
          raise ParseError, "#{path}: no citable passages found in #{Extraction.divisions_label(division_types)}"
        end

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
        # One xpath step of the structural scheme: element name, axis
        # (:child for /, :desc for //), the citation component it binds
        # ($k → k, nil for structural steps), and literal attribute
        # predicates it requires (e.g. {"subtype" => "fragment"}).
        Step = Data.define(:name, :axis, :binds, :predicates)
        StructuralScheme = Data.define(:steps) do
          def leaf_name = steps.last.name
        end
        private_constant :CRefPattern, :Scheme, :Capture, :Step, :StructuralScheme

        # Structural-frame state marking a subtree that can no longer match
        # any step (a broken child-axis chain — xpath would select nothing
        # below it).
        DEAD = -1
        private_constant :DEAD

        # "div[@type=\"translation\"] or div[@type=\"edition\"]" — the error
        # vocabulary for whichever citation roots a parse accepts. With the
        # default single type this renders the exact pre-P7-4 message.
        def self.divisions_label(division_types)
          division_types.map { |type| "div[@type=\"#{type}\"]" }.join(" or ")
        end

        def initialize(reader:, path:, urn:, division_types: DIVISION_TYPES, structural: false)
          @reader = reader
          @path = path
          @urn = urn
          @division_types = division_types
          @structural = structural
          @patterns = []
          @div_stack = []
          @frames = [] # structural mode: one frame per open element inside the edition
          @in_edition = false
          @edition_seen = false
          @capture = nil
          @units = []
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no #{self.class.divisions_label(@division_types)} found" unless @edition_seen

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

          if name == "cRefPattern"
            record_pattern(node)
          elsif name == "div" && @division_types.include?(node.attribute("type"))
            enter_edition(node)
          elsif @structural
            structural_start(node, name) if @in_edition
          elsif name == "div"
            start_div(node)
          elsif leaf_start?(name)
            start_leaf(node)
          end
        end

        def end_element(node)
          name = local_name(node)
          if @capture
            captured_end(node, name)
          elsif @structural
            # END_ELEMENT only fires for non-empty elements — exactly the ones
            # structural_start pushed a frame for.
            structural_end if @in_edition
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
          deepest = deepest_pattern
          leaf = deepest.replacement.to_s.scan(/tei:([A-Za-z][\w.-]*)/).flatten.last
          unless leaf
            raise ParseError,
                  "#{@path}: cannot determine leaf element from replacementPattern #{deepest.replacement.inspect}"
          end

          Scheme.new(depth: deepest.depth, leaf_element: leaf,
                     unit_names: usable_patterns.map(&:unit).compact, deepest_unit: deepest.unit)
        end

        # -- body: div tracking and leaf capture (subtype pass) ---------------

        def start_div(node)
          if @in_edition && leaf_div?(node)
            begin_capture(node, node.attribute("n"))
          else
            push_div(node, edition: false, citation: @in_edition && citation_div?(node))
          end
        end

        def enter_edition(node)
          # Force refsDecl validation before any body work.
          @structural ? structural_scheme : scheme
          actual = node.attribute("n")
          unless actual == @urn
            raise ParseError, "#{@path}: edition urn mismatch: expected #{@urn.inspect}, " \
                              "div[@type=\"#{node.attribute('type')}\"]/@n is #{actual.inspect}"
          end

          @edition_seen = true
          return if node.empty_element?

          @in_edition = true
          if @structural
            @frames << { state: 0, component: nil, edition: true }
          else
            push_div(node, edition: true, citation: false)
          end
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
          begin_capture_at(node, citation_components(node, leaf_n))
        end

        def begin_capture_at(node, components)
          citation = components.join(".")
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

        # -- body: strict xpath matching (structural retry) -------------------
        #
        # One frame per open element inside the edition div; frame[:state] is
        # the number of xpath steps matched by the chain of ancestors (DEAD
        # when a child-axis step broke), frame[:component] the citation value
        # this element bound. Greedy: the first element that can match the
        # next step does; ambiguous re-anchoring under descendant axes is not
        # explored (unneeded by any observed refsDecl shape).

        def structural_start(node, name)
          state = @frames.last ? @frames.last[:state] : DEAD
          step = state == DEAD ? nil : structural_scheme.steps[state]
          frame = { state: DEAD, component: nil }

          if step && step_matches?(step, node, name)
            return structural_match(node, step, state, frame)
          elsif step && step.axis == :desc
            frame[:state] = state # descendants may still match this step
          end

          @frames << frame unless node.empty_element?
        end

        def structural_match(node, step, state, frame)
          return begin_capture_at(node, structural_components(node)) if state == structural_scheme.steps.size - 1

          frame[:state] = state + 1
          frame[:component] = node.attribute("n") if step.binds
          @frames << frame unless node.empty_element?
        end

        # A step matches when the element name agrees, every literal
        # predicate holds, and — for $-bound steps — @n is present (an
        # element without @n is not selected by [@n='...']; it is structural
        # noise, exactly as an xpath engine would treat it).
        def step_matches?(step, node, name)
          return false unless name == step.name
          return false if step.binds && blank?(node.attribute("n"))

          step.predicates.all? { |attribute, value| node.attribute(attribute) == value }
        end

        def structural_components(node)
          @frames.filter_map { |frame| frame[:component] } << node.attribute("n")
        end

        def structural_end
          frame = @frames.pop
          @in_edition = false if frame && frame[:edition]
        end

        def structural_scheme
          @structural_scheme ||= build_structural_scheme
        end

        # Derive the strict step list from the deepest cRefPattern's
        # replacementPattern. The prefix (/tei:TEI/tei:text/tei:body and the
        # unbound div step naming the edition) is dropped — the streaming
        # pass anchors at div[@type="edition"] regardless.
        def build_structural_scheme
          deepest = deepest_pattern
          steps = parse_xpath_steps(deepest.replacement.to_s)
          steps.shift while steps.first && %w[TEI text body].include?(steps.first.name) && steps.first.binds.nil?
          steps.shift if steps.first && steps.first.name == "div" && steps.first.binds.nil? && steps.size > 1

          binds = steps.map(&:binds).compact
          unless steps.any? && steps.last.binds && binds == (1..binds.size).to_a
            raise ParseError, "#{@path}: replacementPattern #{deepest.replacement.inspect} does not bind " \
                              "citation components $1..$n in order along its xpath"
          end
          unless binds.size == deepest.depth
            raise ParseError, "#{@path}: replacementPattern binds #{binds.size} component(s) but " \
                              "matchPattern declares #{deepest.depth}"
          end

          StructuralScheme.new(steps: steps)
        end

        def parse_xpath_steps(raw)
          inner = raw.gsub("\\'", "'")[/#xpath\((.*)\)/m, 1]
          raise ParseError, "#{@path}: cannot parse replacementPattern #{raw.inspect} as an #xpath(...)" unless inner

          matches = inner.scan(%r{(/{1,2})tei:([A-Za-z][\w.-]*)((?:\[[^\]]*\])*)})
          parsed = matches.map { |axis, name, preds| [axis, name, preds] }
          unless parsed.map { |axis, name, preds| "#{axis}tei:#{name}#{preds}" }.join == inner
            raise ParseError, "#{@path}: unsupported replacementPattern xpath #{inner.inspect}"
          end

          parsed.map do |axis, name, preds|
            binds, predicates = parse_predicates(preds, context: inner)
            Step.new(name: name, axis: axis == "//" ? :desc : :child, binds: binds, predicates: predicates)
          end
        end

        def parse_predicates(preds, context:)
          pairs = preds.scan(/\[@([\w:]+)=['"]([^'"\]]*)['"]\]/)
          unless pairs.map { |attribute, value| "[@#{attribute}='#{value}']" }.join == preds ||
                 pairs.map { |attribute, value| "[@#{attribute}=\"#{value}\"]" }.join == preds
            raise ParseError, "#{@path}: unsupported predicate #{preds.inspect} in replacementPattern " \
                              "xpath #{context.inspect}"
          end

          binds = nil
          predicates = {}
          pairs.each do |attribute, value|
            if value =~ /\A\$(\d+)\z/
              unless attribute == "n"
                raise ParseError, "#{@path}: citation component bound to @#{attribute} (not @n) in " \
                                  "replacementPattern xpath #{context.inspect}"
              end
              binds = Regexp.last_match(1).to_i
            else
              predicates[attribute] = value
            end
          end
          [binds, predicates]
        end

        def usable_patterns
          @usable_patterns ||= @patterns.select { |pattern| pattern.depth.positive? }
        end

        def deepest_pattern
          if usable_patterns.empty?
            raise ParseError, "#{@path}: no CTS cRefPattern found (missing or empty refsDecl in teiHeader)"
          end

          usable_patterns.max_by(&:depth)
        end

        def blank?(value)
          value.nil? || value.empty?
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
          if name == leaf_name && node.depth == @capture.depth
            finish_capture
          elsif DROPPED_ELEMENTS.include?(name) && @capture.drop_depths.last == node.depth
            @capture.drop_depths.pop
          end
        end

        def leaf_name
          @structural ? structural_scheme.leaf_name : scheme.leaf_element
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
