# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "titus_avestan_parser"
require_relative "titus_pahlavi_parser"

module Nabu
  module Adapters
    # TITUS Khotanese parser family — the Corpus of Khotanese Saka Texts on
    # TITUS (khotsNNN.htm / khotNNNN.htm, one text per page). The same
    # frame-based machinery as the Pahlavi books — `<!Level N>` header
    # comments on machine-generated `<A NAME>` anchors — composed from the
    # Pahlavi family's pieces (the comment→marker rewrite, the header label,
    # the whitespace/NFC clean; pages are read through
    # TitusPahlaviParser.read_page, the severed-UTF-8 repair) and the
    # Avestan family's walk and anchor splitter. What differs is the lane
    # vocabulary, so the family is its own (a Pahlavi lane test would
    # exclude every Khotanese word).
    #
    # == Levels (census 2026-10-10, ten pages across all seven books)
    #
    #   Level 1  Text Collection  Khot.
    #   Level 2  Book             KBT / KT1–KT5 / Zamb. (on a book's first page)
    #   Level 3  Text             1, 10a, Si, 53a, 360/11.6a …
    #   Level 4  Paragraph        the folio side (134r, 1a, 5v) — absent in
    #                             many texts: the anchor then carries an
    #                             EMPTY component (Khot._KT3_53a__1)
    #   Level 5  Line             the manuscript line — in the Book of
    #                             Zambasta the verse, whose unnumbered second
    #                             line (a bare <BR> + lane run) continues it
    #
    # No `<!XLevel>` headers occur. Every Level header opens a section keyed
    # by the first N components of its anchor (a header repeating the open
    # section's key continues it); only sections that carry lane text
    # survive, which in practice are the Lines.
    #
    # == Lanes, classified by FAMILY at any size
    #
    #   isks<size>      Khotanese — the text (`isks16` on every censused
    #                   page; any flavor letter after `isks` is a new lane)
    #   iosk<size>      Sanskrit — a work's Sanskrit title in a HEADING
    #                   BLOCK (below; KBT 1 "Sūraṃgama-samādhi-sūtra",
    #                   `iosk22`); mined as metadata by the adapter, never
    #                   text. Outside a heading block, inside a Line, it
    #                   would be Sanskrit TEXT, a lane this family has never
    #                   seen — quarantine.
    #   voc<size>       English title words and the manuscript siglum
    #                   ("Khadaliq 1.13", "P 2896") — heading matter, mined
    #                   by the adapter; outside the vocabulary
    #
    # Any other `i<letters><digits>` id is a TITUS script/language lane this
    # family does not know — ParseError (quarantine), never a silent skip,
    # inside a heading block too. `h*`, `n16`, `title`, `textdescr`, `titus`
    # are layout and the editorial header.
    #
    # == Heading blocks (census 2026-10-10, all 1,648 pages)
    #
    # A `<DIV Align=CENTER>` carrying lane runs is a text HEADING — Bailey's
    # title + siglum: KBT pages 1–35 each CLOSE with the next text's heading
    # (after the last Line; 22 of them with a Sanskrit `iosk22` title, four
    # with Khotanese proper names in `isks16` — "Verses of Prince
    # Tcūṃ-Ttehi"), and khots001 also OPENS with its own. Every lane run
    # inside one (46 voc, 23 iosk, 4 isks — no other lane) is heading
    # matter: never Line text (the isks names used to leak into the page's
    # last Line). The adapter attributes each block to its text.
    #
    # Text is verbatim: punctuation (`//`, `,`, `.`, `:`), verse numbers
    # inside the lane, hyphenated compounds. A line break or any
    # whitespace-bearing non-lane text between lane runs becomes one space.
    module TitusKhotaneseParser
      # One text-bearing section: +components+ the raw anchor components
      # (empties preserved), +level+ / +label+ the header's ("Line"), +text+
      # NFC.
      Line = Data.define(:components, :level, :label, :text)

      KHOTANESE_LANE = /\Aisks(?<flavor>[a-z]*)(?<size>\d+)\z/
      SANSKRIT_LANE = /\Aiosk\d+\z/
      CONTENT_PREFIX = /\Ai[a-z]+\d+\z/

      # The Line level (censused: every text-bearing header is Level 5).
      LINE_LEVEL = 5

      # Parse one page's HTML into ordered text-bearing sections. Raises
      # Nabu::ParseError on a structural surprise (invalid UTF-8, lane text
      # before any header, an unknown content lane).
      def self.parse(html)
        raise Nabu::ParseError, "titus-khotanese: page is not valid UTF-8" unless html.valid_encoding?

        doc = Nokogiri::HTML(TitusPahlaviParser.mark_levels(html))
        state = { sections: [], current: nil, break: false, ended: false, lane_cache: {} }
        TitusAvestanParser.walk(doc) { |node| visit(node, state) }
        state[:sections].filter_map { |section| finish(section) }
      end

      def self.visit(node, state)
        if node.element?
          case node.name
          when "br" then state[:break] = true
          when "hr" then state[:ended] = true # the page footer
          when TitusPahlaviParser::MARKER then open_section(node, state) if node["data-kind"] == "level"
          end
        elsif node.text? && !state[:ended]
          lane = lane_of(node, state[:lane_cache])
          if lane == :khotanese
            accumulate(state, node.text)
          elsif lane == :sanskrit
            sanskrit_run!(state, node)
          elsif node.text.match?(/\p{Space}/)
            state[:break] = true
          end
        end
      end

      def self.open_section(marker, state)
        anchor = marker.parent.at_css("a[name]")
        return if anchor.nil?

        level = marker["data-n"].to_i
        comps = TitusAvestanParser.split_components(anchor["name"]).first(level)
        return if state[:current] && state[:current][:comps] == comps

        state[:current] = { comps: comps, level: level, label: TitusPahlaviParser.header_label(marker),
                            text: +"" }
        state[:sections] << state[:current]
        state[:break] = false
      end

      # :khotanese / :sanskrit for a lane text node, nil for excluded
      # markup and for any lane run inside a heading block (heading matter,
      # mined by the adapter); an unknown content-lane id raises, heading
      # block or not. Cached per lane holder.
      def self.lane_of(node, cache)
        holder = node.ancestors.find { |a| a.element? && a["id"] }
        return nil if holder.nil?

        cache.fetch(holder.pointer_id) do
          lane = classify(holder["id"])
          cache[holder.pointer_id] = heading_block?(holder) ? nil : lane
        end
      end

      def self.heading_block?(node)
        node.ancestors.any? { |a| a.element? && heading_div?(a) }
      end

      # A centered DIV — the heading block's frame (also used by the adapter).
      def self.heading_div?(element)
        element.name == "div" && element["align"].to_s.casecmp?("center")
      end

      def self.classify(id)
        if (m = KHOTANESE_LANE.match(id))
          return :khotanese if m[:flavor].empty?

          unknown_lane!(id)
        elsif SANSKRIT_LANE.match?(id) then :sanskrit
        elsif CONTENT_PREFIX.match?(id) then unknown_lane!(id)
        end
      end

      def self.unknown_lane!(id)
        raise Nabu::ParseError, "titus-khotanese: unknown content lane #{id.inspect} — classify it before ingesting"
      end

      # A Sanskrit run before the first Line is header matter (the adapter
      # mines heading blocks); inside a Line, outside any heading block, it
      # would be text in an unseen lane.
      def self.sanskrit_run!(state, node)
        current = state[:current]
        return if current.nil? || current[:level] < LINE_LEVEL || node.text.strip.empty?

        id = node.ancestors.find { |a| a.element? && a["id"] }["id"]
        raise Nabu::ParseError,
              "titus-khotanese: Sanskrit lane #{id.inspect} inside a line — classify it before ingesting"
      end

      def self.accumulate(state, text)
        current = state[:current]
        if current.nil?
          return if text.strip.empty?

          raise Nabu::ParseError, "titus-khotanese: content text #{text.strip.inspect} before any citation header"
        end

        current[:text] << " " if state[:break] && !current[:text].empty?
        state[:break] = false
        current[:text] << text
      end

      def self.finish(section)
        text = TitusPahlaviParser.clean(section[:text])
        return nil if text.empty?

        Line.new(components: section[:comps], level: section[:level], label: section[:label], text: text)
      end
    end
  end
end
