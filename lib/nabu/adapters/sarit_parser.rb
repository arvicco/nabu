# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one SARIT (Search and Retrieval of Indic Texts)
    # scholarly TEI edition — a bespoke parser family (P26-2), SIBLING to
    # GretilParser, not a reuse of it. GRETIL's mass conversion buries its
    # addresses in the running text ("// Abbr_N //" markers); SARIT's
    # hand-encoded editions address through TEI apparatus — @xml:id / @n on
    # the citable elements, nested div paths, base-text <quote> blocks — so
    # this family mines citations from attributes and structure, never from
    # text regexes. Same call shape as the other families:
    # #parse(source, urn:, language:, title:, canonical_path:).
    #
    # == Unit grain (the 2026-07-18 whole-corpus census)
    #
    # A passage is a VERSE GROUP (<lg>, its <l> padas joined — the GRETIL
    # rung-(d) grain), a standalone <l>, or a PROSE PARAGRAPH (<p> outside
    # lg). <quote> is transparent when inline inside a unit (reading text);
    # a BLOCK <quote> (between units) passes its citation to the paragraphs
    # it wraps — that is how nyāyabhāṣya-style commentary carries its
    # base-text sūtras (<quote type="base-text" n="NyāSū__1.1.2">).
    #
    # == The citation ladder (per unit, first rung that answers)
    #
    #   1. @n on the unit, verbatim                     → addressing "attribute"
    #   2. @xml:id on the unit, prefix-stripped         → addressing "xml-id"
    #      ("verse_1.1" → 1.1, "adi-1-1-1" → 1-1-1, "Ah.1.1.001a" → 1.1.001a;
    #      see .strip_citation_id)
    #   3. the enclosing block <quote>'s @n/@xml:id     → addressing "quote"
    #   4. div-scoped ordinal: <div path>.v<k> / .p<k>  → addressing "ordinal"
    #      — flagged non-canonical (the GRETIL prose-ordinal precedent). The
    #      div path components are @n, else the stripped @xml:id; a component
    #      that RESTATES the whole path so far ("nyāyabhāṣya__1.1.1" nested
    #      under __1.1 under __1) replaces rather than re-appends it.
    #
    # An lg whose id rides on its <l> children instead of itself (the
    # aṣṭāvakragītā quirk: <lg><l xml:id="verse_1.1">…) emits ONE unit under
    # that citation when exactly one line is addressed, and one unit PER
    # addressed line (unaddressed lines joining the preceding unit) when
    # several are — the aṣṭāṅgahṛdaya half-verse shape. Any remaining
    # duplicate citation disambiguates positionally (":b2", ":b3" — the
    # house ddbdp/GRETIL precedent), never quarantines the document.
    #
    # == The license gate (per file, the GRETIL-upgrade guarantee)
    #
    # Every SARIT header carries its own grant in <availability> (censused
    # 2026-07-18 across all 83 texts: CC BY-SA 4.0 ×56, CC BY-SA 3.0 ×26,
    # MIT ×1 — ZERO NC). The parser verifies that per file — a <ref>/<licence>
    # target URL or the prose wording — and carries the resolved label in
    # Document#metadata["license"]. A grant outside BY-SA/MIT, or none at
    # all, is a ParseError: the document quarantines loudly rather than
    # riding the source-level "attribution" class on faith.
    #
    # == Text discipline
    #
    # Capture only inside <text><body> units. <note> subtrees (variant
    # apparatus) and <head> (title apparatus) are dropped; <lb break="no"/>
    # continues a word split across a print line (NO space); plain <lb>,
    # <pb>, <milestone> contribute a single space; everything else keeps its
    # text (<seg> padas, <hi>, inline <quote>). Whitespace runs collapse,
    # ends strip, NFC at the boundary.
    #
    # For a Devanagari edition (script subtag -Deva; 41 of 83 files) the
    # pristine text keeps its native script and text_normalized is minted
    # from the Deva→IAST TRANSCODE (Nabu::Deva) through the ordinary san
    # fold — the ccmh-txt documented-derivation precedent — so one IAST
    # query lands on both scripts and on MW/GRETIL alike.
    #
    # == Streaming
    #
    # The only Nokogiri entry point is Nokogiri::XML::Reader — the corpus
    # ships nine >5 MB files including the 38.6 MB Mahābhārata, exactly what
    # the house >5 MB rule exists for. One pass per document.
    class SaritParser
      # SARIT tags languages with ISO 639-1 / bare names; Nabu uses ISO 639-3
      # (conventions §4). Script subtags survive (sa-Deva → san-Deva).
      LANGUAGE_MAP = { "sa" => "san", "braj" => "bra", "avadhi" => "awa" }.freeze

      # One leading "<letters>" + separator ("__", "_", ".", "-") of a
      # citation id. Stripped repeatedly until the remainder leads with a
      # digit ("svargārohaṇaparva__adhyāya_001" → "adhyāya_001" → "001");
      # an id that never reaches a numeric tail stays verbatim.
      ID_PREFIX = /\A\p{L}[\p{L}\d]*(?:__|[_.-])/

      # Recognized grants (the license gate): resolved label by URL fragment
      # or by prose wording. Everything else refuses the document.
      LICENSE_TARGETS = {
        %r{creativecommons\.org/licenses/by-sa/4\.0} => "CC BY-SA 4.0",
        %r{creativecommons\.org/licenses/by-sa/3\.0} => "CC BY-SA 3.0",
        %r{opensource\.org/licenses/MIT} => "MIT"
      }.freeze
      LICENSE_PROSE = {
        /Creative Commons Attribution[- ]Share ?Alike 4\.0/i => "CC BY-SA 4.0",
        /Creative Commons Attribution[- ]Share ?Alike 3\.0/i => "CC BY-SA 3.0",
        /\bMIT Licen[cs]e\b/ => "MIT"
      }.freeze

      # Strip the leading letter-token prefix(es) from a citation id, keeping
      # the numeric path ("verse_1.1" → "1.1", "nyāyabhāṣya__1.1.1" → "1.1.1",
      # "adi-1-1-1" → "1-1-1"). Ids without a numeric tail are kept verbatim.
      def self.strip_citation_id(id)
        result = id
        until result.match?(/\A\d/)
          match = ID_PREFIX.match(result) or break
          result = result[match[0].length..]
        end
        result.match?(/\A\d/) ? result : id
      end

      # Map an upstream xml:lang tag to Nabu's ISO 639-3 form. nil-safe.
      def self.normalize_language(tag)
        return nil if tag.nil? || tag.empty?

        primary, rest = tag.split("-", 2)
        mapped = LANGUAGE_MAP.fetch(primary, primary)
        rest ? "#{mapped}-#{rest}" : mapped
      end

      # One emitted unit: citation suffix, raw accumulated text, and the
      # ladder rung that addressed it.
      Unit = Data.define(:citation, :text, :addressing)
      private_constant :Unit

      def parse(source, urn:, language:, title: nil, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        extraction = extract(source, path: path, language: language)
        units = disambiguate_collisions(extraction.units)
        build_document(units, urn: urn, language: language, title: title, path: path,
                              license: extraction.license)
      end

      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      def extract(source, path:, language:)
        with_io(source) do |io|
          Extraction.new(reader: Nokogiri::XML::Reader(io, path), path: path, language: language).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      # The house collision tolerance (ddbdp/GRETIL precedent): duplicates
      # disambiguate deterministically in document order, never quarantine.
      def disambiguate_collisions(units)
        seen = Hash.new(0)
        units.map do |unit|
          seen[unit.citation] += 1
          count = seen[unit.citation]
          count == 1 ? unit : unit.with(citation: "#{unit.citation}:b#{count}")
        end
      end

      def build_document(units, urn:, language:, title:, path:, license:)
        deva = language.to_s.split("-").include?("Deva")
        document = Document.new(urn: urn, language: language, title: title, canonical_path: path,
                                metadata: { "license" => license })
        units.each_with_index do |unit, sequence|
          text = Normalize.nfc(unit.text.gsub(/[[:space:]]+/, " ").strip)
          document << Passage.new(
            urn: "#{urn}:#{unit.citation}",
            language: language,
            text: text,
            text_normalized: deva ? Normalize.search_form(Deva.to_iast(text), language: language) : nil,
            annotations: { "addressing" => unit.addressing },
            sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable passages found in <text><body>" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The single-pass Reader state machine. Header phase reads the
      # availability grant; body phase tracks div/quote context and captures
      # text inside lg/l/p units.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        DROPPED_ELEMENTS = %w[note head].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS

        Result = Data.define(:units, :license)

        def initialize(reader:, path:, language:)
          @reader = reader
          @path = path
          @language = language
          @in_availability = false
          @availability_text = +""
          @license_targets = []
          @text_lang = nil
          @body_lang = nil
          @seen_body = false
          @in_body = false
          @drop_depth = nil
          @div_frames = [{ component: nil, verse: 0, prose: 0 }] # root frame
          @quote_citations = []
          @group = nil      # open verse group (lg, or a standalone l)
          @lg_depth = 0
          @para = nil       # open prose unit
          @units = []
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no <text><body> found" unless @seen_body

          Result.new(units: @units, license: @license)
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
          return header_element(node, name) unless @seen_body || name == "body"
          return enter_body(node) if name == "body" && !@in_body
          return unless @in_body
          return if dropping?

          if DROPPED_ELEMENTS.include?(name)
            @drop_depth = node.depth unless node.empty_element?
            return
          end

          case name
          when "div" then open_div(node)
          when "lg" then open_group(node)
          when "l" then open_line(node)
          when "p" then open_paragraph(node)
          when "quote" then open_quote(node)
          when "lb" then line_break(node)
          when "pb", "milestone" then separator
          end
        end

        def end_element(node)
          name = local_name(node)
          @in_availability = false if name == "availability"
          return unless @in_body

          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end

          case name
          when "body" then @in_body = false
          when "div" then close_div
          when "lg" then close_group
          when "l" then close_line
          when "p" then close_paragraph
          when "quote" then close_quote
          end
        end

        def text_node(node)
          value = node.value.to_s
          @availability_text << value if @in_availability
          return unless @in_body && !dropping?

          if @group
            line = @group[:current] ||
                   (value.strip.empty? ? nil : open_implicit_line)
            line[:text] << value if line
          elsif @para
            @para[:text] << value
          end
        end

        # -- header: availability + language ---------------------------------

        def header_element(node, name)
          case name
          when "availability" then @in_availability = true unless node.empty_element?
          when "ref", "licence"
            target = node.attribute("target")
            @license_targets << target if @in_availability && target
          when "text" then @text_lang ||= node.attribute("xml:lang")
          end
        end

        def enter_body(node)
          @body_lang ||= node.attribute("xml:lang")
          check_language!
          @license = resolve_license!
          @seen_body = true
          @in_body = !node.empty_element?
        end

        def check_language!
          derived = SaritParser.normalize_language(@text_lang || @body_lang)
          return if derived.nil? || derived == @language

          raise ParseError, "#{@path}: language mismatch: caller says #{@language.inspect}, " \
                            "the edition declares #{(@text_lang || @body_lang).inspect} (→ #{derived.inspect})"
        end

        # The per-file license gate: a target URL or the prose wording must
        # resolve to a recognized grant, or the document refuses to load.
        def resolve_license!
          @license_targets.each do |target|
            LICENSE_TARGETS.each { |pattern, label| return label if pattern.match?(target) }
          end
          LICENSE_PROSE.each { |pattern, label| return label if pattern.match?(@availability_text) }

          unrecognized = @license_targets.grep(/creativecommons\.org|opensource\.org/).first
          detail = unrecognized ? "unrecognized grant target #{unrecognized.inspect}" : "no grant found"
          raise ParseError, "#{@path}: license gate: #{detail} in <availability> — " \
                            "expected CC BY-SA 3.0/4.0 or MIT (the 2026-07-18 corpus census)"
        end

        # -- body: div context ------------------------------------------------

        def open_div(node)
          return if node.empty_element?

          id = node.attribute("xml:id")
          component = node.attribute("n") || (id && SaritParser.strip_citation_id(id))
          @div_frames << { component: component, verse: 0, prose: 0 }
        end

        def close_div
          @div_frames.pop if @div_frames.size > 1
        end

        # The dotted div path. A component that restates the accumulated path
        # ("1.1.1" under "1.1" under "1") replaces it instead of re-appending.
        def div_path
          @div_frames.filter_map { |frame| frame[:component] }.inject("") do |path, component|
            if path.empty? || component.start_with?("#{path}.")
              component
            else
              "#{path}.#{component}"
            end
          end
        end

        # -- body: verse groups (lg / standalone l) ---------------------------

        def open_group(node)
          if @group
            @lg_depth += 1 # nested lg: transparent, lines keep accumulating
            return
          end
          @group = { n: node.attribute("n"), id: node.attribute("xml:id"),
                     lines: [], current: nil, solo: false }
          finalize_group if node.empty_element?
        end

        def close_group
          if @lg_depth.positive?
            @lg_depth -= 1
            return
          end
          finalize_group
        end

        def open_line(node)
          return open_solo_line(node) unless @group

          @group[:current] = { n: node.attribute("n"), id: node.attribute("xml:id"), text: +"" }
          @group[:lines] << @group[:current]
          @group[:current] = nil if node.empty_element?
        end

        def close_line
          return unless @group

          if @group[:solo]
            finalize_group
          else
            @group[:current] = nil
          end
        end

        # A standalone <l> outside any <lg> (bhelasamhitā, rasārṇava) is a
        # one-line group of its own.
        def open_solo_line(node)
          @group = { n: node.attribute("n"), id: node.attribute("xml:id"),
                     lines: [], current: nil, solo: true }
          @group[:current] = { n: nil, id: nil, text: +"" }
          @group[:lines] << @group[:current]
          finalize_group if node.empty_element?
        end

        def open_implicit_line
          record = { n: nil, id: nil, text: +"" }
          @group[:lines] << record
          @group[:current] = record
          record
        end

        def finalize_group
          group = @group
          @group = nil
          @lg_depth = 0
          records = group[:lines].reject { |line| line[:text].strip.empty? }
          return if records.empty?

          if group[:n] || group[:id]
            emit(citation_for(number: group[:n], id: group[:id]), joined(records))
          else
            emit_by_lines(records)
          end
        end

        def emit_by_lines(records)
          addressed = records.select { |line| line[:n] || line[:id] }
          case addressed.size
          when 0 then emit_ordinal(:verse, joined(records))
          when 1 then emit(citation_for(number: addressed.first[:n], id: addressed.first[:id]), joined(records))
          else segment_by_addressed_lines(records)
          end
        end

        # Several addressed lines in one group (the aṣṭāṅgahṛdaya half-verse
        # shape): each starts a unit; unaddressed lines join the unit in
        # progress (leading ones join the first).
        def segment_by_addressed_lines(records)
          pending = []
          open = nil
          records.each do |line|
            if line[:n] || line[:id]
              emit(open[:citation], open[:texts].join(" ")) if open
              open = { citation: citation_for(number: line[:n], id: line[:id]), texts: pending + [line[:text]] }
              pending = []
            elsif open
              open[:texts] << line[:text]
            else
              pending << line[:text]
            end
          end
          emit(open[:citation], open[:texts].join(" ")) if open
        end

        def joined(records)
          records.map { |line| line[:text] }.join(" ")
        end

        # -- body: prose paragraphs -------------------------------------------

        def open_paragraph(node)
          return if @group || @para # a stray nested p keeps feeding the open unit

          @para = { n: node.attribute("n"), id: node.attribute("xml:id"),
                    quote: @quote_citations.last, text: +"" }
          close_paragraph if node.empty_element?
        end

        def close_paragraph
          para = @para
          @para = nil
          return if para.nil? || para[:text].strip.empty?

          if para[:n] || para[:id]
            emit(citation_for(number: para[:n], id: para[:id]), para[:text])
          elsif para[:quote]
            emit([SaritParser.strip_citation_id(para[:quote]), "quote"], para[:text])
          else
            emit_ordinal(:prose, para[:text])
          end
        end

        # -- body: quotes ------------------------------------------------------
        #
        # Inline (inside an open unit): transparent reading text. Block
        # (between units): its @n/@xml:id becomes the citation of the
        # paragraphs it wraps — the base-text sūtra convention.

        def open_quote(node)
          return if @group || @para || node.empty_element?

          @quote_citations << (node.attribute("n") || node.attribute("xml:id"))
        end

        def close_quote
          @quote_citations.pop unless @group || @para
        end

        # -- emission ----------------------------------------------------------

        def citation_for(number:, id:)
          return [number, "attribute"] if number

          [SaritParser.strip_citation_id(id), "xml-id"]
        end

        def emit(citation_and_addressing, text)
          citation, addressing = citation_and_addressing
          return if citation.nil? || citation.empty? || text.strip.empty?

          @units << Unit.new(citation: citation, text: text, addressing: addressing)
        end

        # Ordinal units count per innermost div, prose and verse separately;
        # only a non-empty unit consumes an ordinal (the GRETIL rule).
        def emit_ordinal(kind, text)
          return if text.strip.empty?

          frame = @div_frames.last
          token = kind == :verse ? "v#{frame[:verse] += 1}" : "p#{frame[:prose] += 1}"
          path = div_path
          citation = path.empty? ? token : "#{path}.#{token}"
          @units << Unit.new(citation: citation, text: text, addressing: "ordinal")
        end

        # -- breaks ------------------------------------------------------------

        def line_break(node)
          separator unless node.attribute("break") == "no"
        end

        def separator
          target = @group ? @group[:current] : @para
          target[:text] << " " if target
        end

        def dropping?
          !@drop_depth.nil?
        end

        def local_name(node)
          node.name.split(":").last
        end
      end
      private_constant :Extraction
    end
  end
end
