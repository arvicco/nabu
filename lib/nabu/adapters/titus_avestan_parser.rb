# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"

module Nabu
  module Adapters
    # TITUS Avestan corpus parser family (P43-2). The TITUS Avesta is served as
    # a frame-based site of sequential HTML pages (avest001.htm, avest002.htm,
    # …), each a labeled hierarchy — Book / Chapter / Paragraph / Verse —
    # rendered as 1990s-era, deliberately-broken HTML: `<span id=hN>` headers,
    # each holding an `<A NAME="Avest._<book>_<chapter>_<paragraph>_<verse>">`
    # anchor, and the transliterated Avestan words as
    # `<a href="javascript:ci(...)">` links inside `<span id=ii…>` content spans.
    #
    # == The anchor is the citation key (not the header text)
    #
    # A continuation page repeats NO "Book:" header — avest002 opens straight at
    # "Chapter: 1" — so the book context lives ONLY in the machine-generated
    # `<A NAME>` anchors (`Avest._Y_1_1_a` still names book Y). Parsing is
    # therefore anchor-driven: EVERY `Avest._…` anchor opens a section, keyed by
    # its one-to-four dotted components (book / book.chapter / book.chapter.para
    # / book.chapter.para.verse), and text accumulates into the innermost open
    # section. A section that carries its own `ii`-text becomes a passage —
    # almost always a verse, but a chapter or paragraph can carry a ritual rubric
    # of its own (Yasna 1 opens with the priest roles "zōt̰. u. rāspī." BEFORE
    # its first verse), and that text is the liturgy too, never dropped. Sections
    # that are pure containers (no direct text) mint nothing. An anchor deeper
    # than four components, or `ii`-text before any anchor, quarantines the whole
    # page loudly (ParseError) — text is never silently skipped.
    #
    # == What is text and what is apparatus
    #
    # The running transliteration is exactly the text under a content span whose
    # id starts with "ii": the word links, their "." / "::" separators, and the
    # parenthetical Pahlavi ritual rubrics in `<span id=iipzc…>`. Everything else
    # is excluded by that one rule — the `<span id=x12>` superscript markers
    # (Geldner line numbers, interspersed MID-verse: "frauuarāne.2 mazdaiiasnō"
    # would be corruption), the `<span id=hN>` headers, the `<span id=vod12>`
    # cross-references, the editorial credit block before the first verse, and
    # the page footer. `<SUP>` wraps in-word combining marks (mazdā̊, xᵛarənah-);
    # its content is part of the word and is kept.
    #
    # Text is NFC-normalized at this boundary (ave is NOT NFC-exempt — the
    # combining-diacritic transliteration makes composition matter).
    module TitusAvestanParser
      # One keyed section that carries text: +components+ is the ordered anchor
      # tail (["Y"], ["Y", "0", "1", "a"], …) — the adapter mints the urn and
      # annotations from it; +text+ is the NFC transliteration. Raw tokens, never
      # re-interpreted here.
      Section = Data.define(:components, :text)

      # The anchor prefix every structural anchor carries.
      ANCHOR_PREFIX = "Avest._"

      # The deepest structural level (book.chapter.paragraph.verse).
      MAX_LEVELS = 4

      # Parse one page's HTML into its ordered text-bearing sections (document
      # order == reading order == sequence). Raises Nabu::ParseError on a
      # structural surprise (an anchor deeper than four levels, or content text
      # with no section to hold it) — the page is quarantined whole rather than
      # served with a hole in it.
      def self.parse(html)
        doc = Nokogiri::HTML(html)
        sections = []
        current = nil
        walk(doc) do |node|
          if (comps = section_components(node))
            current = { comps: comps, buffer: +"" }
            sections << current
          elsif node.text? && content_text?(node)
            if current.nil?
              raise Nabu::ParseError,
                    "titus-avestan: content text #{node.text.strip.inspect} before any section anchor"
            end
            current[:buffer] << node.text
          end
        end
        sections.filter_map do |s|
          text = clean(s[:buffer])
          Section.new(components: s[:comps], text: text) unless text.empty?
        end
      end

      # Pre-order (document-order) traversal yielding every node. ITERATIVE by
      # design: this edition's broken markup leaves each line's `<span id=n16>`
      # unclosed, so the DOM nests hundreds of spans deep — a recursive walk
      # blows the stack (Nokogiri's own #traverse is bottom-up anyway, which
      # would break the anchor→following-text interleaving this relies on).
      def self.walk(root)
        stack = root.children.to_a.reverse
        until stack.empty?
          node = stack.pop
          yield node
          next unless node.element?

          children = node.children.to_a
          stack.concat(children.reverse) unless children.empty?
        end
      end

      # The one-to-four anchor-tail components when +node+ is a structural
      # `Avest._…` anchor, else nil. The bare collection anchor (`Avest.`, no
      # trailing components) is not one. An anchor deeper than four levels is a
      # structural surprise — ParseError, never a silent skip.
      def self.section_components(node)
        return nil unless node.element? && node.name == "a"

        name = node["name"]
        return nil unless name&.start_with?(ANCHOR_PREFIX)

        comps = name.delete_prefix(ANCHOR_PREFIX).split("_")
        return comps if (1..MAX_LEVELS).cover?(comps.size)

        raise Nabu::ParseError,
              "titus-avestan: anchor #{name.inspect} has #{comps.size} components (expected 1..#{MAX_LEVELS})"
      end

      # A text node belongs to the running transliteration iff some ancestor is a
      # content span (id starting "ii"). This one rule keeps words + separators +
      # ritual rubrics + in-word <SUP> marks and excludes headers, the x12
      # superscript apparatus, cross-references, the editorial block, and the
      # footer — robustly, regardless of how the broken markup nests.
      def self.content_text?(node)
        node.ancestors.any? { |a| a["id"]&.start_with?("ii") }
      end

      # Collapse the whitespace the markup used for indentation (spaces and the
      # decoded &nbsp; U+00A0), then NFC-normalize at the boundary.
      def self.clean(text)
        Nabu::Normalize.nfc(text.gsub(/\p{Space}+/, " ").strip)
      end
    end
  end
end
