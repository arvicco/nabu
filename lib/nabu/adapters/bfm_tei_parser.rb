# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one BFM (Base de français médiéval, BFM2022) TEI P5
    # document — a bespoke parser family (P45-4), SIBLING to CroalaTeiParser,
    # not a reuse of it. The compose-an-existing-family bet was REFUTED from
    # the real bytes:
    #
    #   1. BFM verse lines are <lb/> MILESTONES inside <ab type|rend="gv">
    #      / <ab rend="strophe"> verse groups, not <l> containers. croala-tei
    #      (and every container-based reading-TEI family) folds <lb> to a
    #      space — the whole 625-line Vie de saint Alexis would collapse into
    #      129 strophe blobs, Fauvel's 3,280 verses into a handful of <ab>s.
    #   2. Roughly half the corpus is TOKENIZED: every word is a <w> element
    #      (some with @lemma/@type morphosyntax, some bare), so the reading
    #      text needs boundary reconstruction — elision joins ("d'" + "ist" →
    #      "d'ist"), punctuation attach-left ("salvament" + "," →
    #      "salvament,") — that no held family performs.
    #   3. The apparat critique rides INLINE as <note resp="#eds"> between
    #      word tokens, plus editorial-French <head xml:lang="fr"> section
    #      titles; both must drop as subtrees (they are modern French
    #      apparatus — and the CC BY-NC-SA layer of the 8 nc-flagged files;
    #      see the D45-c note on the adapter).
    #
    # == Passage grain (from the corpus's own encoding)
    #
    # - <ab> in <body> is a VERSE GROUP (type="gv"/rend="gv"/rend="strophe" on
    #   every sampled file): each stretch between <lb/> milestones is one
    #   verse-line passage. Line ordinals count per enclosing div across
    #   sibling strophes, so they coincide with the edition's continuous
    #   numbering where upstream carries one (<lb ed="norm" n>, Alexis 1–625;
    #   plain <lb n>, Nabaret 1–48).
    # - <p> in <body> is a PROSE BLOCK: one passage per block (the Règle's
    #   chapters, the Serments' oaths); <lb> inside prose is a facsimile line
    #   break (page-relative @n, restarts per page) and folds to a space.
    # - <head> WITHOUT a foreign @xml:lang is original reading text (chapter
    #   rubrics: "Chapitre des gerfaux") → its own block passage; <head
    #   xml:lang="fr"> is the editor's modern section title → dropped.
    #
    # == The citation scheme (positional, deterministic, stable across parses)
    #
    #   <div-path>.<unit-token>
    #
    # - div-path: each ancestor div contributes one dot-joined component —
    #   @xml:id verbatim when present, else "d<@n>" with @n sanitized to
    #   [A-Za-z0-9_-] (the corpus's own chapter/laisse numbers: d49, dI),
    #   else "d<k>" by 1-based sibling position.
    # - unit-token: "l<k>" verse line / "p<k>" prose block / "h<k>" rubric
    #   head, k counted per div per kind, consumed only by a non-empty unit
    #   (the house GRETIL/SARIT rule). Duplicates disambiguate ":b2" in
    #   document order (ddbdp precedent), never quarantine.
    #
    # → urn:nabu:bfm:nabaret:d1.l1
    # → urn:nabu:bfm:RegleSBenCotton:d49.p1
    #
    # == Text discipline (canonical means canonical; all rules from real bytes)
    #
    # Capture only inside <text><body>. Dropped subtrees: <note> (editorial
    # apparatus), <figure> (editorial figure descriptions), <del> (scribal
    # deletions — <subst> then reads its <add>), foreign-language <head>, and
    # — inside <choice> only — <sic>/<orig>/<abbr>, so a choice reads its
    # editorial <corr>/<expan>/<reg> ("Do<choice><sic>m</sic><corr>nn</corr>
    # </choice>ent" → "Donnent") while STANDALONE <sic>/<orig> stay verbatim
    # reading text. <pb>, <cb>, <milestone>, <space>, <gap> and prose <lb>
    # fold to a single space. Everything else is transparent: <q>, <s>, <hi>,
    # <g> (decorated initials carry their letter), <ex>, <supplied>,
    # <surplus>, <add>, <num>, <seg>, <mentioned>, <quote>. Whitespace runs
    # collapse to one space, ends strip, output is NFC (fro is not
    # NFC-exempt).
    #
    # == Tokens (the fro lemma lane; registry lemma_tier: silver)
    #
    # Where a unit's <w> tokens carry @lemma, the passage records annotations
    # "tokens": [{"form","lemma","pos"}] in reading order. Punctuation tokens
    # (@type PON*) and upstream's explicit "no_lem" keep form/pos but no
    # "lemma" key, so the silver lemma index never mints bogus lemmas (the
    # GLAUx/PROIEL discipline). Untokenized and unlemmatized texts mint no
    # tokens annotation at all.
    #
    # == Header metadata (the timeline feed)
    #
    # One pass also mines the teiHeader: <title type="main">, the first
    # <author>, the composition date (<date type="compo"> @when/@notBefore/
    # @notAfter + display text — every BFM text is dated, 842 onward), the
    # declared language (<language @ident> — "fro" on all 219 files),
    # the author's dialect region, the domaine/genre/forme keywords and the
    # in-file <licence @target>. These ride Document#metadata.
    #
    # == Streaming
    #
    # The only Nokogiri entry point is Nokogiri::XML::Reader — the corpus's
    # largest file (qgraal_cm.xml) is ~6.5 MB, over the house >5 MB DOM
    # threshold. One pass per document.
    class BfmTeiParser
      def parse(source, urn:, language:, title: nil, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        extraction = extract(source, path: path)
        units = disambiguate_collisions(extraction.units)
        build_document(units, urn: urn, language: extraction.language || language,
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

      # The house collision tolerance (ddbdp/GRETIL/croala precedent):
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

      # One emitted unit: citation suffix, raw accumulated text, provenance
      # annotations (including the tokens lane where lemmas exist).
      Unit = Data.define(:citation, :text, :annotations)
      private_constant :Unit

      # The single-pass Reader state machine: a header phase mines the
      # metadata; a body phase tracks the div stack, blocks and (for verse
      # groups) the <lb>-milestone segments.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        # Whole-subtree drops: editorial apparatus and scribal deletions.
        DROPPED_ELEMENTS = %w[note figure del].freeze
        # Inside <choice> only: the un-preferred siblings of corr/expan/reg.
        CHOICE_DROPPED_ELEMENTS = %w[sic orig abbr].freeze
        # Layout marks that fold to a single space.
        SEPARATOR_ELEMENTS = %w[pb cb milestone space gap].freeze
        # Verse-line ordinals coincide with these upstream numbering systems.
        PUNCTUATION_POS = /\APON/
        NO_LEMMA = "no_lem"
        LANGUAGE_SHAPE = /\A[a-z]{2,3}(-[A-Za-z0-9]{1,8})*\z/
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS,
                         :CHOICE_DROPPED_ELEMENTS, :SEPARATOR_ELEMENTS,
                         :PUNCTUATION_POS, :NO_LEMMA, :LANGUAGE_SHAPE

        Result = Data.define(:units, :title, :language, :metadata)

        def initialize(reader:, path:)
          @reader = reader
          @path = path
          @seen_body = false
          @in_body = false
          @drop_depth = nil
          @choice_depth = 0
          # div stack; the root frame collects the child-div counter for
          # top-level divs and never contributes a path component.
          @div_frames = [root_frame]
          @block = nil     # the open block (p/ab/head), or nil
          @segment = nil   # the open text segment within the block, or nil
          @word = nil      # the open <w> token, or nil
          @units = []
          @header = { title: nil, title_fallback: nil, author: nil, date: nil,
                      date_when: nil, date_not_before: nil, date_not_after: nil,
                      language: nil, dialect: nil, license_url: nil,
                      domaine: nil, genre: nil, forme: nil }
          @capture = nil   # [key] a header field currently accumulating text
          @term_type = nil
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no <text><body> found" unless @seen_body

          Result.new(units: @units, title: flatten(@header[:title] || @header[:title_fallback]),
                     language: header_language, metadata: metadata)
        end

        private

        def root_frame
          { component: nil, child_divs: 0, verse: 0, prose: 0, heads: 0, type: nil, n: nil }
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
          name = local_name(node)
          return enter_body(node) if name == "body" && !@in_body
          return header_start(node, name) unless @seen_body
          return unless @in_body
          return if dropping?
          return if drop_subtree?(node, name)

          case name
          when "div" then open_div(node)
          when "p", "ab" then open_block(node, name)
          when "head" then open_head(node)
          when "lb" then line_break(node)
          when "choice" then @choice_depth += 1 unless node.empty_element?
          when "w" then open_word(node)
          when *SEPARATOR_ELEMENTS then separator
          end
        end

        def end_element(node)
          name = local_name(node)
          return header_end(name) unless @seen_body
          return unless @in_body || name == "body"

          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end

          case name
          when "body" then close_body
          when "div" then close_div
          when "p", "ab", "head" then close_block(node, name)
          when "choice" then @choice_depth -= 1 if @choice_depth.positive?
          when "w" then close_word
          end
        end

        def text_node(node)
          value = node.value.to_s
          if !@seen_body
            @capture << value if @capture
          elsif @in_body && !dropping? && @segment
            append_text(value)
          end
        end

        # -- header -----------------------------------------------------------

        def header_start(node, name)
          case name
          when "title" then start_title(node)
          when "author" then start_author(node)
          when "date" then composition_date(node)
          when "language" then @header[:language] ||= presence(node.attribute("ident"))
          when "region" then start_dialect(node)
          when "licence" then @header[:license_url] ||= presence(node.attribute("target"))
          when "term" then start_term(node)
          end
        end

        def start_title(node)
          return if node.empty_element?

          if node.attribute("type") == "main"
            @capture = (@header[:title] ||= +"") if @header[:title].nil?
          elsif @header[:title_fallback].nil?
            @capture = (@header[:title_fallback] ||= +"")
          end
        end

        def start_author(node)
          return if node.empty_element? || !@header[:author].nil?

          @capture = (@header[:author] ||= +"")
        end

        # <date type="compo"> carries the composition envelope every BFM text
        # is catalogued under (the timeline feed); other date types (ms,
        # compo_periode…) are ignored.
        def composition_date(node)
          return unless node.attribute("type") == "compo"
          return unless @header[:date].nil?

          @header[:date_when] = presence(node.attribute("when"))
          @header[:date_not_before] = presence(node.attribute("notBefore"))
          @header[:date_not_after] = presence(node.attribute("notAfter"))
          @capture = (@header[:date] ||= +"") unless node.empty_element?
        end

        def start_dialect(node)
          return if node.empty_element?
          return unless node.attribute("type") == "dialecte_auteur"
          return unless @header[:dialect].nil?

          @capture = (@header[:dialect] ||= +"")
        end

        def start_term(node)
          return if node.empty_element?

          type = node.attribute("type")
          return unless %w[domaine genre forme].include?(type)

          key = type.to_sym
          return unless @header[key].nil?

          @term_type = key
          @capture = (@header[key] ||= +"")
        end

        def header_end(name)
          @capture = nil if %w[title author date region term language].include?(name)
          @term_type = nil if name == "term"
        end

        def header_language
          ident = flatten(@header[:language])
          ident if ident&.match?(LANGUAGE_SHAPE)
        end

        def metadata
          {
            "author" => flatten(@header[:author]),
            "date" => flatten(@header[:date]),
            "date_when" => @header[:date_when],
            "date_not_before" => @header[:date_not_before],
            "date_not_after" => @header[:date_not_after],
            "dialect" => flatten(@header[:dialect]),
            "domaine" => flatten(@header[:domaine]),
            "genre" => flatten(@header[:genre]),
            "forme" => flatten(@header[:forme]),
            "license_url" => @header[:license_url]
          }.compact
        end

        # -- body: div context ------------------------------------------------

        def enter_body(node)
          @seen_body = true
          @capture = nil
          @in_body = !node.empty_element?
        end

        def close_body
          @in_body = false
        end

        # Component: the div's own @xml:id, else its own number ("d49" for
        # <div type="chapter" n="49">, "dI" for a laisse), else pure position.
        def open_div(node)
          parent = @div_frames.last
          parent[:child_divs] += 1
          id = presence(node.attribute("xml:id"))
          n = presence(node.attribute("n"))
          component = id || (n ? "d#{sanitize(n)}" : "d#{parent[:child_divs]}")
          frame = { component: component, child_divs: 0, verse: 0, prose: 0, heads: 0,
                    type: presence(node.attribute("type")), n: n }
          @div_frames << frame unless node.empty_element?
        end

        def close_div
          @div_frames.pop if @div_frames.size > 1
        end

        def div_path
          @div_frames.filter_map { |frame| frame[:component] }.join(".")
        end

        # -- body: blocks and segments ----------------------------------------

        def open_block(node, name)
          return if @block || node.empty_element? # nested blocks stay transparent

          @block = { tag: name, depth: node.depth, verse: name == "ab",
                     n: presence(node.attribute("n")) }
          open_segment(line_n: nil)
        end

        # <head xml:lang="fr"> is the editor's modern section title —
        # apparatus, dropped whole. A <head> in the document's own language
        # (chapter rubrics) is reading text and mints its own block.
        def open_head(node)
          return if @block

          lang = presence(node.attribute("xml:lang"))
          if lang && lang != (header_language || "fro")
            @drop_depth = node.depth unless node.empty_element?
            return
          end
          return if node.empty_element?

          @block = { tag: "head", depth: node.depth, verse: false, n: presence(node.attribute("n")) }
          open_segment(line_n: nil)
        end

        def close_block(node, name)
          return unless @block && @block[:tag] == name && @block[:depth] == node.depth

          close_segment
          @block = nil
        end

        # A <lb> milestone inside a verse group closes the running line and
        # opens the next; inside prose it is a facsimile line break → space.
        def line_break(node)
          return unless @block && @segment

          if @block[:verse]
            close_segment
            open_segment(line_n: presence(node.attribute("n")))
          else
            separator
          end
        end

        def open_segment(line_n:)
          @segment = { text: +"", tokens: [], line_n: line_n }
        end

        def close_segment
          segment = @segment
          @segment = nil
          @word = nil
          return if segment.nil? || segment[:text].strip.empty?

          frame = @div_frames.last
          token = unit_token(frame)
          path = div_path
          citation = path.empty? ? token : "#{path}.#{token}"
          @units << Unit.new(citation: citation, text: segment[:text],
                             annotations: annotations_for(segment, frame))
        end

        def unit_token(frame)
          if @block[:verse]
            "l#{frame[:verse] += 1}"
          elsif @block[:tag] == "head"
            "h#{frame[:heads] += 1}"
          else
            "p#{frame[:prose] += 1}"
          end
        end

        def annotations_for(segment, frame)
          {
            "addressing" => "structural-ordinal",
            "unit" => unit_kind,
            "div_type" => frame[:type],
            "div_n" => frame[:n],
            "block_n" => @block[:n],
            "n" => segment[:line_n] || (@block[:verse] ? nil : @block[:n]),
            "tokens" => tokens_annotation(segment)
          }.compact
        end

        def unit_kind
          return "l" if @block[:verse]

          @block[:tag] == "head" ? "h" : "p"
        end

        def tokens_annotation(segment)
          tokens = segment[:tokens]
          tokens if tokens.any? { |token| token.key?("lemma") }
        end

        # -- body: <w> token reconstruction -----------------------------------

        def open_word(node)
          return unless @segment
          return if node.empty_element?

          @word = { boundary_pending: true, form: +"",
                    pos: presence(node.attribute("type")),
                    lemma: presence(node.attribute("lemma")) }
        end

        def close_word
          word = @word
          @word = nil
          return unless word && @segment

          token = { "form" => flatten(word[:form]) }.compact
          return if token.empty?

          token["pos"] = word[:pos] if word[:pos]
          token["lemma"] = word[:lemma] if lemma_worthy?(word)
          @segment[:tokens] << token
        end

        # Punctuation (@type PON*) and upstream's explicit "no_lem" filler
        # never feed the lemma lane (the GLAUx/PROIEL clean-pool discipline).
        def lemma_worthy?(word)
          word[:lemma] && word[:lemma] != NO_LEMMA && !word[:pos]&.match?(PUNCTUATION_POS)
        end

        # First text of a <w> decides the boundary against the accumulated
        # segment: punctuation attaches left ("salvament" + "," →
        # "salvament,"), an elided predecessor absorbs the word ("d'" +
        # "ist" → "d'ist"), anything else gets a space.
        def append_text(value)
          return @segment[:text] << value if @word.nil?
          # Whitespace-only nodes inside a <w> are XML formatting (the
          # indentation around an in-word <choice>), never token text.
          return if value.strip.empty?

          @word[:form] << value
          if @word[:boundary_pending]
            apply_word_boundary(value)
          else
            @segment[:text] << value
          end
        end

        def apply_word_boundary(value)
          @word[:boundary_pending] = false
          buffer = @segment[:text]
          stripped = buffer.rstrip
          joined = stripped.empty? || value.start_with?(",", ".") || stripped.end_with?("'", "’")
          buffer.replace(joined ? stripped : "#{stripped} ")
          buffer << value
        end

        def separator
          @segment[:text] << " " if @segment
        end

        # -- helpers ----------------------------------------------------------

        def drop_subtree?(node, name)
          droppable = DROPPED_ELEMENTS.include?(name) ||
                      (@choice_depth.positive? && CHOICE_DROPPED_ELEMENTS.include?(name))
          return false unless droppable

          @drop_depth = node.depth unless node.empty_element?
          true
        end

        def dropping? = !@drop_depth.nil?

        def sanitize(value)
          value.gsub(/[^A-Za-z0-9_-]/, "-")
        end

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
