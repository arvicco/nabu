# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one Corpus Córporum (mlat.uzh.ch) TEI P5 document —
    # a bespoke parser family (P80-2), SIBLING to CroalaTeiParser, not a reuse.
    # The compose-an-existing-family bet was REFUTED from the real bytes:
    #
    #   1. Patrologia Latina files wrap the ENTIRE reading text — Migne's
    #      monitum AND the work itself — in <body><note><div1> (censused on
    #      every sampled PL opusculum). The blanket drop-<note> rule shared by
    #      epidoc/croala-tei/openmgh-tei parses every such document to ZERO
    #      passages. Here a <note> is TRANSPARENT when it plays structure
    #      (opened outside any reading unit) and APPARATUS (dropped) when it
    #      interrupts one — the letter's seven inline source citations drop,
    #      the letter itself survives.
    #   2. Divisions are the numbered div1/div2 ladder (plus bare div in other
    #      corpora); croala-tei walks only <div>.
    #   3. <pb n="0637A"/> milestones are Migne COLUMN cites — the standard way
    #      PL is referenced — worth carrying as provenance, not just a space.
    #
    # Upstream warns "some of them do not validate as TEI" — this family is
    # tolerant of structure (positional addressing assumes nothing beyond
    # well-formedness) and malformed XML raises ParseError → quarantine,
    # never a crashed sync.
    #
    # == The citation scheme (positional — the croala-tei mold)
    #
    #   <div-path>.<unit-token>
    #
    # - div-path: each ancestor div/div1..div9 contributes "d<k>" (1-based
    #   sibling position; @xml:id verbatim when one exists), dot-joined.
    #   The structural-note wrapper is invisible to the path.
    # - unit-token: "l<k>" verse / "p<k>" prose (<p>/<opener>/<closer>),
    #   ordinals counted per div per kind, consumed only by non-empty units.
    #   Residual duplicates disambiguate ":b<n>" (the house belt).
    #
    # → urn:nabu:corpus-corporum:10468:d1.p2
    #
    # Annotations: addressing "structural-ordinal", the unit kind, the
    # enclosing div's @type/@n where present, the unit's own @n, and "column" —
    # the Migne column in force where the unit's text begins (its first inner
    # <pb n> when the unit opens on one, else the last column seen).
    #
    # == Text discipline (canonical means canonical)
    #
    # Capture only inside <text><body>, per reading unit. <head> and inline
    # <note> drop their subtrees; <lb>, <pb>, <milestone>, <gap> leave a
    # space; everything else is transparent reading text (<hi>, <supplied>,
    # <persName> … keep their characters — OCR quirks reproduced, never
    # "cleaned"). Whitespace collapses, output is NFC (lat is not exempt).
    #
    # == Header metadata (the 80-1 provenance/license capture)
    #
    # The same pass mines the teiHeader: titleStmt title + author (name,
    # nested floruit <date>, @ref — VIAF), editionStmt edition/editor,
    # publicationStmt publisher/pubPlace/date, seriesStmt title/idno (the PL
    # volume + the corpus's own work id), langUsage @ident, and — when a
    # header ever carries one — <availability>/<licence> verbatim (text +
    # @target). The sampled PL headers are license-SILENT; the caller maps
    # availability to a license_override (nil when silent — the source class
    # governs).
    #
    # == Streaming
    #
    # Nokogiri::XML::Reader only: PL single texts reach several MB (largest
    # authors carry 100k+ word works) and the house DOM threshold is 5 MB.
    class CorpusCorporumTeiParser
      VERSE_UNITS = %w[l].freeze
      PROSE_UNITS = %w[p opener closer].freeze
      UNIT_ELEMENTS = (VERSE_UNITS + PROSE_UNITS).freeze
      private_constant :VERSE_UNITS, :PROSE_UNITS, :UNIT_ELEMENTS

      # One emitted unit: citation suffix, raw accumulated text, annotations.
      Unit = Data.define(:citation, :text, :annotations)
      private_constant :Unit

      # +license_mapper+: an optional callable mapping the header's verbatim
      # availability text (or nil) to a license_override class or nil — the
      # adapter owns the mapping policy, the parser owns the capture.
      def parse(source, urn:, language:, title: nil, canonical_path: nil, license_mapper: nil)
        path = resolve_canonical_path(source, canonical_path)
        extraction = extract(source, path: path)
        units = disambiguate_collisions(extraction.units)
        build_document(units, urn: urn, language: language,
                              title: title || extraction.title,
                              path: path, metadata: extraction.metadata,
                              license_override: license_mapper&.call(extraction.metadata["availability"]))
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

      # The house collision tolerance (ddbdp/GRETIL/croala precedent).
      def disambiguate_collisions(units)
        seen = Hash.new(0)
        units.map do |unit|
          seen[unit.citation] += 1
          count = seen[unit.citation]
          count == 1 ? unit : unit.with(citation: "#{unit.citation}:b#{count}")
        end
      end

      def build_document(units, urn:, language:, title:, path:, metadata:, license_override:)
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
        raise ParseError, "#{path}: no citable passages found in <text><body>" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The single-pass Reader state machine: a header phase mines provenance,
      # a body phase tracks the div stack and captures unit text.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        DIV_ELEMENTS = %w[div div1 div2 div3 div4 div5 div6 div7 div8 div9].freeze
        SEPARATOR_ELEMENTS = %w[lb pb milestone gap].freeze
        # <head> always drops; <note> drops ONLY inside an open unit (the
        # structural-wrapper rule — the class note).
        DROPPED_ELEMENTS = %w[head].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DIV_ELEMENTS,
                         :SEPARATOR_ELEMENTS, :DROPPED_ELEMENTS

        Result = Data.define(:units, :title, :metadata)

        def initialize(reader:, path:)
          @reader = reader
          @path = path
          @seen_body = false
          @in_body = false
          @drop_depth = nil
          @column = nil
          @div_frames = [{ component: nil, child_divs: 0, verse: 0, prose: 0, type: nil, n: nil }]
          @unit = nil
          @units = []
          @header = {}
          @capture = nil
          @contexts = []
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no <text><body> found" unless @seen_body

          Result.new(units: @units, title: presence(@header[:title]), metadata: metadata)
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when *TEXT_NODE_TYPES then text_node(node)
          end
        end

        # -- dispatch ---------------------------------------------------------

        def start_element(node)
          name = local_name(node)
          return enter_body(node) if name == "body" && !@in_body
          return header_start(node, name) unless @seen_body
          return unless @in_body
          return if dropping?

          if DROPPED_ELEMENTS.include?(name) || (name == "note" && @unit)
            @drop_depth = node.depth unless node.empty_element?
            return
          end

          case name
          when *DIV_ELEMENTS then open_div(node)
          when *UNIT_ELEMENTS then open_unit(node, name)
          when *SEPARATOR_ELEMENTS then separator(node, name)
          end
        end

        def end_element(node)
          name = local_name(node)
          return header_end(name) unless @seen_body
          return unless @in_body

          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end

          case name
          when "body" then @in_body = false
          when *DIV_ELEMENTS then close_div
          when *UNIT_ELEMENTS then close_unit(node, name)
          end
        end

        def text_node(node)
          value = node.value.to_s
          if !@seen_body
            @capture << value if @capture
          elsif @in_body && !dropping? && @unit
            @unit[:text] << value
          end
        end

        # -- header (the 80-1 provenance capture) -----------------------------
        #
        # Context-flagged single-pass capture: the enclosing *Stmt decides
        # what a <title>/<date>/<idno> means. Self-closing elements never
        # open a capture (the openmgh P56 lesson — no end event would close
        # it and the buffer would drain the rest of the header).

        CONTEXT_ELEMENTS = %w[titleStmt editionStmt publicationStmt seriesStmt
                              author availability langUsage].freeze
        private_constant :CONTEXT_ELEMENTS

        def header_start(node, name)
          if CONTEXT_ELEMENTS.include?(name) && !node.empty_element?
            @contexts.push(name)
            @header[:author_ref] ||= presence(node.attribute("ref")) if name == "author"
            open_capture(:author) if name == "author"
            open_capture(:availability) if name == "availability"
            return
          end
          header_field(node, name)
        end

        def header_field(node, name)
          case name
          when "title" then open_capture(title_key) unless node.empty_element?
          when "date" then open_capture(date_key) if date_key && !node.empty_element?
          when "idno" then open_capture(:series_idno) if context?("seriesStmt") && !node.empty_element?
          when "edition" then open_capture(:edition) if context?("editionStmt") && !node.empty_element?
          when "editor" then open_capture(:editor) if context?("editionStmt") && !node.empty_element?
          when "publisher" then open_capture(:publisher) if context?("publicationStmt") && !node.empty_element?
          when "pubPlace" then open_capture(:pub_place) if context?("publicationStmt") && !node.empty_element?
          when "language" then @header[:language_ident] ||= presence(node.attribute("ident")) if context?("langUsage")
          when "licence"
            @header[:license_url] ||= presence(node.attribute("target"))
            open_capture(:availability) unless node.empty_element?
          end
        end

        # Only a capture-opening element's end closes the capture — inner
        # markup (<hi>, <emph>) stays transparent inside a captured field.
        CAPTURE_CLOSERS = %w[title date idno edition editor publisher pubPlace
                             author availability licence].freeze
        private_constant :CAPTURE_CLOSERS

        def header_end(name)
          @capture = nil if CAPTURE_CLOSERS.include?(name)
          @contexts.pop if CONTEXT_ELEMENTS.include?(name) && @contexts.last == name
        end

        def title_key
          context?("seriesStmt") ? :series : :title
        end

        def date_key
          return :author_date if context?("author")
          return :pub_date if context?("publicationStmt")

          nil
        end

        def context?(name) = @contexts.include?(name)

        # First value wins per field; an already-filled buffer never reopens.
        def open_capture(key)
          return if @header.key?(key)

          @capture = (@header[key] = +"")
        end

        def metadata
          {
            "author" => flatten(@header[:author]),
            "author_date" => flatten(@header[:author_date]),
            "author_ref" => @header[:author_ref],
            "edition" => flatten(@header[:edition]),
            "editor" => flatten(@header[:editor]),
            "publisher" => flatten(@header[:publisher]),
            "pub_place" => flatten(@header[:pub_place]),
            "pub_date" => flatten(@header[:pub_date]),
            "series" => flatten(@header[:series]),
            "series_idno" => flatten(@header[:series_idno]),
            "language_ident" => @header[:language_ident],
            "availability" => flatten(@header[:availability]),
            "license_url" => @header[:license_url]
          }.compact
        end

        # -- body: div context ------------------------------------------------

        def enter_body(node)
          @seen_body = true
          @capture = nil
          @in_body = !node.empty_element?
        end

        def open_div(node)
          parent = @div_frames.last
          parent[:child_divs] += 1
          component = presence(node.attribute("xml:id")) || "d#{parent[:child_divs]}"
          frame = { component: component, child_divs: 0, verse: 0, prose: 0,
                    type: presence(node.attribute("type")), n: presence(node.attribute("n")) }
          @div_frames << frame unless node.empty_element?
        end

        def close_div
          @div_frames.pop if @div_frames.size > 1
        end

        def div_path
          @div_frames.filter_map { |frame| frame[:component] }.join(".")
        end

        # -- body: reading units ----------------------------------------------

        def open_unit(node, name)
          return if @unit || node.empty_element? # nested unit-openers stay transparent

          @unit = { tag: name, depth: node.depth, n: presence(node.attribute("n")),
                    text: +"", column: @column }
        end

        def close_unit(node, name)
          return unless @unit && @unit[:tag] == name && @unit[:depth] == node.depth

          unit = @unit
          @unit = nil
          return if unit[:text].strip.empty? # empty unit consumes no ordinal

          frame = @div_frames.last
          token = VERSE_UNITS.include?(unit[:tag]) ? "l#{frame[:verse] += 1}" : "p#{frame[:prose] += 1}"
          path = div_path
          citation = path.empty? ? token : "#{path}.#{token}"
          @units << Unit.new(citation: citation, text: unit[:text],
                             annotations: annotations_for(unit, frame))
        end

        def annotations_for(unit, frame)
          {
            "addressing" => "structural-ordinal",
            "unit" => unit[:tag],
            "div_type" => frame[:type],
            "div_n" => frame[:n],
            "n" => unit[:n],
            "column" => unit[:column]
          }.compact
        end

        # A separator leaves a space in the open unit; <pb n> additionally
        # tracks the Migne column — a unit whose text starts ON its first
        # inner pb is cited at that column (the letter opening "<p><pb
        # n='0637A'/>Fraternae…"), otherwise at the column it opened in.
        def separator(node, name)
          if name == "pb" && (column = presence(node.attribute("n")))
            @unit[:column] = column if @unit && @unit[:text].strip.empty?
            @column = column
          end
          @unit[:text] << " " if @unit
        end

        # -- helpers ----------------------------------------------------------

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
