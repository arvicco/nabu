# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one openMGH volume (P45-2) — a bespoke
    # `openmgh-tei` family. The compose-an-existing-family bet was REFUTED
    # from the real bytes (censused on MGH SS rer. Germ. 25, Dt. Chron. 1,2
    # and DD Rudolf., 2026-07-25):
    #
    #   1. The body is a bare MILESTONE STREAM: one <ab> per div, the reading
    #      text as raw character data segmented by empty <pb>/<lb> milestones
    #      — zero <p>/<l>/<s>/<opener> reading elements (census: Einhard =
    #      1,439 <lb>, 4 <p> all in the teiHeader). croala-tei/SARIT iterate
    #      reading UNITS and would find nothing; a whole volume would parse
    #      to zero passages.
    #   2. Hyphenated words ship as <w> PAIRS (xml:id="w1"/"w2",
    #      corresp="#w1 #w2", lemma) that must re-join across <lb> AND
    #      across <pb> — <w>descrip-</w><lb/><w>sisse</w>, and
    #      <w>dili-</w><pb/><w>gitur</w> straddling a page boundary.
    #      cora-tei treats every <w> as an independent token record and
    #      would mint both broken halves.
    #   3. Diplomata volumes are a SECOND DIALECT in the same corpus:
    #      <teiCorpus> root, one inner <TEI> per charter with its own
    #      header (<idno type="charternum">, the charter's medieval date in
    #      sourceDesc/bibl/date) and a <div type="tenor"> body. No existing
    #      family enters a teiCorpus root.
    #
    # == Citation addressing (stable, derived from the TEI's own structure)
    #
    # Scriptores dialect (<TEI> root: body div[@type=volume] →
    # div[@type=work @n=title] → optional unnumbered div[@type=part] → <ab>):
    #
    #   w<k>.p<page>   k = 1-based ordinal of the work div; page = the
    #                  printed page number (pb @n, non-alphanumerics
    #                  stripped: "XXVIII" → pXXVIII, "(46)" → p46) — the
    #                  page IS how MGH volumes are cited. Page state is
    #                  document-global: a work opening mid-page (Gerwardi
    #                  versus, zero <pb> of its own) sits on the page the
    #                  previous work left open. A pb without a usable @n
    #                  falls back to the physical image number from its
    #                  xml:id (bsb…_00028 → p00028); text before any pb is
    #                  p0. part divs are transparent (no flush — the page
    #                  chunk is the unit, parts carry no numbering).
    #
    # Diplomata dialect (<teiCorpus> root): the charter is the unit —
    #
    #   c<charternum>  from the charter's own <idno type="charternum">
    #                  (fallback: c~<k>, the 1-based inner-TEI ordinal).
    #                  A tenor with no text (deperdita — charters known
    #                  only by mention) emits nothing.
    #
    # Residual duplicate citations disambiguate positionally (":b2" — the
    # house ddbdp/GRETIL/croala belt), never quarantine.
    #
    # == The hyphenation join (canonical means canonical, but markup is markup)
    #
    # A <w> whose xml:id is the FIRST id in its @corresp starts a join: its
    # trailing "-" drops, the intervening <lb>/<pb> separators and
    # whitespace-only text are suppressed, and the closing half concatenates
    # directly ("descripsisse"). A <pb> inside a join DEFERS the page flush
    # until the word completes, so the whole word lands on the page it
    # starts on. A <w> with no @corresp passes through verbatim.
    #
    # == Text discipline
    #
    # <lb> → one space; <pb> → chunk boundary (Scriptores) or space
    # (Diplomata); <cb>/<anchor> → nothing (column breaks — the reading
    # flow continues); <note> subtrees drop (none censused in the samples,
    # but MGH apparatus must never leak if a volume carries it); every
    # other element (<hi>, <ref>, …) is transparent reading text.
    # Whitespace runs collapse to one space, ends strip, output is NFC.
    # No xml:lang exists anywhere upstream — language is the caller's.
    #
    # == Header metadata
    #
    # The volume teiHeader yields the document title ("MGH SS rer. Germ.
    # 25: Einhardi Vita Karoli Magni"), editor, the BSB/MGH idnos and the
    # PRINT edition's date/place (sourceDesc: "Hannover 1911") — which is
    # honestly NOT the medieval text's date, so it rides metadata as
    # printed_date/printed_place and never pretends to feed the timeline.
    # Charter headers additionally yield the medieval date VERBATIM
    # ("878 März 25." — German editorial prose, carried as a per-passage
    # "date" annotation, unparsed).
    #
    # == Streaming
    #
    # Nokogiri::XML::Reader in a single pass (volumes reach ~600 KB zipped
    # today and the corpus is "successively provided" — the house >5 MB DOM
    # threshold is one big volume away).
    class OpenmghTeiParser
      # One emitted unit: citation suffix, raw accumulated text, annotations.
      Unit = Data.define(:citation, :text, :annotations)
      private_constant :Unit

      def parse(source, urn:, language:, title: nil, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        extraction = extract(source, path: path)
        units = disambiguate_collisions(extraction.units)
        build_document(units, urn: urn, language: language,
                              title: title || extraction.title,
                              path: path, metadata: extraction.metadata)
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

      def build_document(units, urn:, language:, title:, path:, metadata:)
        document = Document.new(urn: urn, language: language, title: title,
                                canonical_path: path, metadata: metadata)
        units.each_with_index do |unit, sequence|
          document << Passage.new(
            urn: "#{urn}:#{unit.citation}",
            language: language,
            text: Normalize.nfc(unit.text.gsub(/[[:space:]]+/, " ").strip),
            annotations: unit.annotations,
            sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable passages found" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The single-pass Reader state machine. The root element picks the
      # dialect (:volume for <TEI>, :corpus for <teiCorpus>); a header phase
      # mines each teiHeader; the body phase runs the milestone-stream
      # chunker with the w-pair join.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        DROPPED_ELEMENTS = %w[note].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS

        Result = Data.define(:units, :title, :metadata)

        def initialize(reader:, path:)
          @reader = reader
          @path = path
          @mode = nil                # :volume | :corpus
          @in_header = false         # inside a teiHeader (volume-level or charter-level)
          @in_body = false
          @drop_depth = nil
          @capture = nil             # a header field currently accumulating text
          # volume-level header capture
          @volume = { title: nil, editor: nil, idnos: {}, printed_date: nil, printed_place: nil }
          @header_count = 0
          @in_source_desc = false
          @idno_type = nil
          # charter (inner TEI) state — :corpus mode
          @charter_ordinal = 0
          @charter = nil
          # Scriptores body state
          @work_ordinal = 0
          @work_n = nil
          @in_work = false
          @page = nil                # [citation token, printed @n verbatim]
          @pending_page = nil        # a pb seen mid-join, applied when the word closes
          @page_fallback = 0
          @joining = false
          @buffer = +""
          @units = []
          # w-pair capture state
          @capture_w = false
          @w_buffer = nil
          @w_role = nil
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no <TEI> or <teiCorpus> root found" if @mode.nil?

          Result.new(units: @units, title: presence(@volume[:title]), metadata: metadata)
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
          return start_root(name) if @mode.nil?

          if name == "TEI" && @mode == :corpus
            @charter_ordinal += 1
            @charter = { title: nil, number: nil, date: nil }
            return
          end
          return start_header(node, name) if @in_header || name == "teiHeader"

          case name
          when "body" then @in_body = true unless node.empty_element?
          else body_element(node, name) if @in_body
          end
        end

        def end_element(node)
          name = local_name(node)
          return end_header(name) if @in_header

          case name
          when "TEI" then flush_charter if @mode == :corpus
          when "body" then end_body
          else body_element_end(node, name) if @in_body
          end
        end

        def text_node(node)
          value = node.value.to_s
          if @capture
            @capture << value
          elsif @in_body && !dropping?
            return @w_buffer << value if @capture_w

            # Whitespace-only runs inside a join are the markup's indentation
            # around the suppressed <lb>/<pb>, never reading text.
            return if @joining && value.strip.empty?

            @buffer << value
          end
        end

        # -- roots ------------------------------------------------------------

        def start_root(name)
          case name
          when "TEI" then @mode = :volume
          when "teiCorpus" then @mode = :corpus
          end
        end

        # -- headers ----------------------------------------------------------
        #
        # The FIRST teiHeader is the volume's (in both dialects); every later
        # header (:corpus mode) belongs to the charter whose inner <TEI> just
        # opened. sourceDesc scoping keeps the print-edition date (biblFull/
        # publicationStmt/date, Scriptores) and the charter's medieval date
        # (bibl/date) apart from the TEI conversion timestamps outside it.

        def start_header(node, name)
          unless @in_header
            @in_header = true
            @header_count += 1
            @in_source_desc = false
            return
          end
          outer_capture = @capture
          case name
          when "sourceDesc" then @in_source_desc = true unless node.empty_element?
          when "title" then capture_title
          when "editor" then @capture = (@volume[:editor] ||= +"") if volume_header? && @volume[:editor].nil?
          when "idno" then start_idno(node)
          when "date" then start_date(node)
          when "pubPlace" then @capture = (@volume[:printed_place] ||= +"") if volume_header? && @in_source_desc
          end
          # A SELF-CLOSING capture field (the DD F. II. charters' <date/> —
          # P56 hotfix rider, 2026-08-02) gets no end event from the Reader,
          # so the capture it opened must close right here; left dangling it
          # swallows everything after it — the entire charter tenor drained
          # into the date buffer and three volumes quarantined with "no
          # citable passages found". The field keeps its "" (seen but empty),
          # which flatten/presence later drop from the annotations.
          @capture = outer_capture if node.empty_element?
        end

        def end_header(name)
          case name
          when "teiHeader" then @in_header = false
          when "sourceDesc" then @in_source_desc = false
          when "title", "editor", "idno", "date", "pubPlace" then @capture = nil
          end
        end

        def volume_header? = @header_count == 1

        # The first <title> of each header wins: the volume's for header 1,
        # the charter's own ("MGH D Rudolf. 1") for the inner headers.
        def capture_title
          if volume_header?
            @capture = (@volume[:title] ||= +"") if @volume[:title].nil?
          elsif @charter && @charter[:title].nil?
            @capture = (@charter[:title] ||= +"")
          end
        end

        def start_idno(node)
          type = presence(node.attribute("type"))
          if volume_header?
            return if type.nil? || @volume[:idnos].key?(type)

            @capture = (@volume[:idnos][type] = +"")
          elsif @charter && type == "charternum" && @charter[:number].nil?
            @capture = (@charter[:number] ||= +"")
          end
        end

        # Dates only from INSIDE sourceDesc: the print edition's year for the
        # volume header, the charter's medieval date for an inner header.
        def start_date(_node)
          return unless @in_source_desc

          if volume_header?
            @capture = (@volume[:printed_date] ||= +"") if @volume[:printed_date].nil?
          elsif @charter && @charter[:date].nil?
            @capture = (@charter[:date] ||= +"")
          end
        end

        # -- body: the milestone-stream chunker -------------------------------

        def body_element(node, name)
          return if dropping?

          if DROPPED_ELEMENTS.include?(name)
            @drop_depth = node.depth unless node.empty_element?
            return
          end

          case name
          when "div" then open_div(node)
          when "pb" then page_break(node)
          when "lb" then @buffer << " " unless @joining
          when "w" then open_w(node)
          end
        end

        def body_element_end(node, name)
          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end

          close_w if name == "w"
          # div closes need no action: a work's trailing chunk flushes when
          # the NEXT work opens or the body ends; part/volume divs are
          # transparent throughout.
        end

        def end_body
          @in_body = false
          flush_scriptores if @mode == :volume
        end

        def open_div(node)
          return unless @mode == :volume
          return unless presence(node.attribute("type")) == "work"

          flush_scriptores
          @work_ordinal += 1
          @work_n = presence(node.attribute("n"))
          @in_work = true
        end

        def page_break(node)
          token = page_token(node)
          printed = presence(node.attribute("n"))
          if @joining
            @pending_page = [token, printed]
            return
          end
          apply_page(token, printed)
        end

        def apply_page(token, printed)
          flush_scriptores if @mode == :volume
          @page = [token, printed]
          @buffer << " " if @mode == :corpus
        end

        # p<printed @n, non-alphanumerics stripped>; fallback: the physical
        # image ordinal from the pb xml:id (bsb00000728_00028 → p00028);
        # last resort: a positional counter.
        def page_token(node)
          printed = presence(node.attribute("n"))&.gsub(/[^0-9A-Za-z]/, "")
          return "p#{printed}" if presence(printed)

          physical = presence(node.attribute("xml:id"))&.slice(/_(\d+)\z/, 1)
          return "p#{physical}" if physical

          "px#{@page_fallback += 1}"
        end

        # -- the w-pair join --------------------------------------------------

        def open_w(node)
          ids = (node.attribute("corresp") || "").scan(/#(\S+)/).flatten
          id = presence(node.attribute("xml:id"))
          @w_role = if ids.empty? || id.nil? then :solo
                    elsif id == ids.first then :first
                    elsif id == ids.last then :last
                    else :middle
                    end
          @w_buffer = +""
          @capture_w = true
          close_w if node.empty_element? # a childless <w/> gets no end event
        end

        def close_w
          return unless @capture_w

          text = @w_buffer
          case @w_role
          when :first
            @buffer << text.sub(/-\z/, "")
            @joining = true
          when :last
            @buffer << text
            @joining = false
            complete_deferred_page
          else
            @buffer << text
          end
          @capture_w = false
          @w_buffer = nil
        end

        def complete_deferred_page
          return if @pending_page.nil?

          token, printed = @pending_page
          @pending_page = nil
          apply_page(token, printed)
        end

        # -- flushing ---------------------------------------------------------

        def flush_scriptores
          text = @buffer
          @buffer = +""
          return if text.strip.empty?

          work = @work_ordinal.positive? ? @work_ordinal : 1
          token = @page ? @page[0] : "p0"
          @units << Unit.new(
            citation: "w#{work}.#{token}",
            text: text,
            annotations: {
              "addressing" => "work-page",
              "unit" => "page",
              "work" => @work_n,
              "page" => @page&.[](1)
            }.compact
          )
        end

        def flush_charter
          text = @buffer
          @buffer = +""
          charter = @charter
          @charter = nil
          return if charter.nil? || text.strip.empty?

          number = presence(charter[:number]&.strip)
          @units << Unit.new(
            citation: number ? "c#{number}" : "c~#{@charter_ordinal}",
            text: text,
            annotations: {
              "addressing" => "charter-number",
              "unit" => "tenor",
              "n" => number,
              "charter" => flatten(charter[:title]),
              "date" => flatten(charter[:date])
            }.compact
          )
        end

        # -- metadata ---------------------------------------------------------

        def metadata
          {
            "editor" => flatten(@volume[:editor]),
            "idno_bsb" => flatten(@volume[:idnos]["BSB"]),
            "idno_mgh" => flatten(@volume[:idnos]["MGH"]),
            "printed_date" => flatten(@volume[:printed_date]),
            "printed_place" => flatten(@volume[:printed_place])
          }.compact
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
