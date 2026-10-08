# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "titus_avestan_parser"

module Nabu
  module Adapters
    # TITUS Tocharian corpus parser family (P114-1a). The same frame-based
    # TITUS machinery as the Avestan and Osco-Umbrian corpora (sequential
    # tochaNNN.htm pages on a "Next part" chain, machine-generated <A NAME>
    # anchors, the 1990s `</sPAN>` markup), with its own content model —
    # the edition's "synoptic" arrangement: every manuscript LINE is given
    # twice, "in a plain transcriptive and a transliterative (syllabic)
    # notation" (the editorial header's words, tocha001.htm).
    #
    # == Anchors (censused over 13 live pages, 2026-10-07)
    #
    #   TochA                      language        (no section)
    #   TochA_THT                  collection      (no section)
    #   TochA_THT_<ms>             manuscript      — the THT number
    #   TochA_THT_<ms>_<part>      leaf side       — Sieg & Siegling's own
    #                                                number + a/b (recto/verso)
    #   TochA_THT_<ms>_<part>_<l>  LINE            — the passage grain; the
    #                                                bilingual pages split a
    #                                                line into 1a/1b/1c
    #                                                sub-lines by language
    #
    # Deeper anchors are a structural surprise — ParseError.
    #
    # == Lanes (`<span id=…16>`, all content lanes carry the 16 suffix)
    #
    #   iotoa16 / iotoac16       Tocharian A transcription → the passage TEXT
    #   iotoax16 / iotoaxc16     Tocharian A syllabic transliteration
    #                            → the "syllabic" annotation (optional — some
    #                            pages give only the transcription)
    #   iosbplc16 / iosbplxc16   Sanskrit (the bilingual sub-lines, e.g.
    #                            "kṣemeṇa", "āvr̥hyāt\") — transcription /
    #                            syllabic, claimed `san`
    #
    # The `c`-suffixed variants occur page-wise (and once mixed with the
    # plain id on one page); the edition does not say what the suffix
    # marks, so both spellings map to the same role and language — never
    # interpreted further. A span id SHAPED like a content lane that the
    # vocabulary does not know quarantines the page (a new lane must be
    # classified, never dropped). `iocd12` is the THT catalogue block
    # (12-size: the find signature, the THT number, the German catalogue
    # note, the per-side Vorderseite/Rückseite label) — collected as
    # metadata, never text; `h*`/`n16`/`title`/`textdescr`/`bibliogr` are
    # layout and the editorial header.
    #
    # == Text discipline
    #
    # Verbatim: the edition's damage/restoration notation (//// lacuna
    # edges, [..] damaged, (..) restored, _ and . for lost/illegible akṣaras,
    # + for a partially preserved one, capitals for the virāma/Fremdzeichen
    # forms, \ the virāma) rides untouched. The ONE exclusion is a <sup>
    # holding only digits: the print edition's footnote reference (TITUS
    # carries the number but not the note) — apparatus, collected as the
    # "footnotes" annotation. Whitespace collapses; NFC at the boundary.
    module TitusTocharianParser
      # One keyed line: +components+ the anchor tail after the collection
      # prefix ([ms, part, line]); +text+ the NFC transcription; +syllabic+
      # the syllabic lane (nil when the page gives none); +language+ the
      # lane vote; +footnotes+ the footnote numbers; +side+ the part's own
      # catalogue label (Vorderseite/Rückseite, "?" verbatim) or nil.
      Line = Data.define(:components, :text, :syllabic, :language, :footnotes, :side)

      # One manuscript block's catalogue: +number+ the THT number (anchor),
      # +catalogue+ the manuscript-level iocd12 lines in order.
      Manuscript = Data.define(:number, :catalogue)

      # The parsed page: its manuscripts (in order) and its lines.
      Page = Data.define(:manuscripts, :lines)

      # The structural anchor prefix every section carries; the bare
      # language/collection anchors open nothing.
      ANCHOR_PREFIX = "TochA_THT"

      # ms / part / line — 3 is the deepest level the edition mints.
      MAX_LEVELS = 3

      # role, language per lane id.
      LANES = {
        "iotoa16" => %i[text xto], "iotoac16" => %i[text xto],
        "iotoax16" => %i[syllabic xto], "iotoaxc16" => %i[syllabic xto],
        "iosbplc16" => %i[text san], "iosbplxc16" => %i[syllabic san]
      }.freeze

      # The catalogue lane (manuscript and part notes).
      CATALOGUE_LANE = "iocd12"

      # A span id shaped like a content lane (the TITUS `io…16` family) —
      # anything matching this that LANES does not know is a NEW lane.
      LANE_SHAPE = /\Aio[a-z]+16\z/

      # Parse one page's HTML. Raises Nabu::ParseError on a structural
      # surprise: an over-deep anchor, lane text before any line anchor, an
      # unknown content-shaped lane id, or a line whose lanes vote two
      # languages.
      def self.parse(html)
        state = { manuscripts: [], lines: [], current: nil, part_side: nil, part_open: false }
        TitusAvestanParser.walk(Nokogiri::HTML(html)) { |node| visit(node, state) }
        Page.new(
          manuscripts: state[:manuscripts].map { |m| Manuscript.new(number: m[:number], catalogue: m[:catalogue]) },
          lines: state[:lines].filter_map { |line| finish(line) }
        )
      end

      def self.visit(node, state)
        if (comps = section_components(node))
          open_section(comps, state)
        elsif catalogue_span?(node)
          note = clean(node.text)
          record_catalogue(note, state) unless note.empty?
        elsif node.text? && (lane = lane_of(node))
          raise Nabu::ParseError, "titus-tocharian: lane text before any line anchor" if state[:current].nil?

          accumulate(state[:current], lane, node)
        end
      end

      def self.open_section(comps, state)
        case comps.size
        when 1
          state[:manuscripts] << { number: comps[0], catalogue: [] }
          state[:current] = nil
          state[:part_side] = nil
          state[:part_open] = false
        when 2
          state[:current] = nil
          state[:part_side] = nil
          state[:part_open] = true
        else
          state[:part_open] = false
          state[:current] = { comps: comps, text: +"", syllabic: +"", langs: [], footnotes: [],
                              side: state[:part_side] }
          state[:lines] << state[:current]
        end
      end

      # Catalogue notes before a part's first line label the part (its
      # side); before any part they describe the manuscript.
      def self.record_catalogue(note, state)
        if state[:part_open]
          state[:part_side] = [state[:part_side], note].compact.join(" ")
        elsif state[:current].nil? && (manuscript = state[:manuscripts].last)
          manuscript[:catalogue] << note
        end
      end

      # The anchor-tail components when +node+ is a structural anchor under
      # the collection prefix, else nil (bare language/collection included).
      def self.section_components(node)
        return nil unless node.element? && node.name == "a"

        name = node["name"]
        return nil unless name&.start_with?("#{ANCHOR_PREFIX}_")

        comps = TitusAvestanParser.split_components(name.delete_prefix("#{ANCHOR_PREFIX}_"))
        return comps if (1..MAX_LEVELS).cover?(comps.size) && comps.none?(&:empty?)

        raise Nabu::ParseError,
              "titus-tocharian: anchor #{name.inspect} has #{comps.size} components (expected 1..#{MAX_LEVELS})"
      end

      # The outermost catalogue span (its link children are walked past by
      # the lane rule: iocd12 is not a content lane).
      def self.catalogue_span?(node)
        node.element? && node.name == "span" && node["id"] == CATALOGUE_LANE
      end

      # [role, language, footnote?] for a lane text node, or nil for
      # excluded markup. An unknown content-shaped lane id raises.
      def self.lane_of(node)
        node.ancestors.each do |ancestor|
          id = ancestor["id"]
          next if id.nil?
          return LANES.fetch(id) if LANES.key?(id)
          return nil if id == CATALOGUE_LANE

          if LANE_SHAPE.match?(id)
            raise Nabu::ParseError,
                  "titus-tocharian: unknown content lane #{id.inspect} — classify it before ingesting"
          end
        end
        nil
      end

      def self.accumulate(line, (role, language), node)
        if footnote?(node)
          line[:footnotes] << node.text.strip if role == :text
          return
        end

        line[role] << node.text
        line[:langs] << language
      end

      # A digits-only <sup>: the print edition's footnote reference.
      def self.footnote?(node)
        node.parent&.name == "sup" && node.text.strip.match?(/\A\d+\z/)
      end

      def self.finish(line)
        text = clean(line[:text])
        syllabic = clean(line[:syllabic])
        return nil if text.empty? && syllabic.empty?

        languages = line[:langs].uniq
        if languages.size > 1
          raise Nabu::ParseError,
                "titus-tocharian: line #{line[:comps].join('_').inspect} mixes languages " \
                "#{languages.inspect} — one line, one language claim"
        end

        # A syllabic-only line never occurred in the census; stay honest.
        text = syllabic if text.empty?
        Line.new(components: line[:comps], text: text, syllabic: syllabic.empty? ? nil : syllabic,
                 language: languages.first.to_s, footnotes: line[:footnotes], side: line[:side])
      end

      def self.clean(text)
        Nabu::Normalize.nfc(text.gsub(/\p{Space}+/, " ").strip)
      end
    end
  end
end
