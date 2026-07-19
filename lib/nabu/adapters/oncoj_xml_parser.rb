# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The oncoj-xml family (P32-2): the Oxford-NINJAL Corpus of Old Japanese's
    # per-text tree XML (github.com/ONCOJ/data xml/, "TEI compatible" per the
    # upstream README but a corpus-specific application: a namespace-less
    # <TEI> shell whose <ab type="transliteration"> holds a constituency tree
    # of typed <s>/<cl>/<phr>/<w> nodes over <c> writing segments, with the
    # original man'yōgana script riding line-break markers as lb/@corresp).
    #
    # == The line is the unit
    #
    # The corpus's own line markers (<lb id corresp>) partition the whole
    # token stream in document order — robust against every censused tree
    # quirk (the file without an <s> wrapper, tokens sitting directly under
    # a multi-sentence wrapper, embedded quotation sentences), where any
    # sentence-based segmentation would lose material. Each line pairs the
    # editors' romanized analysis (element content — the layer upstream
    # itself names "transliteration") with the attested man'yōgana line
    # (@corresp, 33,192/33,192 lines censused). Four lines corpus-wide carry
    # man'yōgana but no tokens at all (upstream's unanalyzed cruxes —
    # MYS.10.2033 ×2, MYS.12.2917, MYS.20.4372); they yield token-less
    # lines and the caller keeps them honestly. Two more one-off shapes are
    # handled below: the line break INSIDE a word (KK.6) and the word-less
    # bare <c> segments (MYS.4.655).
    #
    # == Tokens
    #
    # - A LEAF <w> (no child <w>) is a token: form = its <c> texts joined,
    #   pos = @type, lemma_id = @lemma (115,515/115,525 leaves censused),
    #   segments = per-<c> {text, script} — script is the corpus's honest
    #   writing-status vocabulary (log/phon/nlog/phon-kun/phon-on/plog/
    #   null/ill and the one upstream "phonon" typo), carried verbatim.
    #   <c type="null"> segments write the corpus's literal "*" (null
    #   realizations); "xxx" forms are upstream's illegibility marks.
    # - A lemma-bearing NON-leaf <w> (a compound: titipapa above titi+papa)
    #   mints a token too — form = all descendant <c> text, compound: true,
    #   emitted BEFORE its parts (pre-order) — so compound lemmas join the
    #   lemma index beside their members. Censused: no <w> mixes direct <c>
    #   and <w> children.
    #
    # == Line ids
    #
    # Upstream lb ids ride verbatim (12 files have skips/out-of-order runs —
    # they are citation, not sequence). The two censused files with
    # DUPLICATE lb ids (MYS.3.276b, MYS.5.903) re-mint repeats with a
    # stable file-order "-b"/"-c" suffix (the starling collision precedent);
    # the verbatim id stays on the line record.
    class OncojXmlParser
      # One corpus line: +id+ = the (possibly re-minted) citation id,
      # +upstream_id+ = lb/@id verbatim, +manyogana+ = lb/@corresp verbatim,
      # +tokens+ = Token records in pre-order.
      Line = Data.define(:id, :upstream_id, :manyogana, :tokens)

      # One analyzed word. +segments+ is nil for compound tokens (segments
      # belong to leaves); +lemma_id+ is nil for the censused lemma-less
      # leaves (illegibility marks).
      Token = Data.define(:form, :pos, :lemma_id, :segments, :compound)

      # The re-mint suffixes for duplicate lb ids, in file order after the
      # plain first occurrence. Two files, one repeat each, censused — the
      # alphabet is deliberately longer than reality needs.
      DUPLICATE_SUFFIXES = ("b".."z").to_a.freeze

      Parsed = Data.define(:text_id, :lines)

      # Parse one per-text file. Returns Parsed; raises Nabu::ParseError on
      # malformed XML, a missing/empty <ab>, a body id drifting from the
      # filename stem, or a token preceding the first line marker (censused
      # zero — loud beats silent loss).
      def read(path)
        doc = Nokogiri::XML(File.read(path), &:strict)
        text_id = body_id!(doc, path)
        ab = doc.at_xpath("//ab")
        raise Nabu::ParseError, "#{path}: no <ab> transliteration block" if ab.nil?

        Parsed.new(text_id: text_id, lines: collect_lines(ab, path))
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed XML: #{e.message}"
      end

      private

      def body_id!(doc, path)
        body = doc.at_xpath("//body")
        id = body && body["xml:id"]
        stem = File.basename(path, ".xml")
        return id if id == stem

        raise Nabu::ParseError,
              "#{path}: body xml:id #{id.inspect} does not match the filename stem #{stem.inspect}"
      end

      def collect_lines(block, path)
        builder = LineBuilder.new(path)
        walk(block, builder)
        builder.lines
      end

      # Pre-order walk: lb markers open lines, <w> subtrees mint tokens,
      # everything else is structure to descend through. A bare <c> outside
      # any <w> (censused: MYS.4.655 only — four word-less segments on an
      # unanalyzed line) mints a pos-less, lemma-less token so its text is
      # never lost.
      def walk(node, builder)
        node.element_children.each do |child|
          case child.name
          when "lb" then builder.open_line(id: child["id"].to_s, manyogana: child["corresp"].to_s)
          when "w" then emit_word(child, builder)
          when "c"
            builder.add(Token.new(form: child.text, pos: nil, lemma_id: nil,
                                  segments: [{ text: child.text, script: child["type"].to_s }],
                                  compound: false))
          else walk(child, builder)
          end
        end
      end

      def emit_word(word, builder)
        children = word.element_children.select { |child| child.name == "w" }
        if children.empty?
          emit_leaf(word, builder)
          return
        end
        if word["lemma"]
          builder.add(Token.new(form: word.xpath(".//c").map(&:text).join, pos: word["type"].to_s,
                                lemma_id: word["lemma"], segments: nil, compound: true))
        end
        # An lb may sit between compound members: walk the full child list so
        # line boundaries inside a <w> keep their place.
        walk(word, builder)
      end

      # A leaf word is one token on the line open where the word STARTS. An
      # lb may fall between its <c> segments (censused once corpus-wide:
      # KK.6 adisikwi|takapwikwone straddles lines 8/9) — the token stays
      # whole on its starting line and the interior lb opens the next line
      # AFTER it, so following tokens land where they belong.
      def emit_leaf(word, builder)
        segments = []
        interior_lbs = []
        word.element_children.each do |child|
          case child.name
          when "c" then segments << { text: child.text, script: child["type"].to_s }
          when "lb" then interior_lbs << child
          end
        end
        builder.add(Token.new(form: segments.map { |segment| segment[:text] }.join,
                              pos: word["type"].to_s, lemma_id: word["lemma"],
                              segments: segments, compound: false))
        interior_lbs.each { |lb| builder.open_line(id: lb["id"].to_s, manyogana: lb["corresp"].to_s) }
      end

      # Accumulates lines in document order and re-mints duplicate lb ids.
      class LineBuilder
        def initialize(path)
          @path = path
          @records = []
          @seen = Hash.new(0)
        end

        def open_line(id:, manyogana:)
          citation = mint(id)
          @records << { id: citation, upstream_id: id, manyogana: manyogana, tokens: [] }
        end

        def add(token)
          if @records.empty?
            raise Nabu::ParseError, "#{@path}: token #{token.form.inspect} precedes the first <lb> marker"
          end

          @records.last[:tokens] << token
        end

        def lines
          @records.map { |record| Line.new(**record) }
        end

        private

        def mint(id)
          nth = @seen[id]
          @seen[id] += 1
          return id if nth.zero?

          suffix = DUPLICATE_SUFFIXES.fetch(nth - 1) do
            raise Nabu::ParseError,
                  "#{@path}: lb id #{id.inspect} repeats more than #{DUPLICATE_SUFFIXES.size + 1} times"
          end
          "#{id}-#{suffix}"
        end
      end
    end
  end
end
