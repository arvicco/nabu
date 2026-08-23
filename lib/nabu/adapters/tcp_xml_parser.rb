# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one TCP-schema XML document (P82-2) — the
    # eebo2prf.xml.dtd shape shared by the Text Creation Partnership lineage
    # (EEBO-TCP / ECCO-TCP / Evans-TCP) and by the Corpus of Middle English's
    # May-2026 normalization, which is this family's first rider. LOAD-BEARING
    # BY DESIGN: a future EEBO-TCP wave (~60k texts) is meant to ride this
    # exact machinery, so the CME adapter composes the family and owns none
    # of it.
    #
    # The schema is NOT lowercase TEI P5 (the fixture-first verdict, censused
    # on all 297 CME files 2026-08-23): UPPERCASE names under an <ETS> root —
    # <HEADER> (FILEDESC/ENCODINGDESC/PROFILEDESC) then <EEBO> holding the
    # <IDG> identity group and the <TEXT> tree(s). The features that
    # "sometimes surprise even" the TCP's own manager, handled from real
    # bytes:
    #
    #   1. <TEXT> nests inside a <DIV1> of another <TEXT> with NO <GROUP>
    #      (CME00121) — so the citation stack is driven by pure NESTING,
    #      never by the DIV1..DIV7 ladder rank, and TEXT/GROUP/FRONT/BODY/
    #      BACK are transparent structural frames.
    #   2. <IDG ID="CME00000"> is a placeholder SHARED by many files (empty
    #      STC/BIBNO/VID) — captured verbatim as metadata, never an identity;
    #      the caller's urn (in CME: the filename) is the identity.
    #   3. <CHOICE><SIC>/<CORR> order varies and SIC can hold editorial prose
    #      rather than text ("[scratched out in MS.]") — the reading takes
    #      CORR and drops SIC-inside-CHOICE; a standalone <SIC> (no CHOICE)
    #      stays transparent.
    #   4. <GAP DESC="…" DISP="•"/> carries upstream's display glyph — the
    #      reading takes a plain space, like every separator.
    #   5. <AUTHOR/> appears EMPTY before the real <AUTHOR TYPE="add"> — an
    #      empty element never consumes a first-wins header capture.
    #
    # == The citation scheme (positional — the corpus-corporum-tei mold)
    #
    #   <div-path>.<unit-token>     → urn:nabu:cme:tenwives:d2.l7
    #
    # - div-path: each DIV1..DIV7 frame contributes "d<k>" (1-based count of
    #   div-children its PARENT frame has opened; the root frame is the
    #   file), dot-joined. Nesting alone builds the stack (quirk 1).
    # - unit-token: "l<k>" verse <L> / "h<k>" rubric <HEAD> / "p<k>" prose
    #   blocks (P, Q, ITEM, CELL, OPENER, CLOSER, …), ordinals counted per
    #   kind per frame, consumed only by non-empty units. Residual
    #   duplicates disambiguate ":b<n>" (the house belt).
    #
    # == Text discipline (canonical means canonical)
    #
    # <HEAD> is a reading unit here — CME heads are transcribed medieval
    # rubrics, NOT the editorial captions the croala/epidoc families drop.
    # <NOTE>/<TAILNOTE> (marg/foot glosses and end-notes) and <FIGDESC> drop
    # their subtrees; <SPEAKER> drops from text but labels its <SP>'s
    # passages via the "speaker" annotation. <PB>, <MILESTONE>, <LB>, <GAP>
    # read as one space (<PB N> additionally tracks the page cite in force —
    # the Migne-column mold). <ADD> and <DEL> both stay transparent (a
    # scribal deletion is transcription, not apparatus). Everything else
    # (<HI>, <SUP>, <SUB>, <ABOVE>, <SEG>, <ABBR>, <SUPPLIED>, <UNCLEAR>,
    # tables/lists…) is transparent reading text. Whitespace collapses,
    # output is NFC.
    #
    # == Header metadata
    #
    # One pass mines the <HEADER>: FILEDESC title/author/editor, the digital
    # PUBLICATIONSTMT (publisher/place/date + IDNO TYPE="dlps" +
    # AVAILABILITY verbatim — the per-file license statement), the BIBLFULL
    # print-source block (source_* keys; absent on direct-from-manuscript
    # transcriptions), LANGUSAGE entries verbatim ("enm=English, Middle
    # (1100-1500)"), plus IDG@ID and the first TEXT@LANG. +license_mapper+
    # and +metadata_mapper+ are the corpus-corporum seams: the parser owns
    # capture, the adapter owns judgment.
    #
    # == Streaming
    #
    # Nokogiri::XML::Reader only: the largest CME file is 20 MB (afz9170,
    # the Wycliffite bible) and the house DOM threshold is 5 MB. The corpus
    # carries no named entities beyond the XML built-ins (censused), so the
    # external DTD reference is never fetched (NONET default).
    class TcpXmlParser
      # One emitted unit: citation suffix, raw accumulated text, annotations.
      Unit = Data.define(:citation, :text, :annotations)
      private_constant :Unit

      def parse(source, urn:, language:, title: nil, canonical_path: nil,
                license_mapper: nil, metadata_mapper: nil)
        path = resolve_canonical_path(source, canonical_path)
        extraction = extract(source, path: path)
        units = disambiguate_collisions(extraction.units)
        metadata = (metadata_mapper&.call(extraction.metadata) || {}).merge(extraction.metadata)
        build_document(units, urn: urn, language: language,
                              title: title || extraction.title,
                              path: path, metadata: metadata,
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
        raise ParseError, "#{path}: no citable passages found under <TEXT>" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The single-pass Reader state machine: a header phase mines the
      # <HEADER>, an EEBO phase tracks the nesting-driven div stack and
      # captures unit text.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        DIV_ELEMENTS = %w[DIV1 DIV2 DIV3 DIV4 DIV5 DIV6 DIV7].freeze
        VERSE_UNITS = %w[L].freeze
        HEAD_UNITS = %w[HEAD].freeze
        PROSE_UNITS = %w[P AB Q ITEM CELL LABEL OPENER CLOSER SALUTE SIGNED BYLINE
                         DATELINE TRAILER EPIGRAPH ARGUMENT HEADNOTE STAGE BIBL DATE].freeze
        UNIT_ELEMENTS = (VERSE_UNITS + HEAD_UNITS + PROSE_UNITS).freeze
        SEPARATOR_ELEMENTS = %w[PB MILESTONE LB GAP].freeze
        DROPPED_ELEMENTS = %w[NOTE TAILNOTE FIGDESC].freeze
        # FRONT/BACK mark passage provenance; BODY is the silent default.
        DIVISION_ELEMENTS = %w[FRONT BACK].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DIV_ELEMENTS, :VERSE_UNITS,
                         :HEAD_UNITS, :PROSE_UNITS, :UNIT_ELEMENTS,
                         :SEPARATOR_ELEMENTS, :DROPPED_ELEMENTS, :DIVISION_ELEMENTS

        Result = Data.define(:units, :title, :metadata)

        def initialize(reader:, path:)
          @reader = reader
          @path = path
          @in_eebo = false
          @seen_text = false
          @drop_depth = nil
          @page = nil
          @divisions = []
          @speakers = []
          @speaker_capture = nil
          @choice_depth = 0
          @frames = [new_frame(nil)]
          @unit = nil
          @units = []
          @header = {}
          @languages = []
          @capture = nil
          @contexts = []
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no <TEXT> element found under <EEBO>" unless @seen_text

          Result.new(units: @units, title: presence(@header[:title]), metadata: metadata)
        end

        private

        def new_frame(component)
          { component: component, child_divs: 0, l: 0, p: 0, h: 0 }
        end

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when *TEXT_NODE_TYPES then text_node(node)
          end
        end

        # -- dispatch ---------------------------------------------------------

        def start_element(node)
          name = node.name
          return enter_eebo(node, name) unless @in_eebo
          return if dropping?

          if DROPPED_ELEMENTS.include?(name)
            @drop_depth = node.depth unless node.empty_element?
            return
          end

          case name
          when "TEXT" then start_text(node)
          when "IDG" then @header[:idg_id] ||= presence(node.attribute("ID"))
          when "SPEAKER" then start_speaker(node)
          when "CHOICE" then @choice_depth += 1 unless node.empty_element?
          when "SIC" then start_sic(node)
          when *DIV_ELEMENTS then open_div(node)
          when *UNIT_ELEMENTS then open_unit(node, name)
          when *SEPARATOR_ELEMENTS then separator(node, name)
          when *DIVISION_ELEMENTS then @divisions.push(name) unless node.empty_element?
          when "SP" then @speakers.push(nil) unless node.empty_element?
          end
        end

        def end_element(node)
          name = node.name
          return header_end(name) unless @in_eebo

          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end

          case name
          when "SPEAKER" then @speaker_capture = nil
          when "CHOICE" then @choice_depth -= 1 if @choice_depth.positive?
          when *DIV_ELEMENTS then close_div
          when *UNIT_ELEMENTS then close_unit(node, name)
          when *DIVISION_ELEMENTS then @divisions.pop if @divisions.last == name
          when "SP" then @speakers.pop unless @speakers.empty?
          end
        end

        def text_node(node)
          value = node.value.to_s
          if !@in_eebo
            @capture << value if @capture
          elsif dropping?
            nil
          elsif @speaker_capture
            @speaker_capture << value
          elsif @unit
            @unit[:text] << value
          end
        end

        # -- the EEBO phase entry / structural frames -------------------------

        def enter_eebo(node, name)
          if name == "EEBO"
            @in_eebo = true
            @capture = nil
          else
            header_start(node, name)
          end
        end

        def start_text(node)
          @seen_text = true
          @header[:text_lang] ||= presence(node.attribute("LANG"))
        end

        # SPEAKER labels its <SP>'s passages; its text never reads. Inside an
        # open unit (defensive — unseen upstream) it drops like apparatus.
        def start_speaker(node)
          return if node.empty_element?

          if @unit || @speakers.empty?
            @drop_depth = node.depth
          else
            @speaker_capture = (@speakers[-1] = +"")
          end
        end

        # SIC inside CHOICE is the typo record — dropped; the reading takes
        # CORR (quirk 3). A standalone SIC stays transparent.
        def start_sic(node)
          return unless @choice_depth.positive?

          @drop_depth = node.depth unless node.empty_element?
        end

        def open_div(node)
          parent = @frames.last
          parent[:child_divs] += 1
          frame = new_frame("d#{parent[:child_divs]}")
          frame[:type] = presence(node.attribute("TYPE"))
          frame[:n] = presence(node.attribute("N"))
          @frames << frame unless node.empty_element?
        end

        def close_div
          @frames.pop if @frames.size > 1
        end

        def div_path
          @frames.filter_map { |frame| frame[:component] }.join(".")
        end

        # -- reading units ----------------------------------------------------

        def open_unit(node, name)
          return if @unit || node.empty_element? # nested unit-openers stay transparent

          @unit = { tag: name, depth: node.depth, n: presence(node.attribute("N")),
                    text: +"", page: @page, speaker: presence(@speakers.last),
                    division: @divisions.last }
        end

        def close_unit(node, name)
          return unless @unit && @unit[:tag] == name && @unit[:depth] == node.depth

          unit = @unit
          @unit = nil
          # Empty unit consumes no ordinal. Unicode-blank, NOT String#strip:
          # the corpus carries <P>&#xA0;</P> placeholders (CME00006 and kin,
          # censused) — an NBSP survives strip but collapses to nothing, and
          # the two notions disagreeing minted an empty Passage.
          return if blank?(unit[:text])

          frame = @frames.last
          token = unit_token(unit[:tag], frame)
          path = div_path
          citation = path.empty? ? token : "#{path}.#{token}"
          @units << Unit.new(citation: citation, text: unit[:text],
                             annotations: annotations_for(unit, frame))
        end

        def unit_token(tag, frame)
          case tag
          when *VERSE_UNITS then "l#{frame[:l] += 1}"
          when *HEAD_UNITS then "h#{frame[:h] += 1}"
          else "p#{frame[:p] += 1}"
          end
        end

        def annotations_for(unit, frame)
          {
            "addressing" => "structural-ordinal",
            "unit" => unit[:tag].downcase,
            "div_type" => frame[:type],
            "div_n" => frame[:n],
            "n" => unit[:n],
            "page" => unit[:page],
            "speaker" => flatten(unit[:speaker]),
            "division" => unit[:division]&.downcase
          }.compact
        end

        # A separator reads as a space; <PB N> additionally tracks the page
        # cite in force — a unit whose text starts ON its first inner <PB>
        # is cited at that page (the corpus-corporum column mold).
        def separator(node, name)
          if name == "PB" && (page = presence(node.attribute("N")))
            @unit[:page] = page if @unit && blank?(@unit[:text])
            @page = page
          end
          @unit[:text] << " " if @unit
        end

        # -- the HEADER phase (first-wins captures, context-flagged) ----------
        #
        # Self-closing elements never open a capture (the openmgh P56
        # lesson — and quirk 5's empty <AUTHOR/> depends on it).

        CONTEXT_ELEMENTS = %w[FILEDESC TITLESTMT PUBLICATIONSTMT SOURCEDESC
                              BIBLFULL LANGUSAGE AVAILABILITY].freeze
        private_constant :CONTEXT_ELEMENTS

        def header_start(node, name)
          if CONTEXT_ELEMENTS.include?(name) && !node.empty_element?
            @contexts.push(name)
            open_capture(:availability) if name == "AVAILABILITY"
            return
          end
          header_field(node, name)
        end

        def header_field(node, name)
          return if node.empty_element?

          case name
          when "TITLE" then open_capture(source_scoped(:title)) if context?("TITLESTMT")
          when "AUTHOR" then open_capture(source_scoped(:author))
          when "EDITOR" then open_capture(source_scoped(:editor))
          when "PUBLISHER" then open_capture(source_scoped(:publisher)) if context?("PUBLICATIONSTMT")
          when "PUBPLACE" then open_capture(source_scoped(:pub_place)) if context?("PUBLICATIONSTMT")
          when "DATE" then open_capture(source_scoped(:pub_date)) if context?("PUBLICATIONSTMT")
          when "IDNO" then open_capture(:idno) if idno_capture?(node)
          when "LANGUAGE" then start_language(node)
          end
        end

        # The BIBLFULL (print source) block mints source_* keys; pub_date
        # stays "date" on the source side (the print edition's own year).
        SOURCE_KEYS = { title: :source_title, author: :source_author, editor: :source_editor,
                        publisher: :source_publisher, pub_place: :source_pub_place,
                        pub_date: :source_date }.freeze
        private_constant :SOURCE_KEYS

        def source_scoped(key)
          context?("BIBLFULL") ? SOURCE_KEYS.fetch(key) : key
        end

        def idno_capture?(node)
          context?("PUBLICATIONSTMT") && !context?("BIBLFULL") && node.attribute("TYPE") == "dlps"
        end

        def start_language(node)
          return unless context?("LANGUSAGE")

          @languages << { id: presence(node.attribute("ID")), label: +"" }
          @capture = @languages.last[:label]
        end

        # Only a capture-opening element's end closes the capture — inner
        # markup (<HI>) stays transparent inside a captured field.
        CAPTURE_CLOSERS = %w[TITLE AUTHOR EDITOR PUBLISHER PUBPLACE DATE IDNO
                             LANGUAGE AVAILABILITY].freeze
        private_constant :CAPTURE_CLOSERS

        def header_end(name)
          @capture = nil if CAPTURE_CLOSERS.include?(name)
          @contexts.pop if CONTEXT_ELEMENTS.include?(name) && @contexts.last == name
        end

        def context?(name) = @contexts.include?(name)

        # First value wins per field; an already-filled buffer never reopens.
        def open_capture(key)
          return if @header.key?(key)

          @capture = (@header[key] = +"")
        end

        def metadata
          {
            "title" => flatten(@header[:title]),
            "author" => flatten(@header[:author]),
            "editor" => flatten(@header[:editor]),
            "publisher" => flatten(@header[:publisher]),
            "pub_place" => flatten(@header[:pub_place]),
            "pub_date" => flatten(@header[:pub_date]),
            "idno" => flatten(@header[:idno]),
            "availability" => flatten(@header[:availability]),
            "source_title" => flatten(@header[:source_title]),
            "source_author" => flatten(@header[:source_author]),
            "source_editor" => flatten(@header[:source_editor]),
            "source_publisher" => flatten(@header[:source_publisher]),
            "source_pub_place" => flatten(@header[:source_pub_place]),
            "source_date" => flatten(@header[:source_date]),
            "language_usage" => language_usage,
            "idg_id" => @header[:idg_id],
            "text_lang" => @header[:text_lang]
          }.compact
        end

        def language_usage
          entries = @languages.filter_map do |entry|
            label = flatten(entry[:label])
            next unless label || entry[:id]

            entry[:id] ? "#{entry[:id]}=#{label}" : label
          end
          entries.empty? ? nil : entries.join("; ")
        end

        # -- helpers ----------------------------------------------------------

        def dropping? = !@drop_depth.nil?

        # Unicode-blank — the same [[:space:]] notion the collapse uses, so
        # the emit gate and the collapse can never disagree again.
        def blank?(text)
          text.match?(/\A[[:space:]]*\z/)
        end

        def flatten(value)
          presence(value&.gsub(/[[:space:]]+/, " ")&.strip)
        end

        def presence(value)
          value if value && !value.empty?
        end
      end
      private_constant :Extraction
    end
  end
end
