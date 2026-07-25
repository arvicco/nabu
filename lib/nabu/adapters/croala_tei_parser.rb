# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one CroALa (Croatiae auctores Latini) TEI P5
    # document — a bespoke parser family (P44-9), SIBLING to SaritParser, not a
    # reuse of it. The compose-an-existing-family bet was REFUTED from the real
    # bytes:
    #
    #   1. CroALa's reading text lives partly in <opener>/<closer>/<signed>
    #      (medieval charters open with a dating clause and close with a
    #      scribal subscription — real running text, not apparatus). SARIT and
    #      every other reading-TEI family capture only <p>/<lg>/<l> and would
    #      SILENTLY DROP those subtrees.
    #   2. Verse carries a SPARSE every-fifth-line running marker (<l n="5">,
    #      <l n="10">, the rest bare) — a print aid, not a per-line address.
    #      Feeding it into SARIT's @n-first citation ladder mints an incoherent
    #      mix of "5"/"10" attribute citations amid v1/v2 ordinals.
    #   3. A document is a flat sequence of unnumbered sibling <div>s (7 poems
    #      in one file, 107 charters in another); SARIT's div stack gives every
    #      such sibling the empty path and collides them into :b2/:b3.
    #
    # So CroALa addresses POSITIONALLY and coherently: a passage is a verse
    # line or a prose block (<p>/<opener>/<closer>), cited by its div path plus
    # a per-div, per-kind ordinal. Same call shape as the other families:
    # #parse(source, urn:, language:, title:, canonical_path:).
    #
    # == The citation scheme (positional, deterministic, stable across parses)
    #
    #   <div-path>.<unit-token>
    #
    # - div-path: each ancestor div contributes ONE component, dot-joined. The
    #   component is the div's @xml:id verbatim when it carries one (the
    #   editor's own anchor — "tr-vd01"), else "d<k>" where k is the div's
    #   1-based position among its siblings. Unnumbered sibling divs therefore
    #   read d1, d2, d3 …; nested divs nest the path (the Supetarski cartulary:
    #   d1.d1.d5). No stripping, no @n (CroALa divs carry none) — pure
    #   structure.
    # - unit-token: "l<k>" for a verse line, "p<k>" for a prose block, k a
    #   1-based ordinal counted PER div PER kind, consumed only by a non-empty
    #   unit (the GRETIL/SARIT rule). Where the sparse @n IS present it
    #   coincides with the line ordinal (both count from the div's first line),
    #   so d1.l5 is exactly the line the source marks n="5"; the @n rides the
    #   passage's "n" annotation for provenance, never the citation.
    #
    # → urn:nabu:croala:albert-i-inscr:d1.p1
    # → urn:nabu:croala:andreis-f-carm-h46:d1.l5   (the source's <l n="5">)
    #
    # Every passage records addressing "structural-ordinal" (honest: this is
    # positional structure, not a canonical reference system), plus the
    # enclosing div's @type and @met and the unit kind, and the line's raw @n
    # when present. Any residual duplicate citation disambiguates positionally
    # (":b2" — the house ddbdp/GRETIL precedent), never quarantines.
    #
    # == Text discipline (canonical means canonical; all shapes on real bytes)
    #
    # Capture only inside <text><body>, per reading unit. <note> (editorial)
    # and <head> (poem/section titles — apparatus, carried nowhere) drop their
    # whole subtree. <lb>, <pb>, <milestone>, <gap> leave a single space.
    # Everything else is transparent reading text: <sic>, <supplied>, <q>,
    # <hi>, <persName>, <signed>, <foreign>, <name>, <date> keep their
    # characters (CroALa encodes editorial supplements and scribal errors in
    # place — reproduced, never "cleaned"). Whitespace runs collapse to one
    # space, ends strip, output is NFC (lat is not NFC-exempt). A unit that
    # flattens to nothing (the empty <p/> placeholders) emits nothing and
    # consumes no ordinal.
    #
    # == Header metadata (the timeline feed)
    #
    # One streaming pass also mines the teiHeader: titleStmt/title (the
    # document title, unless the caller overrides), the author persName, and
    # profileDesc/creation's date + placeName. CroALa spans 976 CE onward and
    # the creation <date> carries machine attributes (@when/@notBefore, and a
    # @period bucket); these ride Document#metadata so the date dimension has an
    # honest feed where present, and is simply absent otherwise.
    #
    # == Streaming
    #
    # The only Nokogiri entry point is Nokogiri::XML::Reader — the corpus's
    # largest file is ~6 MB (over the house >5 MB DOM threshold). One pass per
    # document.
    class CroalaTeiParser
      # Reading units: a verse line, or a prose block. <opener>/<closer> are
      # prose blocks because in CroALa they carry running text (charter dating
      # clauses and scribal subscriptions), not apparatus.
      VERSE_UNITS = %w[l].freeze
      PROSE_UNITS = %w[p opener closer].freeze
      UNIT_ELEMENTS = (VERSE_UNITS + PROSE_UNITS).freeze
      private_constant :VERSE_UNITS, :PROSE_UNITS, :UNIT_ELEMENTS

      # One emitted unit: citation suffix, raw accumulated text, and the
      # provenance annotations mined from its div/line context.
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

      # The house collision tolerance (ddbdp/GRETIL/SARIT precedent):
      # duplicates disambiguate deterministically in document order.
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
        raise ParseError, "#{path}: no citable passages found in <text><body>" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The single-pass Reader state machine. A header phase mines title,
      # author and the creation date/place; a body phase tracks the div stack
      # and captures text inside verse/prose units.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        DROPPED_ELEMENTS = %w[note head].freeze
        SEPARATOR_ELEMENTS = %w[lb pb milestone gap].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS, :SEPARATOR_ELEMENTS

        Result = Data.define(:units, :title, :metadata)

        def initialize(reader:, path:)
          @reader = reader
          @path = path
          @seen_body = false
          @in_body = false
          @drop_depth = nil
          # div stack; the root frame collects the child-div counter for
          # top-level divs and never contributes a path component.
          @div_frames = [{ component: nil, child_divs: 0, verse: 0, prose: 0, type: nil, met: nil }]
          @unit = nil # the open reading unit, or nil
          @units = []
          # header capture
          @header = { title: nil, author: nil, date: nil, when: nil, not_before: nil,
                      period: nil, precision: nil, place: nil, genre: [] }
          @capture = nil # a header field currently accumulating text, or nil
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

          if DROPPED_ELEMENTS.include?(name)
            @drop_depth = node.depth unless node.empty_element?
            return
          end

          case name
          when "div" then open_div(node)
          when *UNIT_ELEMENTS then open_unit(node, name)
          when *SEPARATOR_ELEMENTS then separator
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
          when "div" then close_div
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

        # -- header -----------------------------------------------------------
        #
        # Coarse single-pass capture: the FIRST <title> is titleStmt/title; the
        # first <author>'s persName is the author; profileDesc/creation's
        # <date>/<placeName> feed the timeline. Enough for honest metadata
        # without a second parse of a possibly-6 MB file.

        def header_start(node, name)
          case name
          when "title" then @capture = (@header[:title] ||= +"") if @header[:title].nil?
          when "author" then @in_author = true unless node.empty_element?
          when "persName" then @capture = (@header[:author] ||= +"") if @in_author && @header[:author].nil?
          when "creation" then @in_creation = true unless node.empty_element?
          when "date" then creation_date(node) if @in_creation
          when "placeName" then @capture = (@header[:place] ||= +"") if @in_creation && @header[:place].nil?
          when "keywords" then @in_genre = node.attribute("scheme") == "genre" unless node.empty_element?
          when "term" then start_genre_term if @in_genre
          end
        end

        def header_end(name)
          @capture = nil if %w[title persName placeName date term].include?(name)
          case name
          when "author" then @in_author = false
          when "creation" then @in_creation = false
          when "keywords" then @in_genre = false
          when "term" then finish_genre_term
          end
        end

        def creation_date(node)
          @header[:when] ||= presence(node.attribute("when"))
          @header[:not_before] ||= presence(node.attribute("notBefore"))
          @header[:period] ||= presence(node.attribute("period"))
          @header[:precision] ||= presence(node.attribute("precision"))
          @capture = (@header[:date] ||= +"") if @header[:date].nil?
        end

        def start_genre_term
          @genre_term = +""
          @capture = @genre_term
        end

        def finish_genre_term
          term = presence(@genre_term&.gsub(/[[:space:]]+/, " ")&.strip)
          @header[:genre] << term if term
          @genre_term = nil
        end

        def metadata
          {
            "author" => flatten(@header[:author]),
            "date" => flatten(@header[:date]),
            "date_when" => @header[:when],
            "date_not_before" => @header[:not_before],
            "date_period" => @header[:period],
            "date_precision" => @header[:precision],
            "place" => flatten(@header[:place]),
            "genre" => (@header[:genre].empty? ? nil : @header[:genre])
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
          id = presence(node.attribute("xml:id"))
          component = id || "d#{parent[:child_divs]}"
          frame = { component: component, child_divs: 0, verse: 0, prose: 0,
                    type: presence(node.attribute("type")), met: presence(node.attribute("met")) }
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

          @unit = { tag: name, depth: node.depth, n: presence(node.attribute("n")), text: +"" }
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
            "met" => frame[:met],
            "n" => unit[:n]
          }.compact
        end

        def separator
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
