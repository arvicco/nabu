# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "titus_avestan_parser"

module Nabu
  module Adapters
    # TITUS Old Prussian corpus parser family. The same frame-based edition
    # machinery as the Avestan corpus (sequential apreuNNN.htm pages, "Next
    # part" chain, machine-generated <A NAME> anchors), but its own content
    # model: a DIPLOMATIC edition (W. Euler after Mažiulis) whose structural
    # headers name every level and whose content lanes mix the Old Prussian
    # text with the German of the bilingual prints and vocabularies.
    #
    # == Lines, keyed by header + anchor
    #
    # Each printed line opens with `<span id=h6>Line: <n><A NAME="OPr.Corp.
    # _<text>_<part>_<paragraph>_<page>_<line>">`. The anchor is the
    # identity (it rides the passage urn verbatim), but it cannot be split
    # blindly: parts carry underscores of their own ("I._Decal.") and empty
    # levels and the fragments' "_" page placeholder make runs of them. So
    # the levels come from the page's own headers — h3 "Part:", h4
    # "Paragraph:", h5 "Page:", h6 "Line:" — and the text siglum from the
    # anchor's first token (continuation pages omit the h2 "Text:" header;
    # the sigla Kat.I/Kat.II/Kat.III/Gloss./Fragm. carry no underscore).
    # The anchor must equal the joined levels, or the page quarantines: a
    # header/anchor disagreement is a structural surprise, never guessed.
    # Header order varies (the Elbing pages set Page before Paragraph, the
    # catechisms after), so Page is tracked on its own; Part clears
    # Paragraph (Grunau's columns run paragraph-less).
    #
    # == Lanes: the Prussian is the text, the German an annotation
    #
    # Content spans (`<span id=…>`) name their lane:
    #   baap12/16/22, baapx…  — Old Prussian (x = a hyphen-broken fragment)
    #                           → the passage TEXT
    #   oend12/16/22, oendx…  — the German of the prints and vocabularies
    #                           → the `german` annotation (the Elbing
    #                             headword "GOt" beside "Deywis")
    #   welar…, oec…, bali…   — the editors' Latin, English and Lithuanian
    #                           (title furniture, the Basel epigram's
    #                           translations) — never Old Prussian, dropped
    #   …f12 / …fi12          — footnote apparatus (the Anm./N. notes)
    #   h*, n*, nd*, title, … — headers, layout, editorial prose
    # A line with no Prussian lane is not a passage (the German prefaces and
    # Grunau's German prose; the parallel German master texts are their own
    # TITUS edition). A lane id SHAPED like a content lane (letters + size
    # suffix) that this vocabulary does not know quarantines the page
    # loudly — a new language lane must be classified, never dropped.
    #
    # Footnote links (`<a><span id=fn><sup>*</sup></span></a>` followed by
    # the note number's `<sup>`) are apparatus and are removed before the
    # walk; every OTHER superscript is the print's own (Kat.III's "²ſʒ")
    # and stays.
    module TitusOldPrussianParser
      # One Old Prussian line: +anchor+ is the anchor tail after the
      # collection prefix (verbatim — the urn's citation); +siglum+ the text
      # siglum (Kat.I, Gloss., …); +part+/+paragraph+/+page+/+line+ the
      # header levels (raw tokens, "" when the level is empty); +text+ the
      # NFC Prussian line; +german+ the German lane's NFC text or nil.
      Line = Data.define(:anchor, :siglum, :part, :paragraph, :page, :line, :text, :german)

      ANCHOR_PREFIX = "OPr.Corp._"

      PRUSSIAN_LANE = /\Abaapx?(?:12|16|22)\z/
      GERMAN_LANE = /\Aoendx?(?:12|16|22)\z/
      # The editors' own renderings and title furniture: Latin, English,
      # Lithuanian (sample census 2026-11-12, 9 of 40 pages).
      # census: 9 sampled pages, 2026-11-12
      OTHER_LANE = /\A(?:welar|oec|bali)x?(?:12|16|22)\z/
      # Footnote apparatus: every notes lane carries an f / fi size prefix
      # (baapf12, balfi12, oendf12, ndf12, oeff12 …).
      FOOTNOTE_LANE = /fi?\d+\z/
      # Layout and editorial prose (n16 spacing, nd12 the preface notes).
      LAYOUT_LANE = /\And?\d+\z/
      # Anything else shaped like a content lane is a new language lane.
      LANE_SHAPE = /\A[a-z]+x?(?:12|16|22)\z/

      HEADER = /\Ah([1-6])\z/
      LABEL = /\A\p{Space}*(?:Text collection|Text|Part|Paragraph|Page|Line):\p{Space}*(.*?)\p{Space}*\z/m

      # Parse one page's HTML into its ordered Old Prussian lines. Raises
      # Nabu::ParseError on a structural surprise: an unknown content lane,
      # Prussian text outside any line, or a line anchor that disagrees
      # with its headers.
      def self.parse(html)
        doc = Nokogiri::HTML(html)
        strip_footnote_links(doc)
        levels = { part: "", paragraph: "", page: "" }
        lines = []
        current = nil
        TitusAvestanParser.walk(doc) do |node|
          if (level = header_level(node))
            current = nil
            if level == 6
              current = open_line(node, levels)
              lines << current if current
            else
              set_level(levels, level, label_of(node))
            end
          elsif node.text?
            accumulate(current, lane_of(node), node.text)
          end
        end
        lines.filter_map { |line| finish(line) }
      end

      # Remove each footnote link and the note-number superscript after it.
      # The edition spaces the marker off its word ("rekyſe *¹."); when
      # punctuation follows the marker, that spacing goes with it — the
      # marker's own furniture, never the print's.
      def self.strip_footnote_links(doc)
        doc.xpath("//span[@id='fn']").each do |marker|
          link = marker.ancestors("a").first || marker
          number = link.next_sibling
          number.remove if number&.element? && number.name == "sup"
          before = link.previous_sibling
          after = link.next_sibling
          if before&.text? && after&.text? && after.content.match?(/\A[.,;:]/)
            before.content = before.content.sub(/\p{Space}+\z/, "")
          end
          link.remove
        end
      end

      def self.header_level(node)
        return nil unless node.element? && node.name == "span"

        match = HEADER.match(node["id"].to_s)
        match && Integer(match[1], 10)
      end

      # The header's own label value ("Part: I._Decal." → "I._Decal.").
      def self.label_of(node)
        own = node.children.select(&:text?).map(&:text).join
        match = LABEL.match(own)
        match ? match[1] : ""
      end

      def self.set_level(levels, level, value)
        case level
        when 2
          levels[:part] = ""
          levels[:paragraph] = ""
        when 3
          levels[:part] = value
          levels[:paragraph] = ""
        when 4 then levels[:paragraph] = value
        when 5 then levels[:page] = value
        end
      end

      # A new line from an h6 header, or nil for an h6 without a corpus
      # anchor. The anchor must equal the joined header levels.
      def self.open_line(node, levels)
        anchor = node.css("a[name]").map { |a| a["name"] }.find { |name| name.start_with?(ANCHOR_PREFIX) }
        return nil if anchor.nil?

        tail = anchor.delete_prefix(ANCHOR_PREFIX)
        siglum = tail.split("_", 2).first
        line = label_of(node)
        expected = [siglum, levels[:part], levels[:paragraph], levels[:page], line].join("_")
        unless tail == expected
          raise Nabu::ParseError,
                "titus-old-prussian: line anchor #{anchor.inspect} does not match its headers " \
                "(expected #{ANCHOR_PREFIX}#{expected})"
        end

        { anchor: tail, siglum: siglum, part: levels[:part], paragraph: levels[:paragraph],
          page: levels[:page], line: line, prussian: +"", german: +"" }
      end

      # The lane of a text node — :prussian / :german / :other — or nil for
      # apparatus, layout and headers. An unknown content-shaped lane raises.
      def self.lane_of(node)
        node.ancestors.each do |ancestor|
          id = ancestor["id"]
          next if id.nil?
          return :prussian if PRUSSIAN_LANE.match?(id)
          return :german if GERMAN_LANE.match?(id)
          return :other if OTHER_LANE.match?(id)
          return nil if FOOTNOTE_LANE.match?(id) || LAYOUT_LANE.match?(id) || !LANE_SHAPE.match?(id)

          raise Nabu::ParseError,
                "titus-old-prussian: unknown content lane #{id.inspect} — classify it before ingesting"
        end
        nil
      end

      def self.accumulate(line, lane, text)
        case lane
        when :prussian
          if line.nil?
            return if text.strip.empty?

            raise Nabu::ParseError,
                  "titus-old-prussian: Prussian text #{text.strip[0, 40].inspect} outside any line anchor"
          end
          line[:prussian] << text
        when :german
          line[:german] << text if line
        end
      end

      def self.finish(line)
        text = clean(line[:prussian])
        return nil if text.empty?

        german = clean(line[:german])
        Line.new(anchor: line[:anchor], siglum: line[:siglum], part: line[:part],
                 paragraph: line[:paragraph], page: line[:page], line: line[:line],
                 text: text, german: german.empty? ? nil : german)
      end

      def self.clean(text)
        Nabu::Normalize.nfc(text.gsub(/\p{Space}+/, " ").strip)
      end
    end
  end
end
