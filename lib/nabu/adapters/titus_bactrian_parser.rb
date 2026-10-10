# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "titus_avestan_parser"
require_relative "titus_pahlavi_parser"

module Nabu
  module Adapters
    # TITUS Bactrian parser family — the Corpus of Bactrian Texts (N.
    # Sims-Williams; TITUS version J. Gippert, 2010): the Bactrian
    # documents from northern Afghanistan, the letters, lists and
    # accounts, the Buddhist texts and the Tang-i Safedak inscription, in
    # the edition's GREEK-letter transcription of the cursive Bactrian
    # script (ϸ for š, numerals in the Greek manner: ρʹ ιʹ = 110).
    #
    # == Composed from the Pahlavi family, not a copy of it
    #
    # The pages are the same 1990s TITUS machinery as the Pahlavi books:
    # `<!Level N>` header comments (Level 1 collection, 2 genre, 3 text,
    # 4 LINE), machine-generated anchors `Bactr.Corp._Dat.Doc._A_1`. The
    # shared pieces are reused, never duplicated: the severed-UTF-8 repair
    # (TitusPahlaviParser.read_page — the adapter reads through it), the
    # Level-comment marker rewrite (TitusPahlaviParser.mark_levels), the
    # header label reader, the bracket-aware anchor split and the document
    # walk (TitusAvestanParser). What does NOT carry over is the Pahlavi
    # accumulation model (two renderings per section, embedded Avestan
    # runs, the note-neighbour heuristics for body-size quotations): the
    # Bactrian corpus has ONE rendering and a much plainer apparatus, so
    # its line model lives here.
    #
    # == Passage grain: the manuscript line
    #
    # Only a Level-4 ("Line") header opens a section; Levels 1–3 close any
    # open line (lane text outside a line is a structural surprise —
    # quarantine). Line labels are the edition's own and kept verbatim:
    # `1`, `1'` (the second, open copy of a double document — printed in
    # italics), `(2)` (a line-break INSIDE a printed row of a two-column
    # layout), `5+6A`, `30+37` (joined tally fragments). Note sections
    # (`na`, `nb`, … — English apparatus with quoted forms) carry only
    # apparatus lanes and mint nothing; lines that carry only an editorial
    # `nci16` "traces only" likewise mint nothing.
    #
    # == Lanes, by FAMILY at any size (never a literal id table)
    #
    # `gbbk<flavors><size>` — Greek-script Bactrian. Flavor letters
    # (census of 7 real pages, 2026-10-10):
    #   (none) running text;
    #   x      a word BROKEN across the line end — each half is text of its
    #          own line ("ολοβω-" ends line 1, "στογο" opens line 2);
    #   i      italic: the second (open) copy of a double document;
    #   v      a variant / quoted form inside a note — always apparatus.
    # A flavor letter outside {x, i, v} is a NEW lane: quarantine
    # (ParseError), never a silent skip. A SMALL run (size < 16) is a form
    # quoted inside an `nc12` editorial note (all 48 small runs censused
    # sit beside one — the intro's conventions list, the notes): apparatus.
    # A small run with NO note beside it has no known reading — quarantine.
    #
    # Every word is wrapped in a TITUS word-index link
    # `<a id=gbbk16 href="javascript:ci(929,'<UTF-16LE hex>')">`; the one
    # EMPTY link at a line end (its text sits in the following x-flavor
    # span) carries the WHOLE broken word's index form — kept as the line's
    # `line_end_word` (plain letters, `#` for an illegible one), the only
    # place the joined word exists.
    #
    # Upstream sigla ([ ] restorations, ̣ uncertain readings, • illegible
    # letters, { } deletions, \ in-word line breaks, overlines) are
    # canonical text and kept verbatim.
    module TitusBactrianParser
      # One text-bearing manuscript line: +genre+ / +text+ / +line+ the
      # anchor components (+text+ "" on a headerless text — see the
      # adapter); +label+ the header's own word ("Line"); +text_content+
      # NFC; +copy+ "second" when the line is the italic open copy;
      # +line_end_word+ the broken word's index form (nil when none).
      Line = Data.define(:genre, :text, :line, :label, :content, :copy, :line_end_word)

      LANE = /\Agbbk(?<flavor>[a-z]*)(?<size>\d+)\z/
      CONTENT_PREFIX = /\Agbbk/
      TEXT_FLAVORS = %w[x i].freeze
      APPARATUS_FLAVOR = "v"
      NOTE_SPAN = TitusPahlaviParser::NOTE_SPAN
      BODY_SIZE = TitusPahlaviParser::BODY_SIZE
      LINE_LEVEL = 4
      COLLECTION = "Bactr.Corp."
      MARKER = TitusPahlaviParser::MARKER

      # The word-index link's argument: corpus number, UTF-16LE hex.
      INDEX_LINK = /\Ajavascript:ci\(\d+,'(?<hex>(?:\h{4})+)'\)\z/

      # Parse one page's HTML into ordered text-bearing lines. Raises
      # Nabu::ParseError on a structural surprise.
      def self.parse(html)
        raise Nabu::ParseError, "titus-bactrian: page is not valid UTF-8" unless html.valid_encoding?

        doc = Nokogiri::HTML(TitusPahlaviParser.mark_levels(html))
        state = { lines: [], current: nil, break: false, ended: false, lane_cache: {} }
        TitusAvestanParser.walk(doc) { |node| visit(node, state) }
        state[:lines].filter_map { |line| finish(line) }
      end

      def self.visit(node, state)
        if node.element?
          visit_element(node, state)
        elsif node.text?
          return if state[:ended]

          lane = lane_of(node, state[:lane_cache])
          if lane
            accumulate(state, lane, node.text)
          elsif node.text.match?(/\p{Space}/)
            state[:break] = true
          end
        end
      end

      def self.visit_element(node, state)
        case node.name
        when "br" then state[:break] = true
        when "hr" then state[:ended] = true # the page footer
        when MARKER then open_level(node, state) if node["data-kind"] == "level"
        when "a" then record_line_end_word(node, state)
        end
      end

      # A Level-4 header opens a line keyed by its anchor's components;
      # a higher level closes the open line.
      def self.open_level(marker, state)
        level = marker["data-n"].to_i
        unless level == LINE_LEVEL
          state[:current] = nil
          return
        end

        anchor = marker.parent.css("a[name]").map { |a| a["name"] }.first
        raise Nabu::ParseError, "titus-bactrian: a Line header without an anchor" if anchor.nil?

        comps = TitusAvestanParser.split_components(anchor)
        unless comps.size == LINE_LEVEL && comps.first == COLLECTION
          raise Nabu::ParseError, "titus-bactrian: unexpected line anchor #{anchor.inspect}"
        end

        state[:current] = { comps: comps, label: TitusPahlaviParser.header_label(marker),
                            buffer: +"", copy: false, line_end_word: nil }
        state[:lines] << state[:current]
        state[:break] = false
      end

      # The EMPTY word-index link at a line end names the whole broken word.
      def self.record_line_end_word(node, state)
        current = state[:current]
        return if current.nil? || !CONTENT_PREFIX.match?(node["id"].to_s) || !node.text.strip.empty?

        m = INDEX_LINK.match(node["href"].to_s)
        return if m.nil?

        word = [m[:hex]].pack("H*").force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
        current[:line_end_word] = Nabu::Normalize.nfc(word)
      rescue EncodingError
        nil # an undecodable index key is not text — the line keeps its words
      end

      # :text / :italic for a lane text node, nil for excluded markup.
      def self.lane_of(node, cache)
        holder = node.ancestors.find { |a| a.element? && a["id"] }
        return nil if holder.nil?

        cache.fetch(holder.pointer_id) { cache[holder.pointer_id] = classify(holder) }
      end

      def self.classify(holder)
        id = holder["id"].to_s
        return nil unless CONTENT_PREFIX.match?(id)

        m = LANE.match(id)
        flavors = m && m[:flavor].chars
        if m.nil? || !(flavors - TEXT_FLAVORS - [APPARATUS_FLAVOR]).empty?
          raise Nabu::ParseError, "titus-bactrian: unknown content lane #{id.inspect} — classify it before ingesting"
        end
        return nil if flavors.include?(APPARATUS_FLAVOR)
        return nil if m[:size].to_i < BODY_SIZE && quoted_in_note!(holder, id)

        flavors.include?("i") ? :italic : :text
      end

      # A small run beside an `nc12` note is a quoted form (apparatus);
      # one with no note beside it is unclassified — quarantine.
      def self.quoted_in_note!(holder, id)
        span = ([holder] + holder.ancestors.to_a).find { |e| e.element? && e.name == "span" } || holder
        sides = [span.previous_element, span.next_element]
        return true if sides.any? { |e| e && NOTE_SPAN.match?(e["id"].to_s) }

        raise Nabu::ParseError, "titus-bactrian: small-type lane #{id.inspect} outside any editorial note"
      end

      def self.accumulate(state, kind, text)
        current = state[:current]
        if current.nil?
          return if text.strip.empty?

          raise Nabu::ParseError, "titus-bactrian: content text #{text.strip.inspect} outside any Line"
        end

        current[:buffer] << " " if state[:break] && !current[:buffer].empty?
        state[:break] = false
        current[:buffer] << text
        current[:copy] = true if kind == :italic
      end

      def self.finish(line)
        content = TitusPahlaviParser.clean(line[:buffer])
        return nil if content.empty?

        _collection, genre, text, number = line[:comps]
        Line.new(genre: genre, text: text, line: number, label: line[:label], content: content,
                 copy: line[:copy] ? "second" : nil, line_end_word: line[:line_end_word])
      end
    end
  end
end
