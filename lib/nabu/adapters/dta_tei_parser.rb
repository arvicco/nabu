# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one DTA-Basisformat (TEI/P5) text (P94-0) — a
    # bespoke `dta-tei` family. The Deutsches Textarchiv's 5,481 texts
    # span 1473–1969 and every genre (novels, plays, newspapers,
    # scientific prose, dictionaries), so the census verdict (Luther
    # 1524 / Kant 1784 / Fontane 1899, 2026-09-03) is the openMGH mold:
    #
    # == Page grain (the addressing)
    #
    # DTA texts are cited by page/facsimile, and only a page-grain
    # accumulate-and-flush survives the corpus's element heterogeneity
    # without silently losing text. The reading flow of <front>, <body>
    # and <back> accumulates; every <pb> flushes the open page:
    #
    #   p<n>     the printed page number when the pb carries @n
    #            (non-alphanumerics stripped, the openMGH rule)
    #   f<num>   else the facsimile ordinal from @facs ("#f0009")
    #   p0       text before any pb
    #
    # Blank scan pages (a pb streak with no interleaved text) mint
    # nothing. Residual duplicate citations disambiguate positionally
    # (":b2" — the house belt), never quarantine.
    #
    # == The ¬<lb/> hyphenation join
    #
    # DTA prints line-break hyphenation as "Maſchi¬<lb/>nen": one word,
    # broken by the typesetter. The join (canonical means canonical, but
    # markup is markup — the openMGH w-pair precedent): when the buffer
    # ends in "¬" at an <lb>, the marker drops, no space is inserted,
    # and the next text node's leading whitespace strips. A <pb> arriving
    # mid-join DEFERS the page flush so the whole word lands on the page
    # it starts on. A plain <lb> is one space.
    #
    # == As printed (the v1 layer decision)
    #
    # <choice> keeps the printed half — <sic> (errors and all), <abbr>
    # (abbreviation tildes as combining marks), <orig> — and drops the
    # editors' <corr>/<expan>/<reg> layers. DTA's normalized orthography
    # is deliberately not ingested in v1; corrections are enrichments.
    #
    # == Dropped vs kept
    #
    # <fw> (running heads, signature marks, catchwords) and <figure>
    # subtrees drop — the binder's and engraver's apparatus, not reading
    # text. <note> (DTA notes are AUTHORIAL footnotes — Kant's own) is
    # kept: its text buffers aside and appends at the TAIL of its page's
    # passage, physically where the print puts it. Everything else
    # (<hi>, <q>, <persName>, <supplied>, …) is transparent reading
    # text; block-element ends contribute a space so headings never glue
    # to paragraphs. Whitespace collapses, output is NFC.
    #
    # == Header
    #
    # Identity is the DTADirName <idno> — the caller (discover) peeks it
    # the same way. Title/author come from the FIRST titleStmt
    # (fileDesc's; sourceDesc/biblFull duplicates it). The print year
    # lives ONLY under sourceDesc — fileDesc's publicationStmt <date>
    # is the digital edition's timestamp and must not win. Genre rides
    # the dtamain/dtasub classCodes. langUsage is verified: a text whose
    # first ident isn't "deu" quarantines loudly (the rem precedent) —
    # the corpus claims German throughout, so a divergence is news.
    class DtaTeiParser
      GERMAN_IDENT = "deu"

      Unit = Data.define(:citation, :text, :annotations)
      private_constant :Unit

      def parse(source, urn:, language:, title: nil, metadata: {}, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        extraction = extract(source, path: path)
        verify_language!(extraction, path)
        units = disambiguate_collisions(extraction.units)
        build_document(units, urn: urn, language: language,
                              title: title || extraction.header["title"],
                              path: path,
                              metadata: extraction_metadata(extraction).merge(metadata))
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

      def verify_language!(extraction, path)
        ident = extraction.header["lang_ident"]
        return if ident.nil? || ident == GERMAN_IDENT

        raise ParseError, "#{path}: langUsage ident #{ident.inspect} — the DTA corpus claims " \
                          "#{GERMAN_IDENT.inspect} throughout; a divergent text is news, not a default"
      end

      def extraction_metadata(extraction)
        extraction.header.slice("author", "author_gnd", "date", "place",
                                "genre", "subgenre", "dta_dirname").compact
      end

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

      # The single-pass Reader state machine: a header phase mines the
      # teiHeader (first-wins fields, sourceDesc-scoped dates), then the
      # text phase runs the page chunker with the ¬<lb/> join.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        # fw/figure: apparatus. corr/expan/reg: the editors' layer — the
        # printed sic/abbr/orig halves stay (class note).
        DROPPED_ELEMENTS = %w[fw figure corr expan reg teiHeader].freeze
        # Ends of block-level elements contribute a space so a heading
        # never glues to the paragraph after it.
        BLOCK_ELEMENTS = %w[p head opener closer salute dateline byline argument
                            item l lg row cell titlePart docTitle docAuthor docImprint
                            docDate speaker stage sp table list castItem trailer].freeze
        HYPHEN = "¬"
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS, :BLOCK_ELEMENTS, :HYPHEN

        Result = Data.define(:units, :header)

        def initialize(reader:, path:)
          @reader = reader
          @path = path
          @in_header = false
          @header_done = false
          @capture = nil
          @header = {}
          @in_source_desc = false
          @class_scheme = nil
          @in_text = false
          @drop_depth = nil
          # page chunker state
          @page = nil                # [citation token, printed @n, facs]
          @pending_page = nil        # a pb seen mid-join
          @page_fallback = 0
          @strip_next = false        # just joined across ¬<lb/>
          @buffer = +""
          # footnote side-buffer
          @note_depth = nil
          @note_buffer = nil
          @notes = []
          @units = []
        end

        def call
          @reader.each { |node| process(node) }
          flush_page
          Result.new(units: @units, header: @header)
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
          if name == "teiHeader" && !@header_done
            @in_header = true
            return
          end
          return header_element(node, name) if @in_header

          case name
          when "text"
            # Only the OUTER <text> toggles the phase: a <floatingText>'s
            # inner <text> must not end it early.
            if !@in_text && !node.empty_element?
              @in_text = true
              @text_depth = node.depth
            end
          else text_element(node, name) if @in_text
          end
        end

        def end_element(node)
          name = local_name(node)
          if @in_header
            end_header_element(name)
            return
          end
          return unless @in_text

          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end
          case name
          when "text" then @in_text = false if node.depth == @text_depth
          when "note" then close_note(node)
          else
            (@note_depth ? @note_buffer : @buffer) << " " if BLOCK_ELEMENTS.include?(name)
          end
        end

        def text_node(node)
          value = node.value.to_s
          if @capture
            @capture << value
            return
          end
          return unless @in_text && !dropping?

          if @strip_next
            value = value.lstrip
            return if value.empty?

            @strip_next = false
          end
          if @note_depth
            @note_buffer << value
          elsif @pending_page
            append_completing_word(value)
          else
            @buffer << value
          end
        end

        # A page break arrived mid-join (text¬<lb/><pb/>tail): the word's
        # tail — up to the first whitespace — finishes on the page the word
        # started on, THEN the deferred page applies and the remainder opens
        # the new page (the openMGH deferred-flush behavior).
        def append_completing_word(value)
          head, separator, tail = value.partition(/[[:space:]]/)
          @buffer << head
          return if separator.empty? # the word is still running — keep deferring

          token, printed = @pending_page
          @pending_page = nil
          apply_page(token, printed)
          @buffer << tail
        end

        # -- header -----------------------------------------------------------
        #
        # First-wins captures; dates and places only from INSIDE sourceDesc
        # (fileDesc's publicationStmt date is the digital timestamp). The
        # classCode scheme fragment (#dtamain/#dtasub) routes genre.

        def header_element(node, name)
          outer_capture = @capture
          case name
          when "sourceDesc" then @in_source_desc = true unless node.empty_element?
          when "title" then @capture = (@header["title"] ||= +"") if @header["title"].nil? && main_title?(node)
          when "surname" then @capture = (@header["surname"] ||= +"") if @header["surname"].nil?
          when "forename" then @capture = (@header["forename"] ||= +"") if @header["forename"].nil?
          when "persName" then capture_gnd(node)
          when "date" then @capture = (@header["date"] ||= +"") if @in_source_desc && @header["date"].nil?
          when "pubPlace" then @capture = (@header["place"] ||= +"") if @in_source_desc && @header["place"].nil?
          when "idno" then start_idno(node)
          when "classCode" then start_class_code(node)
          when "language" then start_language(node)
          end
          @capture = outer_capture if node.empty_element? # self-closing fields must not swallow the header
        end

        def end_header_element(name)
          case name
          when "teiHeader"
            @in_header = false
            @header_done = true
            finish_header
          when "sourceDesc" then @in_source_desc = false
          when "title", "surname", "forename", "date", "pubPlace", "idno", "classCode", "language"
            @capture = nil
          end
        end

        def main_title?(node)
          type = node.attribute("type")
          type.nil? || type == "main"
        end

        def capture_gnd(node)
          ref = node.attribute("ref").to_s
          @header["author_gnd"] ||= ref if ref.include?("d-nb.info/gnd/")
        end

        def start_idno(node)
          return unless node.attribute("type") == "DTADirName"

          @capture = (@header["dta_dirname"] ||= +"") if @header["dta_dirname"].nil?
        end

        def start_class_code(node)
          scheme = node.attribute("scheme").to_s
          key = if scheme.end_with?("#dtamain") then "genre"
                elsif scheme.end_with?("#dtasub") then "subgenre"
                end
          return if key.nil? || @header[key]

          @capture = (@header[key] = +"")
        end

        def start_language(node)
          ident = node.attribute("ident")
          @header["lang_ident"] ||= ident if ident && !ident.empty?
        end

        def finish_header
          surname = presence(@header.delete("surname")&.strip)
          forename = presence(@header.delete("forename")&.strip)
          @header["author"] = [surname, forename].compact.join(", ") if surname
          @header["title"] = presence(@header["title"]&.gsub(/[[:space:]]+/, " ")&.strip)
          %w[date place genre subgenre dta_dirname].each do |key|
            @header[key] = presence(@header[key]&.strip)
          end
          @header.compact!
        end

        # -- the page chunker -------------------------------------------------

        def text_element(node, name)
          return if dropping?

          if DROPPED_ELEMENTS.include?(name)
            @drop_depth = node.depth unless node.empty_element?
            return
          end

          case name
          when "pb" then page_break(node)
          when "lb" then line_break
          when "cb" then append_space
          when "note" then open_note(node)
          end
        end

        def line_break
          buffer = @note_depth ? @note_buffer : @buffer
          trimmed = buffer.sub(/[[:space:]]*\z/, "")
          if trimmed.end_with?(HYPHEN)
            buffer.replace(trimmed.delete_suffix(HYPHEN))
            @strip_next = true
          else
            buffer << " "
          end
        end

        def append_space
          (@note_depth ? @note_buffer : @buffer) << " "
        end

        def page_break(node)
          token = page_token(node)
          printed = presence(node.attribute("n"))
          # Inside a footnote or mid-join the flush defers: the note (and
          # the broken word) belong to the page they started on.
          if @note_depth || @strip_next
            @pending_page = [token, printed]
            return
          end
          apply_page(token, printed)
        end

        def apply_page(token, printed)
          flush_page
          @page = [token, printed]
        end

        def page_token(node)
          printed = presence(node.attribute("n"))&.gsub(/[^0-9A-Za-z]/, "")
          return "p#{printed}" if presence(printed)

          facs = presence(node.attribute("facs"))&.delete_prefix("#")
          return facs if presence(facs)

          "px#{@page_fallback += 1}"
        end

        # -- footnotes ---------------------------------------------------------

        def open_note(node)
          return if node.empty_element? || @note_depth # a nested note rides its outer's buffer

          @note_depth = node.depth
          @note_buffer = +""
        end

        def close_note(node)
          return unless @note_depth && node.depth == @note_depth

          text = @note_buffer.gsub(/[[:space:]]+/, " ").strip
          @notes << text unless text.empty?
          @note_depth = nil
          @note_buffer = nil
          complete_deferred_page_if_clear
        end

        def complete_deferred_page_if_clear
          return if @pending_page.nil? || @note_depth || @strip_next

          token, printed = @pending_page
          @pending_page = nil
          apply_page(token, printed)
        end

        # -- flushing ----------------------------------------------------------

        def flush_page
          text = [@buffer, *@notes].join(" ")
          @buffer = +""
          @notes = []
          @strip_next = false
          return if text.strip.empty?

          token = @page ? @page[0] : "p0"
          @units << Unit.new(
            citation: token,
            text: text,
            annotations: { "addressing" => "page", "unit" => "page",
                           "page" => @page&.[](1) }.compact
          )
        end

        # -- helpers -----------------------------------------------------------

        def dropping? = !@drop_depth.nil?

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
