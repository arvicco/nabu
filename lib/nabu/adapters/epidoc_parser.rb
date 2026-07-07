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
    # == P4 fallback (P9-2) — legacy pre-P5 TEI
    #
    # A third acceptance strategy for the pre-P5 Perseus vintage (167
    # perseus-latin files at census): documents with NO citation root div and
    # NO CTS cRefPattern — either true TEI P4 (<TEI.2> DOCTYPE, unnamespaced,
    # numbered <div1>/<div2> containers, undefined ISO entities) or P5-
    # namespace conversions that kept the legacy <refState>-only refsDecl
    # (body = <div type="book"> containers + <milestone unit="chapter|
    # section" n=".."/> streams). It engages when — and ONLY when — the
    # subtype pass raised its "no div[@type=...] found" error (an error the
    # structural retry never handles, so the two strategies trigger on
    # disjoint shapes) AND the header declared no usable cRefPattern: a P5
    # document without an edition div (the first1k commentary class) makes
    # the fallback DECLINE and the original error re-raise byte-identical.
    #
    # The legacy declarations are NOT trusted for citation: the census shows
    # them contradicting the body wholesale (phi0692 declares
    # book.chapter.section over lb-numbered verse; stoa0045 declares the same
    # over letter divs), so citation is minted from the body itself, on a
    # three-rung ladder where each rung runs only if the previous minted
    # nothing:
    #
    # 1. Containers + milestones. Every body div/div1..div9 is a citation
    #    container; its component is @n, else @type + 1-based ordinal among
    #    same-type siblings ("poem2"), else "d" + ordinal. Milestones with
    #    @unit and non-empty @n segment WITHIN the innermost container: units
    #    form a hierarchy in first-appearance order (Livy: chapter before
    #    section), a milestone clears all deeper components, and any div
    #    boundary clears them all. Citation = div path + set milestone
    #    components, dot-joined; text accumulating while at least one
    #    component is set flushes at every boundary; consecutive flushes with
    #    the SAME citation merge (a boundary that does not change the
    #    citation did not create a new unit) — NON-adjacent repeats are
    #    honest duplicate-urn quarantines (8 files at census, e.g. Cato's
    #    praefatio div labeled chapter n="1" colliding with the real one).
    # 2. Numbered <lb n/> marks as per-line citation (Appendix Vergiliana
    #    verse: no divs, no milestones, lines as lb marks).
    # 3. Bare <p> ordinals, 1-based over ALL p elements in body order
    #    (Boethius tractates: no apparatus at all; empty p's keep their
    #    ordinal and mint nothing).
    #
    # All rungs share the P5 text discipline (notes dropped, breaks space,
    # whitespace collapsed, NFC) plus two P4-specific rules: <head> subtrees
    # are dropped (title apparatus, and the P5 pass excludes them
    # structurally anyway), and undefined entity references — the P4 DTD is
    # never fetched — resolve through a fixed table of the ISO Latin-1/pub
    # names observed at census (&aelig; &mdash; ...; unknown names become a
    # space so words never fuse). No urn cross-check is possible: P4 bodies
    # carry no edition urn, the caller-supplied urn is authoritative.
    #
    # FROZEN-URN SAFETY: same argument as the structural retry — the fallback
    # runs strictly after the unchanged first pass raised, so every document
    # that parses cleanly today never reaches it; quarantined documents never
    # entered the catalog. (Verified read-only against the live catalog; see
    # the P9-2 worklog entry.)
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

      # The subtype pass's no-citation-root error — the P4 fallback's trigger
      # (see the file header). Disjoint from RETRYABLE_ERRORS: the structural
      # retry and the P4 fallback can never race for the same document.
      NO_DIVISION_ERROR = /: no div\[@type=.*\] found\z/
      private_constant :NO_DIVISION_ERROR

      # Raised internally by P4Extraction when the header declares a usable
      # CTS cRefPattern: the document is P5 territory and the original error
      # must stand byte-identical.
      class P4Declined < StandardError
      end
      private_constant :P4Declined

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
        if RETRYABLE_ERRORS.any? { |pattern| pattern.match?(e.message) } && rewind_for_retry(source)
          structural_retry(source, path: path, urn: urn, language: language, title: title,
                                   division_types: division_types, original: e)
        elsif NO_DIVISION_ERROR.match?(e.message) && rewind_for_retry(source)
          p4_retry(source, path: path, urn: urn, language: language, title: title, original: e)
        else
          raise
        end
      end

      private

      def attempt(source, path:, urn:, language:, title:, division_types:, structural:)
        units = extract_units(source, path: path, urn: urn, division_types: division_types, structural: structural)
        build_document(units, urn: urn, language: language, title: title, path: path,
                              division_types: division_types)
      end

      def structural_retry(source, path:, urn:, language:, title:, division_types:, original:)
        attempt(source, path: path, urn: urn, language: language, title: title,
                        division_types: division_types, structural: true)
      rescue ParseError => e
        raise ParseError, "#{original.message}; structural retry (refsDecl replacementPattern xpath) " \
                          "also failed: #{e.message.delete_prefix("#{path}: ")}"
      end

      # The P4 fallback ladder (see the file header): each rung re-reads the
      # document and runs only if the previous one minted nothing. A usable
      # cRefPattern in the header raises P4Declined out of the first read —
      # the original P5 error stands byte-identical.
      def p4_retry(source, path:, urn:, language:, title:, original:)
        P4Extraction::MODES.each_with_index do |mode, index|
          break if index.positive? && !rewind_for_retry(source)

          units = extract_p4_units(source, path: path, mode: mode)
          next if units.empty?

          return build_document(units, urn: urn, language: language, title: title, path: path)
        end
        raise ParseError, "#{path}: no citable passages found by any rung (numbered divs/milestones, " \
                          "lb lines, p ordinals)"
      rescue P4Declined
        raise original
      rescue ParseError => e
        raise ParseError, "#{original.message}; P4 retry (legacy numbered-div/milestone citation) " \
                          "also failed: #{e.message.delete_prefix("#{path}: ")}"
      end

      def extract_p4_units(source, path:, mode:)
        with_io(source) do |io|
          P4Extraction.new(reader: Nokogiri::XML::Reader(io, path), mode: mode).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
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

      # One rung of the P4 fallback ladder (file header, "P4 fallback"): a
      # single streaming pass minting citation units from the body's own
      # structure — numbered container divs + milestone streams (:containers),
      # numbered lb marks (:lines), or bare p ordinals (:paragraphs). Raises
      # P4Declined the moment the header shows a usable CTS cRefPattern.
      class P4Extraction
        MODES = %i[containers lines paragraphs].freeze

        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = Extraction::TEXT_NODE_TYPES
        # <note> parity with the P5 pass; <head> is title apparatus that the
        # P5 pass excludes structurally (it sits outside citation units) but a
        # P4 container div would otherwise swallow.
        DROPPED_ELEMENTS = %w[note head].freeze
        CONTAINER_DIV = /\Adiv[1-9]?\z/
        # Undefined entity references observed at census across all 167 P4
        # files — the standard ISO Latin-1/pub names their unfetchable DTD
        # would define. Unknown names resolve to a space (words never fuse).
        ENTITIES = {
          "aelig" => "æ", "AElig" => "Æ", "oelig" => "œ", "OElig" => "Œ",
          "aacute" => "á", "Aacute" => "Á", "agrave" => "à", "acirc" => "â", "auml" => "ä",
          "eacute" => "é", "egrave" => "è", "ecirc" => "ê", "euml" => "ë", "Euml" => "Ë",
          "emacr" => "ē", "iacute" => "í", "Iacute" => "Í", "igrave" => "ì", "icirc" => "î",
          "iuml" => "ï", "Iuml" => "Ï", "oacute" => "ó", "ograve" => "ò", "ocirc" => "ô",
          "ouml" => "ö", "Ouml" => "Ö", "uacute" => "ú", "ugrave" => "ù", "ucirc" => "û",
          "uuml" => "ü", "Uuml" => "Ü", "yacute" => "ý", "yuml" => "ÿ", "ntilde" => "ñ",
          "ccedil" => "ç", "racute" => "ŕ", "mdash" => "—", "ndash" => "–", "dagger" => "†",
          "sect" => "§", "deg" => "°", "pound" => "£", "prime" => "′", "cdot" => "·",
          "lsquo" => "‘", "rsquo" => "’", "ldquo" => "“", "rdquo" => "”"
        }.freeze

        def initialize(reader:, mode:)
          @reader = reader
          @mode = mode
          @body_depth = 0
          @drop_depth = 0
          @frames = [] # one per open container div: { component:, counters: }
          @counters = Hash.new(0) # ordinal fallbacks for divs directly under body
          @milestone_units = []   # hierarchy in first-appearance order
          @milestone_values = {}
          @paragraph = 0
          @in_paragraph = false
          @buffer = +""
          @segments = [] # [citation, raw text] — merged + NFC'd at the end
        end

        def call
          @reader.each { |node| process(node) }
          @segments.map { |citation, text| Unit.new(citation: citation, text: Normalize.nfc(text)) }
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when READER::TYPE_ENTITY_REFERENCE
            @buffer << ENTITIES.fetch(node.name, " ") if capturing?
          when *TEXT_NODE_TYPES
            @buffer << node.value.to_s if capturing?
          end
        end

        def capturing?
          @body_depth.positive? && @drop_depth.zero? && citable?
        end

        def citable?
          return @in_paragraph if @mode == :paragraphs

          @frames.any? || @milestone_values.any?
        end

        def start_element(node)
          name = local_name(node)
          raise P4Declined if name == "cRefPattern" && usable_cref_pattern?(node)
          return enter_body(node) if name == "body"
          return if @body_depth.zero?
          return open_drop(node) if @drop_depth.positive? || DROPPED_ELEMENTS.include?(name)

          dispatch_start(node, name)
        end

        def dispatch_start(node, name)
          if CONTAINER_DIV.match?(name) && @mode != :paragraphs
            open_container(node)
          elsif citation_milestone?(node, name)
            milestone_event(name == "lb" ? "line" : node.attribute("unit"), node.attribute("n"))
          elsif name == "p" && @mode == :paragraphs
            flush
            @paragraph += 1
            @in_paragraph = true unless node.empty_element?
          elsif Extraction::BREAK_ELEMENTS.include?(name) && capturing?
            @buffer << " "
          end
        end

        def end_element(node)
          name = local_name(node)
          if name == "body"
            flush
            @body_depth -= 1
          elsif @body_depth.zero?
            nil
          elsif @drop_depth.positive?
            @drop_depth -= 1
          elsif CONTAINER_DIV.match?(name) && @mode != :paragraphs
            close_container
          elsif name == "p" && @mode == :paragraphs
            flush
            @in_paragraph = false
          end
        end

        def enter_body(node)
          @body_depth += 1 unless node.empty_element?
        end

        def open_drop(node)
          @drop_depth += 1 unless node.empty_element?
        end

        # -- containers + milestones (rungs 1 and 2) --------------------------

        def open_container(node)
          flush
          component = component_for(node)
          clear_milestones
          @frames << { component: component, counters: Hash.new(0) } unless node.empty_element?
        end

        def close_container
          flush
          @frames.pop
          clear_milestones
        end

        # Component minting (file header): @n, else @type + ordinal among
        # same-type siblings of the parent, else "d" + ordinal.
        def component_for(node)
          n = node.attribute("n")
          return n unless n.nil? || n.empty?

          type = node.attribute("type").to_s
          counters = @frames.empty? ? @counters : @frames.last[:counters]
          counters[type] += 1
          type.empty? ? "d#{counters[type]}" : "#{type}#{counters[type]}"
        end

        # A milestone with @unit and non-empty @n is a citation event; on the
        # :lines rung, numbered <lb/> marks join as the pseudo-unit "line".
        def citation_milestone?(node, name)
          return false if @mode == :paragraphs
          return false if blank?(node.attribute("n"))

          (name == "milestone" && !blank?(node.attribute("unit"))) || (name == "lb" && @mode == :lines)
        end

        def milestone_event(unit, value)
          flush
          index = @milestone_units.index(unit) || ((@milestone_units << unit).size - 1)
          @milestone_values[unit] = value
          @milestone_units[(index + 1)..].each { |deeper| @milestone_values.delete(deeper) }
        end

        def clear_milestones
          @milestone_units.clear
          @milestone_values.clear
        end

        # -- flushing ----------------------------------------------------------

        def citation
          return @paragraph.to_s if @mode == :paragraphs

          (@frames.map { |frame| frame[:component] } +
            @milestone_units.filter_map { |unit| @milestone_values[unit] }).join(".")
        end

        def flush
          text = @buffer.gsub(/[[:space:]]+/, " ").strip
          @buffer = +""
          return if text.empty?

          label = citation
          return if label.empty?

          # A boundary that did not change the citation did not create a new
          # unit: consecutive same-citation segments merge. Non-adjacent
          # repeats survive to the duplicate-urn check — honest quarantine.
          if @segments.last&.first == label
            @segments.last[1] << " " << text
          else
            @segments << [label, text]
          end
        end

        def usable_cref_pattern?(node)
          match = node.attribute("matchPattern")
          match ? match.scan(/(?<!\\)\(/).size.positive? : false
        end

        def blank?(value)
          value.nil? || value.empty?
        end

        def local_name(node)
          node.name.split(":").last
        end
      end
      private_constant :P4Extraction
    end
  end
end
