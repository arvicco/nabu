# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one 84000 translation TEI file (P48-2) — the
    # bespoke `e84000-tei` family. The compose bet was refuted from the real
    # bytes: 84000's reading unit is not the <p>/<l> element but the
    # `<milestone unit="chunk"/>` SPAN — the numbered paragraph of the 84000
    # Reading Room, which may hold several <p>/<lg> blocks (toh846a's ac.1),
    # a mantra paragraph riding the chunk before it (toh539e's 1.1), or a
    # trailer — and no existing family addresses milestone spans.
    #
    # == The citation scheme (the corpus's own published grain)
    #
    #   <division-label>.<k>
    #
    # A passage is one chunk milestone's span inside its top-level DIVISION
    # (a direct child div of <front>, or of the body's div type="translation").
    # k is the 1-based chunk ordinal within the division — consumed by EVERY
    # milestone, empty or not, so numbering can never drift from upstream's.
    # Division labels mirror the Reading Room exactly (s.1 / ac.1 / i.3 / 1.5
    # / c.1 all verified against read.84000.co, 2026-07-28):
    #
    #   summary "s", acknowledgment "ac", preface "pf", introduction "i",
    #   prologue "p", homage "h", colophon "c", appendix "ap",
    #   abbreviations "ab" — and chapter/section/part divisions share one
    #   1-based counter whose NUMBER is the label ("1.1" style). An unlisted
    #   div type labels as itself (deterministic, visible in review). Nested
    #   divs (introduction sections, chapter sub-sections) do not open new
    #   divisions — the Reading Room numbers straight through them.
    #
    # → urn:nabu:e84000:toh846a:s.1, …:toh846a:1.5, …:toh3156:c.1
    #
    # <back> (notes / listBibl / glossary) is apparatus, never passages; the
    # glossary's bo/Wylie/Sanskrit entity records are the named P48 follow-up.
    #
    # == Text discipline
    #
    # Chunk text is every text node in the open span, minus dropped subtrees:
    # <head> (section headings — navigation) and <note> (inline endnotes —
    # apparatus) drop whole; <lb>/<pb> and non-chunk milestones leave a
    # space; everything else (<mantra>, <title>, <foreign>, <ref> link text)
    # is transparent reading text. Empty folio refs (<ref cRef="F.3.b"/>)
    # contribute nothing. Whitespace collapses, output is NFC (en). A chunk
    # that flattens to nothing emits no passage but keeps its ordinal.
    #
    # Both markup spellings parse identically: plain <div> and the
    # namespace-prefixed <tei:div> variant that newer exports carry.
    #
    # == Header metadata (the crosswalk feed)
    #
    # One pass also mines the teiHeader: the mainTitle set (en → the document
    # title; bo → title_bo, Bo-Ltn Wylie → title_wylie, Sa-Ltn →
    # title_sanskrit), every sourceDesc <bibl @key> Toh number (first mints
    # the document slug upstream; all ride "toh", part-suffix-stripped bases
    # ride "toh_base" — the P48-6 join key), the UT id (publicationStmt idno
    # @xml:id), translators (author role translator*), the edition string and
    # publication date, and the first biblScope.
    class E84000TeiParser
      # One emitted chunk: citation suffix, raw accumulated text, provenance.
      Unit = Data.define(:citation, :text, :annotations)
      private_constant :Unit

      # The Toh-number base: part-publications (upstream bibl keys toh1-1 …
      # toh44-45, one Toh published chapter-wise) strip their "-<part>"
      # suffix; letter suffixes (toh846a) are part of the Toh number itself
      # and stay. The canonical rule for the P48-6 crosswalk join.
      def self.toh_base(key)
        key.sub(/-\d+\z/, "")
      end

      def parse(source, urn:, language:, title: nil, canonical_path: nil, extra_metadata: {})
        path = resolve_canonical_path(source, canonical_path)
        extraction = extract(source, path: path)
        units = disambiguate_collisions(extraction.units)
        build_document(units, urn: urn, language: language,
                              title: title || extraction.title,
                              path: path, metadata: extraction.metadata.merge(extra_metadata))
      end

      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      def extract(source, path:)
        with_io(source) do |io|
          Extraction.new(reader: Nokogiri::XML::Reader(io, path), path: path).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      # Belt and braces (the house ddbdp/GRETIL rule): labels are unique by
      # construction, but a repeated same-type front div would collide its
      # label — disambiguate deterministically, never quarantine.
      def disambiguate_collisions(units)
        seen = Hash.new(0)
        units.map do |unit|
          seen[unit.citation] += 1
          count = seen[unit.citation]
          count == 1 ? unit : unit.with(citation: "#{unit.citation}:b#{count}")
        end
      end

      def build_document(units, urn:, language:, title:, path:, metadata:)
        document = Document.new(urn: urn, language: language, title: title,
                                canonical_path: path, metadata: metadata)
        units.each_with_index do |unit, sequence|
          text = Normalize.nfc(unit.text.gsub(/[[:space:]]+/, " ").strip)
          document << Passage.new(
            urn: "#{urn}:#{unit.citation}",
            language: language,
            text: text,
            annotations: unit.annotations,
            sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable passages found in <front>/<body>" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The single-pass Reader state machine: a header phase mines the
      # teiHeader, a text phase tracks front/body divisions and captures
      # chunk spans. Local names throughout — <div> and <tei:div> are the
      # same element.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        DROPPED_ELEMENTS = %w[head note].freeze
        SEPARATOR_ELEMENTS = %w[lb pb].freeze
        # The Reading Room's own division labels (class comment).
        DIVISION_LABELS = {
          "summary" => "s", "acknowledgment" => "ac", "preface" => "pf",
          "introduction" => "i", "prologue" => "p", "homage" => "h",
          "colophon" => "c", "appendix" => "ap", "abbreviations" => "ab"
        }.freeze
        NUMBERED_DIVISION_TYPES = %w[chapter section part].freeze
        HEADER_CONTAINERS = %w[titleStmt editionStmt publicationStmt sourceDesc].freeze
        TITLE_LANG_KEYS = {
          "bo" => :title_bo, "Bo-Ltn" => :title_wylie, "Sa-Ltn" => :title_sanskrit, "en" => :title_en
        }.freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS, :SEPARATOR_ELEMENTS,
                         :DIVISION_LABELS, :NUMBERED_DIVISION_TYPES, :HEADER_CONTAINERS,
                         :TITLE_LANG_KEYS

        Result = Data.define(:units, :title, :metadata)

        def initialize(reader:, path:)
          @reader = reader
          @path = path
          # header state
          @in_header = false
          @container = nil
          @capture = nil
          @titles = {}
          @authors = []
          @toh = []
          @header = { ut_id: nil, edition: nil, publication_date: nil, bibl_scope: nil,
                      translator_tib: nil }
          # text state
          @section = nil            # :front | :body | :back
          @section_depth = nil
          @container_depth = nil    # the body translation wrapper's depth, or nil
          @division = nil           # { label:, type:, chunks: }
          @division_depth = nil
          @numbered = 0             # the shared chapter/section/part counter
          @drop_depth = nil
          @chunk = nil              # { citation:, id:, division:, text: }
          @units = []
        end

        def call
          @reader.each { |node| process(node) }
          Result.new(units: @units, title: presence(flatten(@titles[:title_en])), metadata: metadata)
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when *TEXT_NODE_TYPES then text_node(node)
          end
        end

        # -- dispatch --------------------------------------------------------

        def start_element(node)
          name = local_name(node)
          return (@in_header = true) if name == "teiHeader" && !node.empty_element?
          return header_start(node, name) if @in_header
          return enter_section(node, name) if %w[front body back].include?(name) && @section.nil?
          return unless %i[front body].include?(@section)
          return if dropping?

          if DROPPED_ELEMENTS.include?(name)
            @drop_depth = node.depth unless node.empty_element?
            return
          end

          case name
          when "div" then open_div(node)
          when "milestone" then milestone(node)
          when *SEPARATOR_ELEMENTS then separator
          end
        end

        def end_element(node)
          name = local_name(node)
          return (@in_header = false) if name == "teiHeader"
          return header_end(name) if @in_header
          return unless @section

          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end

          case name
          when "front", "body", "back" then leave_section(node)
          when "div" then close_div(node)
          end
        end

        def text_node(node)
          value = node.value.to_s
          if @in_header
            @capture << value if @capture
          elsif @chunk && !dropping?
            @chunk[:text] << value
          end
        end

        # -- header ----------------------------------------------------------

        def header_start(node, name)
          return (@container = name) if HEADER_CONTAINERS.include?(name)

          case @container
          when "titleStmt" then title_stmt_start(node, name)
          when "editionStmt"
            @capture = (@header[:edition] ||= +"") if name == "edition" && @header[:edition].nil?
          when "publicationStmt" then publication_stmt_start(node, name)
          when "sourceDesc" then source_desc_start(node, name)
          end
        end

        def header_end(name)
          @capture = nil if %w[title author edition date biblScope].include?(name)
          finish_author if name == "author"
          @container = nil if HEADER_CONTAINERS.include?(name)
        end

        def title_stmt_start(node, name)
          case name
          when "title"
            return if node.empty_element? || node.attribute("type") != "mainTitle"

            key = TITLE_LANG_KEYS[node.attribute("xml:lang")]
            @capture = (@titles[key] ||= +"") if key && @titles[key].nil?
          when "author"
            return if node.empty_element?

            @current_author = { role: presence(node.attribute("role")), text: +"" }
            @capture = @current_author[:text]
          end
        end

        def finish_author
          author = @current_author
          @current_author = nil
          return unless author

          text = flatten(author[:text])
          @authors << { role: author[:role], name: text } if text
        end

        def publication_stmt_start(node, name)
          case name
          when "idno" then @header[:ut_id] ||= presence(node.attribute("xml:id"))
          when "date" then @capture = (@header[:publication_date] ||= +"") if @header[:publication_date].nil?
          end
        end

        def source_desc_start(node, name)
          case name
          when "bibl"
            key = presence(node.attribute("key"))
            @toh << key if key
          when "biblScope"
            @capture = (@header[:bibl_scope] ||= +"") if @header[:bibl_scope].nil? && !node.empty_element?
          when "author"
            # The HISTORICAL translator: sourceDesc's author role="translatorTib"
            # names the Tibetan-era translator of the source text (toh3156's
            # colophon monk), distinct from the 84000 team in titleStmt.
            return unless node.attribute("role") == "translatorTib" && !node.empty_element?

            @capture = (@header[:translator_tib] ||= +"") if @header[:translator_tib].nil?
          end
        end

        # -- text: sections and divisions ------------------------------------

        def enter_section(node, name)
          return if node.empty_element? # <front/> is the placeholder-stub shape

          @section = name.to_sym
          @section_depth = node.depth
        end

        def leave_section(_node)
          close_chunk
          @division = nil
          @division_depth = nil
          @container_depth = nil
          @section = nil
          @section_depth = nil
        end

        def open_div(node)
          return if node.empty_element?
          return unless @division.nil? # nested divs are transparent

          type = presence(node.attribute("type"))
          # The body's div type="translation" wraps the real divisions.
          if @section == :body && type == "translation" && @container_depth.nil?
            @container_depth = node.depth
            return
          end

          @division = { label: division_label(type), type: type, chunks: 0 }
          @division_depth = node.depth
        end

        def close_div(node)
          return unless @division && node.depth == @division_depth

          close_chunk
          @division = nil
          @division_depth = nil
        end

        def division_label(type)
          return (@numbered += 1).to_s if NUMBERED_DIVISION_TYPES.include?(type)

          DIVISION_LABELS.fetch(type) { type || "d" }
        end

        # -- text: chunks ----------------------------------------------------

        def milestone(node)
          return separator unless node.attribute("unit") == "chunk"

          close_chunk
          division = @division || implicit_division
          division[:chunks] += 1
          @chunk = {
            citation: "#{division[:label]}.#{division[:chunks]}",
            id: presence(node.attribute("xml:id")),
            division: division[:type],
            text: +""
          }
        end

        # A chunk milestone outside any division (not seen upstream, but a
        # crash would quarantine a real text): a deterministic per-section
        # fallback division, visible in review.
        def implicit_division
          @division = { label: @section == :front ? "fr" : "tr", type: @section.to_s, chunks: 0 }
          @division_depth = @section_depth
          @division
        end

        def close_chunk
          chunk = @chunk
          @chunk = nil
          return unless chunk
          return if chunk[:text].strip.empty? # keeps its ordinal, emits nothing

          @units << Unit.new(citation: chunk[:citation], text: chunk[:text],
                             annotations: annotations_for(chunk))
        end

        def annotations_for(chunk)
          {
            "addressing" => "84000-chunk",
            "unit" => "chunk",
            "division" => chunk[:division],
            "chunk_id" => chunk[:id]
          }.compact
        end

        def separator
          @chunk[:text] << " " if @chunk
        end

        # -- assembly --------------------------------------------------------

        def metadata
          translators = @authors.select { |a| a[:role].to_s.start_with?("translator") && a[:role] != "translatorMain" }
          main = @authors.find { |a| a[:role] == "translatorMain" }
          {
            "toh" => (@toh.empty? ? nil : @toh),
            "toh_base" => (@toh.empty? ? nil : @toh.map { |key| E84000TeiParser.toh_base(key) }.uniq),
            "ut_id" => @header[:ut_id],
            "title_bo" => flatten(@titles[:title_bo]),
            "title_wylie" => flatten(@titles[:title_wylie]),
            "title_sanskrit" => flatten(@titles[:title_sanskrit]),
            "translators" => (translators.empty? ? nil : translators.map { |a| a[:name] }),
            "translator_main" => main&.fetch(:name),
            "translator_tib" => flatten(@header[:translator_tib]),
            "edition" => flatten(@header[:edition]),
            "publication_date" => flatten(@header[:publication_date]),
            "bibl_scope" => flatten(@header[:bibl_scope])
          }.compact
        end

        # -- helpers ---------------------------------------------------------

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
      private_constant :Extraction
    end
  end
end
