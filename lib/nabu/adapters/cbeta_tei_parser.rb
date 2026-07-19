# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one CBETA xml-p5 edition — the `cbeta-tei` family
    # (P33-2): TEI P5 plus CBETA's own cb: extension namespace
    # (http://www.cbeta.org/ns/1.0), probed on real T (Taishō) and X
    # (Xuzangjing) files before design, never invented.
    #
    # == Passage grain: the encoded print line (censused 2026-07-20)
    #
    # Every file carries its canon's own print coordinates as empty <lb>
    # milestones: @n = "PPPPrLL" (four-digit page, register a/b/c…,
    # two-digit line — e.g. "1390a24" = p.1390, register a, line 24), @ed =
    # the canon siglum ("T", "X"). The Taishō/Xuzangjing citation therefore
    # rides FREE: passage urn = <document urn>:<lb @n> verbatim
    # (urn:nabu:cbeta:T85n2884:1390a24 IS "T85, No. 2884, p.1390a24" — the
    # standard scholarly citation), volume in the document id, never
    # invented. A file may ALSO carry a parallel lb stream for a WITNESS
    # edition (X files interleave ed="R150"-style 卍續藏經 lines); only the
    # file's own canon siglum mints — the witness stream is layout of a
    # different print run. Attribute order varies upstream
    # (<lb n=… ed=…> and <lb ed=… n=…> both real; censused) — attributes,
    # never regexes. Lines whose accumulated text is empty (blank layout
    # lines around headers) emit nothing; a duplicate @n (none censused)
    # would disambiguate ":b2" (house ddbdp rule), never quarantine.
    #
    # == Text discipline (all shapes censused on real files)
    #
    # Reading text is captured between <text><body> and </body>. <back> is
    # never read: CBETA encodes the witness apparatus STAND-OFF there
    # (cb:div type="apparatus" — <app from="#beg…"><lem wit="#wit.orig">
    # …</lem><rdg wit="#wit1">…</rdg></app> keyed by body anchors — plus
    # taisho-notes/cf/tt divisions), so the body already carries the
    # edition's reading text. Inside the body:
    #
    # - <note place="inline"> — CBETA's interlinear small-print notes — are
    #   dropped from the reading text but carried VERBATIM per line as a
    #   "notes" annotation; every other <note> subtree is dropped.
    # - <g ref="#CB…"/> gaiji: the element's text content (CBETA's Unicode
    #   approximation) stays in the reading text; the ref rides the line's
    #   "gaiji" annotation verbatim, NOT resolved against <charDecl> (the
    #   P33-0 Kanripo rule; composition/PUA mappings stay in canonical XML).
    # - Inline <app>/<lem> (defensive; censused apparatus is stand-off) keep
    #   the <lem> reading, <rdg> subtrees drop.
    # - <cb:t place="foot"> (the back-matter multilingual term glosses —
    #   Dīrgha-āgama beside 長阿含經) drops; plain <cb:t> text flows.
    # - <cb:mulu> (table-of-contents entries duplicating the adjacent
    #   <head>; censused on X55n0899) drops.
    # - <space quantity="0"/> contributes nothing; any other <space/> one
    #   space. <caesura/> (verse half-line) contributes nothing — CJK verse
    #   carries its own punctuation. <anchor/>, foreign-ed <lb>/<pb> are
    #   empty and ignored. Everything else (p, lg, l, head, byline,
    #   cb:div, cb:jhead, cb:docNumber…) is transparent: line grain means
    #   text flows to the open print line.
    # - <milestone unit="juan" n="…"/> tracks the current fascicle; each
    #   passage carries it as the "juan" annotation.
    #
    # == The license gate (canon-level, re-verified per file)
    #
    # Every T and X header carries the SAME <availability> grant verbatim:
    # "Available for non-commercial use when distributed with this header
    # intact." (censused across all sampled T/X files at 2026.R1). The
    # parser refuses (ParseError) any file whose availability does not
    # carry that sentence — a drifted grant must quarantine loudly, never
    # ride the source's nc class on faith. The grant is carried in
    # Document#metadata["license"]; the witness list (tagsDecl <witness>:
    # 【CB】【大】【宋】【元】【明】…) in metadata["witnesses"].
    #
    # == Streaming
    #
    # Nokogiri::XML::Reader only: T ships 27 files over the house 5 MB DOM
    # limit (max 17.2 MB, T25n1509), X ships 7 (max 9.0 MB). One pass.
    class CbetaTeiParser
      # All CBETA T/X text is Literary Chinese (headers tag zh-Hant, the
      # script; the language is lzh — the SuttaCentral Āgama precedent).
      LANGUAGE = "lzh"

      # The in-file grant, byte-verbatim (see class note). Field-gated at
      # <body>; quoted in docs and the 02-sources row.
      AVAILABILITY_GRANT =
        "Available for non-commercial use when distributed with this header intact."

      # One print line: citation = lb @n verbatim; juan/gaiji/notes ride
      # annotations.
      Unit = Data.define(:citation, :text, :juan, :gaiji, :notes)
      private_constant :Unit

      def parse(source, urn:, canon:, title: nil, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        extraction = extract(source, path: path, canon: canon)
        units = disambiguate_collisions(extraction.units)
        build_document(extraction, units, urn: urn, title: title, path: path)
      end

      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      def extract(source, path:, canon:)
        with_io(source) do |io|
          Extraction.new(reader: Nokogiri::XML::Reader(io, path), path: path, canon: canon).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      # The house collision tolerance: duplicates disambiguate
      # deterministically in document order, never quarantine.
      def disambiguate_collisions(units)
        seen = Hash.new(0)
        units.map do |unit|
          count = seen[unit.citation] += 1
          count == 1 ? unit : unit.with(citation: "#{unit.citation}:b#{count}")
        end
      end

      def build_document(extraction, units, urn:, title:, path:)
        document = Document.new(
          urn: urn, language: LANGUAGE, title: extraction.title || title,
          canonical_path: path, metadata: document_metadata(extraction)
        )
        units.each_with_index do |unit, sequence|
          text = Normalize.nfc(unit.text.gsub(/[[:space:]]+/, " ").strip)
          document << Passage.new(
            urn: "#{urn}:#{unit.citation}", language: LANGUAGE, text: text,
            annotations: unit_annotations(unit), sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable print lines found in <text><body>" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      def document_metadata(extraction)
        metadata = { "license" => AVAILABILITY_GRANT }
        metadata["witnesses"] = extraction.witnesses unless extraction.witnesses.empty?
        metadata["canon"] = extraction.canon if extraction.canon
        metadata["vol"] = extraction.vol if extraction.vol
        metadata["no"] = extraction.no if extraction.no
        metadata
      end

      def unit_annotations(unit)
        annotations = {}
        annotations["juan"] = unit.juan if unit.juan
        annotations["gaiji"] = unit.gaiji unless unit.gaiji.empty?
        annotations["notes"] = unit.notes unless unit.notes.empty?
        annotations
      end

      # The single-pass Reader state machine: header phase (title, idno,
      # availability gate, witness list), body phase (print-line units),
      # done at </body> — <back> never read.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        # Body subtrees whose text never reaches the reading line. <note> is
        # special-cased (inline notes ride annotations); <mulu> is cb:mulu.
        DROPPED_ELEMENTS = %w[note rdg mulu].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS

        Result = Data.define(:units, :title, :witnesses, :canon, :vol, :no)

        attr_reader :title, :witnesses, :canon, :vol, :no

        def initialize(reader:, path:, canon:)
          @reader = reader
          @path = path
          @expected_canon = canon
          @title = nil
          @capture = nil            # header text sink (:title, :idno, :witness, :availability)
          @availability_text = +""
          @in_availability = false
          @witnesses = []
          @idno = {}
          @idno_type = nil
          @seen_body = false
          @in_body = false
          @drop_depth = nil
          @note_buffer = nil        # open inline-note text, riding annotations
          @juan = nil
          @line = nil               # open print line {citation:, text:, gaiji:, notes:}
          @units = []
        end

        def call
          @reader.each do |node|
            process(node)
            break if @seen_body && !@in_body # </body> reached: back matter is never read
          end
          raise ParseError, "#{@path}: no <text><body> found" unless @seen_body

          Result.new(units: @units, title: @title, witnesses: @witnesses,
                     canon: @idno["canon"], vol: @idno["vol"], no: @idno["no"])
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
          return enter_body(node) if name == "body" && !@seen_body
          return header_element(node, name) unless @in_body
          return if dropping?

          case name
          when "lb" then line_break(node)
          when "note" then open_note(node)
          when "g" then @line[:gaiji] << node.attribute("ref") if @line && node.attribute("ref")
          when "milestone" then @juan = node.attribute("n") if node.attribute("unit") == "juan"
          when "space" then append(" ") unless node.attribute("quantity") == "0"
          when "t" then drop_subtree(node) if node.attribute("place") == "foot"
          when *DROPPED_ELEMENTS then drop_subtree(node)
          end
        end

        def end_element(node)
          if @in_body
            return close_body if local_name(node) == "body"
            return unless dropping?

            if node.depth == @drop_depth
              @drop_depth = nil
              close_note
            end
          else
            header_end_element(local_name(node))
          end
        end

        def text_node(node)
          value = node.value.to_s
          if @in_body
            return @note_buffer << value if dropping? && @note_buffer
            return if dropping?

            append(value)
          else
            header_text(value)
          end
        end

        # -- header ----------------------------------------------------------

        def header_element(node, name)
          case name
          when "title"
            @capture = :title if @title.nil? && node.attribute("level") == "m" &&
                                 node.attribute("xml:lang") == "zh-Hant"
          when "idno" then @idno_type = node.attribute("type")
          when "witness" then @capture = :witness
          when "availability" then @in_availability = true unless node.empty_element?
          end
        end

        def header_end_element(name)
          @capture = nil
          @in_availability = false if name == "availability"
          @idno_type = nil if name == "idno"
        end

        def header_text(value)
          @availability_text << value if @in_availability
          case @capture
          when :title
            @title = value.strip
            @capture = nil
          when :witness
            @witnesses << value.strip
            @capture = nil
          end
          @idno[@idno_type] = value.strip if @idno_type
        end

        # The canon-level license gate, re-verified per file, plus the
        # canon identity check — both loud, both before any body text.
        def enter_body(node)
          unless @availability_text.include?(CbetaTeiParser::AVAILABILITY_GRANT)
            raise ParseError, "#{@path}: license gate: <availability> does not carry the CBETA " \
                              "grant verbatim (#{CbetaTeiParser::AVAILABILITY_GRANT.inspect}) — " \
                              "refusing to ride the nc class on faith"
          end
          declared = @idno["canon"]
          if declared && declared != @expected_canon
            raise ParseError, "#{@path}: canon mismatch: caller says #{@expected_canon.inspect}, " \
                              "the header declares #{declared.inspect}"
          end
          @seen_body = true
          @in_body = !node.empty_element?
        end

        # -- body ------------------------------------------------------------

        # Only the file's own canon siglum mints print lines; witness-edition
        # lb streams (ed="R150"…) are another print run's layout.
        def line_break(node)
          return unless node.attribute("ed") == @expected_canon

          flush_line
          @line = { citation: node.attribute("n"), text: +"", gaiji: [], notes: [] }
        end

        def open_note(node)
          return if node.empty_element?

          @note_buffer = +"" if @line && node.attribute("place") == "inline"
          drop_subtree(node)
        end

        def close_note
          return if @note_buffer.nil?

          note = @note_buffer.strip
          @line[:notes] << note unless note.empty?
          @note_buffer = nil
        end

        def close_body
          flush_line
          @in_body = false
        end

        def flush_line
          line = @line
          @line = nil
          return if line.nil? || line[:citation].nil? || line[:text].strip.empty?

          @units << Unit.new(citation: line[:citation], text: line[:text],
                             juan: @juan, gaiji: line[:gaiji], notes: line[:notes])
        end

        def append(value)
          @line[:text] << value if @line
        end

        def drop_subtree(node)
          @drop_depth = node.depth unless node.empty_element?
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
