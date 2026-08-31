# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "titus_avestan_parser"

module Nabu
  module Adapters
    # TITUS Osco-Umbrian corpus parser family (P90-2). The same frame-based
    # 1990s edition machinery as the Avestan corpus (sequential oskumNNN.htm
    # pages, "Next part" chain, machine-generated <A NAME> anchors), but the
    # content model differs enough for its own family: every inscription LINE
    # is rendered as a SYNOPSIS of script lanes — the original-script lane
    # first (native Italic right-to-left, Latin capitals, or Greek letters),
    # then the edition's own "unified Latin transliteration ... added
    # throughout ... to provide a common retrieval basis" (the editorial
    # header's words, oskum001.htm).
    #
    # == Anchors
    #
    # `<A NAME="Inscr.OU_<monument>_<inscription>[_<part>]_<line>">` — e.g.
    # `Inscr.OU_IT_Ia__1` (Tabulae Iguvinae, table Ia, line 1; the doubled
    # underscore is an EMPTY level, preserved in the raw components and
    # dropped at citation time) or `Inscr.OU_BaI_POMP-2__1`. The bare
    # collection anchor (`Inscr.OU`) and the container anchors (monument,
    # inscription) open sections that normally carry no lane text and mint
    # nothing. Components are raw tokens, never re-interpreted — some carry
    # parentheses (`(&)`, `(inc.)-1`, `(VS)`) verbatim.
    #
    # == Lanes: the transliteration is the text, the original an annotation
    #
    # Content spans (`<span id=…16>`) name their lane:
    #   weum16 / weos16   — the unified transliteration (Umbrian- / Oscan-lane)
    #                       → the passage TEXT, and the language claim
    #                         (xum / osc; the edition's own coarse split —
    #                         minor Sabellic dialects ride their nearest lane)
    #   umo16 / oso16     — the native-Italic-alphabet original (RTL)
    #   weuml16 / weosl16 — the Latin-alphabet original (capitals)
    #   gros16            — the Greek-alphabet original
    # The original lane rides the passage as the "original" annotation with
    # its alphabet named; a lane id that LOOKS like a content lane but is not
    # in the vocabulary quarantines the page loudly (a new dialect lane must
    # be classified, never silently dropped). `wec*` spans are citation
    # headers, `bibliogr12`/`gr12`/`h*`/`n16` apparatus and layout — all
    # excluded by the lane rule.
    module TitusOscoUmbrianParser
      # One keyed section: +components+ is the raw anchor tail (empties
      # preserved); +text+ the NFC transliteration; +language+ the lane vote
      # (xum/osc); +original+ the original-script line (nil when the page
      # carries none or it equals the text); +alphabet+ the original lane's
      # script (italic/latin/greek, nil without an original lane).
      Section = Data.define(:components, :text, :language, :original, :alphabet)

      # The collection prefix every structural anchor carries; the bare
      # collection anchor itself opens no section.
      ANCHOR_PREFIX = "Inscr.OU"

      # Sampled depth histogram over 20 live pages (2026-08-31): 1..5
      # components (313×4, 73×5 of 426); deeper is a structural surprise.
      # census: 426 anchors over 20 sampled pages, 2026-08-31
      MAX_LEVELS = 5

      # Transliteration lanes → the language claim they carry.
      TRANSLIT_LANES = { "weum16" => "xum", "weos16" => "osc" }.freeze

      # Original-script lanes → [language claim, alphabet].
      ORIGINAL_LANES = {
        "umo16" => %w[xum italic], "weuml16" => %w[xum latin],
        "oso16" => %w[osc italic], "weosl16" => %w[osc latin],
        "gros16" => %w[osc greek]
      }.freeze

      # A span id shaped like a content lane. Anything matching this that the
      # two vocabularies do not know is a NEW lane — quarantine, never skip.
      # (`wec…` ids are citation headers, excluded by name.)
      LANE_SHAPE = /\A(?:we(?!c)[a-z]+|umo|oso|gros)\d+\z/

      # Parse one page's HTML into ordered text-bearing sections. Raises
      # Nabu::ParseError on a structural surprise: an over-deep anchor, lane
      # text before any anchor, an unknown content-shaped lane id, or a line
      # whose lanes vote two languages.
      def self.parse(html)
        doc = Nokogiri::HTML(html)
        sections = []
        current = nil
        TitusAvestanParser.walk(doc) do |node|
          if (comps = section_components(node))
            current = { comps: comps, translit: +"", original: +"", langs: [], alphabets: [] }
            sections << current
          elsif node.text? && (lane = lane_of(node))
            raise Nabu::ParseError, "titus-osco-umbrian: lane text before any section anchor" if current.nil?

            accumulate(current, lane, node.text)
          end
        end
        sections.filter_map { |section| finish(section) }
      end

      # The anchor-tail components when +node+ is a structural anchor under
      # the collection prefix, else nil (the bare collection anchor included).
      def self.section_components(node)
        return nil unless node.element? && node.name == "a"

        name = node["name"]
        return nil unless name&.start_with?(ANCHOR_PREFIX)

        tail = name.delete_prefix(ANCHOR_PREFIX).delete_prefix("_")
        return nil if tail.empty?

        comps = TitusAvestanParser.split_components(tail)
        return comps if (1..MAX_LEVELS).cover?(comps.size)

        raise Nabu::ParseError,
              "titus-osco-umbrian: anchor #{name.inspect} has #{comps.size} components (expected 1..#{MAX_LEVELS})"
      end

      # The lane of a text node — [:translit, id] / [:original, id] — or nil
      # for excluded markup. An unknown content-shaped lane id raises.
      def self.lane_of(node)
        node.ancestors.each do |ancestor|
          id = ancestor["id"]
          next if id.nil?
          return [:translit, id] if TRANSLIT_LANES.key?(id)
          return [:original, id] if ORIGINAL_LANES.key?(id)

          if LANE_SHAPE.match?(id)
            raise Nabu::ParseError,
                  "titus-osco-umbrian: unknown content lane #{id.inspect} — classify it before ingesting"
          end
        end
        nil
      end

      def self.accumulate(section, (kind, id), text)
        if kind == :translit
          section[:translit] << text
          section[:langs] << TRANSLIT_LANES.fetch(id)
        else
          language, alphabet = ORIGINAL_LANES.fetch(id)
          section[:original] << text
          section[:langs] << language
          section[:alphabets] << alphabet
        end
      end

      def self.finish(section)
        text = clean(section[:translit])
        original = clean(section[:original])
        return nil if text.empty? && original.empty?

        languages = section[:langs].uniq
        if languages.size > 1
          raise Nabu::ParseError,
                "titus-osco-umbrian: section #{section[:comps].join('_').inspect} mixes languages " \
                "#{languages.inspect} — one line, one language claim"
        end

        text = original if text.empty? # a lane-less transliteration never occurred in the census; stay honest
        Section.new(
          components: section[:comps], text: text, language: languages.first,
          original: original == text || original.empty? ? nil : original,
          alphabet: section[:alphabets].uniq.first
        )
      end

      def self.clean(text)
        Nabu::Normalize.nfc(text.gsub(/\p{Space}+/, " ").strip)
      end
    end
  end
end
