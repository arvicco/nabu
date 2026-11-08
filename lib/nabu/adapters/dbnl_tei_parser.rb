# frozen_string_literal: true

require "nokogiri"
require "stringio"

require_relative "source_read"
require_relative "streaming_tei_parser"

module Nabu
  module Adapters
    # The `dbnl-tei` family (P165): one title of the DBNL public-domain dump
    # (KB, the Netherlands) — DBNL's house TEI.2 flavor ("-//DBNL//DTD TEI.2
    # XML//NL", teixlite; header encodingDesc "DBNL-TEI 1"). None of the held
    # TEI families composes: the P4-era freising/TCP families read their own
    # projects' markup, and DBNL's quirks below are its own.
    #
    # == Grain: the printed page (the DTA mould)
    #
    # DBNL texts are cited by page (dbnl.org/tekst/<id>/_NNNN), every genre
    # from Middle Dutch drama to 19th-century school readers rides one
    # element soup (div chapter/section/act/scene, sp, lg/l, p, table, list),
    # and only a page-grain accumulate-and-flush survives that without
    # silently losing text. Every <pb n> flushes the open page:
    #
    #   p<n>   a print page (n sanitized to [A-Za-z0-9*.-]: "A3r", "*4v",
    #          "t.o.9" — the plate facing page 9, "XII")
    #   f<n>   a manuscript/foliated page (pb @ed or @rend "fol"/"fol.":
    #          "f239vb" — Rubben in the Hulthem manuscript)
    #   p0     text before the first pb
    #
    # A <pb> without @n (rend="hidden", 984 corpus-wide) never flushes. Blank
    # pages mint nothing. Residual duplicate citations disambiguate
    # positionally (":b2"), never quarantine.
    #
    # 21 titles carry no <pb> at all (the Hooft occasional poems, Dousa's
    # odes, the 5.6 MB Witsen letters): those flush per OUTERMOST <div>
    # instead — "d1", "d2", … in document order (text outside any div takes
    # the next ordinal).
    #
    # == The joins (markup is markup — the DTA ¬<lb/> precedent)
    #
    # <c type="shy">-</c><lb/> is the print's line-end word break; <hy>-</hy>
    # its page-end word break ("composi<hy>-</hy></p><pb/>…<p>tiën"). Both
    # drop the hyphen and join the halves with no space; a page break inside
    # the join DEFERS so the whole word lands on the page it starts on. An
    # <hy> after whitespace is a printed dash, not a break ("snijden <hy>-</hy>")
    # and stays as text.
    #
    # == Dropped vs kept
    #
    # <figure> subtrees drop (plates and their DBNL captions — the engraver's
    # apparatus); <interpGrp> drops from the text but its <interp> pairs ride
    # the page's "dbnl_interp" annotation ({type => [values]}: DBNL's own
    # links — primair/secundair person, place and date codes, song tunes,
    # biography and linguistics markers; the text-level group before <body>
    # is the document's own, returned as Result#interps). <note> bodies (the print's foot/
    # margin/end notes and the editions' critical notes, place="krit") ride
    # the page's "notes" annotation ([{n, place, text}]), never the passage
    # text: the medieval titles' notes are the modern editors' apparatus,
    # and a Middle Dutch page must not carry 19th-century Dutch commentary
    # in its text. Everything else (<hi>, <name>, <q>, <speaker>, <stage>,
    # <tune>, <head>, <cell>, …) is transparent reading text; block-element
    # ends contribute a space. Whitespace (NBSP included) collapses; NFC.
    #
    # DBNL applies its editorial interventions silently in the text and
    # lists them in the header (editionStmt corr: "p. 27: 'beminde.' →
    # 'beminde,'"); the list rides metadata "editorial_interventions".
    #
    # == Named entities
    #
    # The files reference HTML entities the DTD would declare (&nbsp;
    # 679,636 corpus-wide, &acirc;, &lsquo;, …) and the DTD is never fetched
    # (no network). Every named reference expands at read time through
    # Nokogiri's HTML4 table plus two ISO/HTML5 names it lacks (&gacute; ǵ,
    # &nacute; ń — 2026-11-08 census: 49 distinct names, all covered); an
    # unknown name is a ParseError, never a silent drop.
    #
    # == Header
    #
    # Mined by a small DOM parse of the <teiHeader> alone (≤ a few KB): the
    # titleStmt title/author/editor, the editionStmt statement (prose — the
    # diplomatic-transcription statement or the INL CD-rom provenance block)
    # and its intervention list, the publicationStmt titelcode idno, the
    # sourceDesc (the transcribed print/manuscript as DBNL describes it, the
    # used copy) and the langUsage language ids. The <ebook>/<pod> blocks are
    # DBNL's empty commercial-edition templates and stay unread.
    class DbnlTeiParser < StreamingTeiParser
      # The two names Nokogiri::HTML4::NamedCharacters lacks (ISO 8879 /
      # HTML5 "gacute"/"nacute"), both seen in the 2026-11-08 corpus.
      EXTRA_ENTITIES = { "gacute" => 0x01F5, "nacute" => 0x0144 }.freeze
      XML_ENTITIES = %w[amp lt gt quot apos].freeze

      Result = Data.define(:header, :units, :grain, :interps)
      Unit = Data.define(:citation, :text, :annotations)

      # Read one title: [header Hash, page/div units, grain (:page | :div)].
      def read(path)
        source = expand_entities(SourceRead.utf8_file(path, label: "dbnl"), path)
        header = Header.new(source, path).call
        grain = source.match?(/<pb\b[^>]*\bn\s*=/) ? :page : :div
        units, interps = extract(StringIO.new(source), path: path, grain: grain)
        Result.new(header: header, units: disambiguate_collisions(units), grain: grain, interps: interps)
      end

      # A read title → a Document (StreamingTeiParser#build_document): the
      # caller decides the language and the metadata from the header and
      # its own register.
      def document(result, urn:, language:, path:, title: nil, metadata: {})
        build_document(result.units, urn: urn, language: language, title: title || result.header["title"],
                                     path: path, metadata: metadata)
      end

      # Every named entity reference expanded to its character (the five XML
      # ones stay references). Public for the census tooling.
      def self.expand_entities(source, path: "(string)")
        source.gsub(/&([A-Za-z][A-Za-z0-9]*);/) do |match|
          name = Regexp.last_match(1)
          next match if XML_ENTITIES.include?(name)

          codepoint = Nokogiri::HTML4::NamedCharacters[name] || EXTRA_ENTITIES[name]
          raise ParseError, "#{path}: unknown named entity &#{name}; (not HTML4/EXTRA_ENTITIES)" unless codepoint

          [codepoint].pack("U")
        end
      end

      private

      def expand_entities(source, path) = self.class.expand_entities(source, path: path)

      def extraction_class = Walker

      def no_passages_message = "no text in <text> (every page empty)"

      # The teiHeader fields (class note), from a DOM parse of the header's
      # own substring. A file without one yields {}.
      class Header
        def initialize(source, path)
          @source = source
          @path = path
        end

        def call
          start = @source.index("<teiHeader")
          finish = @source.index("</teiHeader>")
          return {} unless start && finish

          doc = Nokogiri::XML(@source[start...(finish + "</teiHeader>".length)])
          mine(doc.root)
        end

        private

        def mine(root)
          file_desc = root.at_xpath("fileDesc")
          return {} unless file_desc

          {
            "title" => flat(file_desc.at_xpath("titleStmt/title[@type='main']") ||
                            file_desc.at_xpath("titleStmt/title")),
            "authors" => list(file_desc.xpath("titleStmt/author")),
            "editors" => list(file_desc.xpath("titleStmt/editor")),
            "edition_statement" => edition_statement(file_desc.at_xpath("editionStmt")),
            "editorial_interventions" => list(file_desc.xpath("editionStmt//corr")),
            "dbnl_id" => titelcode(file_desc),
            "source_edition" => presence(file_desc.xpath("sourceDesc/p").map { |p| flat(p) }.compact.join(" ")),
            "used_copy" => flat(file_desc.at_xpath("sourceDesc/bibl/idno[@type='usedcopy']")),
            "lang_usage" => root.xpath("profileDesc/langUsage/language").filter_map { |l| presence(l["id"].to_s.strip) }
          }.reject { |_, value| value.nil? || value == [] }
        end

        # The statement prose without the intervention list (that rides
        # editorial_interventions on its own).
        def edition_statement(node)
          return nil unless node

          copy = node.dup
          copy.xpath(".//respStmt").each(&:remove)
          flat(copy)
        end

        def titelcode(file_desc)
          node = file_desc.at_xpath("publicationStmt/idno[@type='titelcode']") ||
                 file_desc.at_xpath("publicationStmt/idno[not(@type)]")
          flat(node)
        end

        def list(nodes) = nodes.filter_map { |node| flat(node) }

        def flat(node)
          return nil unless node

          presence(Normalize.nfc(node.text.gsub(/[[:space:]]+/, " ").strip))
        end

        def presence(value) = value.nil? || value.empty? ? nil : value
      end

      # The single-pass Reader walk over <text> (class note).
      class Walker < StreamingTeiParser::Walker
        DROPPED = %w[figure].freeze
        BLOCK_ELEMENTS = %w[p head l lg sp speaker stage item list label row cell table tune signed q
                            cit bibl titlepage div].freeze
        FOLIO = /\Afol\.?\s*\z/
        private_constant :DROPPED, :BLOCK_ELEMENTS, :FOLIO

        def initialize(reader:, path:, grain:)
          super(reader: reader, path: path)
          @grain = grain
          @in_text = false
          @drop_depth = nil
          @buffer = +""
          @citation = grain == :page ? "p0" : nil
          @div_depths = []
          @div_ordinal = 0
          @join = false          # a shy/hy break is open: no space, strip the next text
          @breaking = nil        # depth of the open <c type=shy>/<hy> (its hyphen is dropped)
          @pending_page = nil    # a pb seen mid-join
          @note = nil            # [depth, buffer, n, place] while inside a note
          @notes = []
          @interp_group = nil    # depth while inside an interpGrp
          @interps = {}
          @scope = nil           # depth of the open <front>/<body>/<back>
          @doc_interps = {}      # text-level links (the interpGrp before <body>)
          @units = []
        end

        # [units, the document-level DBNL links].
        def call
          @reader.each { |node| process(node) }
          flush
          [@units, @doc_interps.transform_values(&:uniq)]
        end

        private

        def start_element(node)
          name = local_name(node)
          if name == "text" && !@in_text
            @in_text = true unless node.empty_element?
            return
          end
          return unless @in_text && !dropping?

          if DROPPED.include?(name)
            @drop_depth = node.depth unless node.empty_element?
            return
          end
          element(node, name)
        end

        def element(node, name)
          case name
          when "pb" then page_break(node)
          when "lb" then line_break
          when "c" then open_break(node) if node.attribute("type") == "shy"
          when "hy" then open_break(node) if word_running?
          when "note" then open_note(node)
          when "interpGrp" then @interp_group = node.depth unless node.empty_element?
          when "interp" then record_interp(node)
          when "div" then @div_depths << node.depth unless node.empty_element?
          when "front", "body", "back" then @scope ||= node.depth unless node.empty_element?
          end
        end

        def end_element(node)
          name = local_name(node)
          return unless @in_text

          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end
          case name
          when "text" then @in_text = false
          when "note" then close_note(node)
          when "interpGrp" then @interp_group = nil
          when "front", "body", "back" then @scope = nil if @scope == node.depth
          when "c", "hy" then @breaking = nil if @breaking == node.depth
          else
            append_space if BLOCK_ELEMENTS.include?(name)
            close_div(node) if name == "div"
          end
        end

        def text_node(node)
          return unless @in_text && !dropping? && @interp_group.nil?
          return if @breaking # the shy/hy hyphen itself

          value = node.value.to_s
          if @note
            @note[1] << value
            return
          end
          if @join
            value = value.lstrip
            return if value.empty?

            @join = false
          end
          return complete_word(value) if @pending_page

          @buffer << value
        end

        # -- joins -------------------------------------------------------------

        def word_running? = @buffer.match?(/[^[:space:]]\z/)

        def open_break(node)
          @breaking = node.depth unless node.empty_element?
          @join = true
        end

        def line_break
          append_space unless @join
        end

        def append_space
          return if @join
          return @note[1] << " " if @note
          return resume_deferred_page if @pending_page # the broken word ended at a block end

          @buffer << " "
        end

        # The broken word's tail (up to the first whitespace) finishes on the
        # page it started on; then the deferred page opens. A tail split over
        # several text nodes ("tiën<hi>…") keeps deferring.
        def complete_word(value)
          head, separator, tail = value.partition(/[[:space:]]/)
          @buffer << head
          return if separator.empty?

          resume_deferred_page
          @buffer << tail
        end

        # -- pages and divs ----------------------------------------------------

        def page_break(node)
          return unless @grain == :page

          n = node.attribute("n").to_s.gsub(/[^A-Za-z0-9*.-]/, "")
          return if n.empty?

          citation = "#{folio?(node) ? 'f' : 'p'}#{n}"
          if @join || @note
            @pending_page = citation
            return
          end
          flush
          @citation = citation
        end

        def folio?(node)
          [node.attribute("ed"), node.attribute("rend")].any? { |value| value.to_s.strip.match?(FOLIO) }
        end

        def close_div(node)
          return unless @div_depths.last == node.depth

          @div_depths.pop
          flush if @grain == :div && @div_depths.empty?
        end

        # -- notes and interps -------------------------------------------------

        def open_note(node)
          return if node.empty_element? || @note # a nested note rides its outer's buffer

          @note = [node.depth, +"", node.attribute("n"), node.attribute("place")]
        end

        def close_note(node)
          return unless @note && node.depth == @note.first

          _, text, n, place = @note
          @note = nil
          text = text.gsub(/[[:space:]]+/, " ").strip
          unless text.empty?
            @notes << { "n" => presence(n.to_s.strip), "place" => presence(place.to_s.strip),
                        "text" => Normalize.nfc(text) }.compact
          end
          resume_deferred_page
        end

        def resume_deferred_page
          return if @pending_page.nil? || @join || @note

          citation = @pending_page
          @pending_page = nil
          flush
          @citation = citation
        end

        def record_interp(node)
          type = presence(node.attribute("type").to_s.strip)
          value = presence(node.attribute("value").to_s.strip)
          return unless type && value

          ((@scope ? @interps : @doc_interps)[type] ||= []) << value
        end

        # -- flushing ----------------------------------------------------------

        def flush
          text = @buffer
          @buffer = +""
          notes = @notes
          @notes = []
          interps = @interps
          @interps = {}
          unless text.match?(/[^[:space:]]/) # NBSP-only counts as empty (String#strip keeps it)
            # A textless page (a plate, a blank) mints nothing; whatever notes
            # and DBNL links it carried ride the next page that has text.
            @notes = notes
            @interps = interps
            return
          end

          citation = @grain == :page ? @citation : "d#{@div_ordinal += 1}"
          annotations = {}
          annotations["notes"] = notes unless notes.empty?
          annotations["dbnl_interp"] = interps.transform_values(&:uniq) unless interps.empty?
          @units << Unit.new(citation: citation, text: text, annotations: annotations)
        end
      end
    end
  end
end
