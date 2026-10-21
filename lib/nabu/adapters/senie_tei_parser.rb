# frozen_string_literal: true

require "stringio"
require_relative "streaming_tei_parser"

module Nabu
  module Adapters
    # The senie-tei parser family: the body of ONE <TEI> element of the
    # SENIE corpus file (the Corpus of Early Written Latvian, AiLab IMCS UL
    # + the Latvian Language Institute; SENIE_Unicode.tei.xml, 2025-11
    # release). Census of the whole release (61 MB, 183 text-bearing TEIs):
    #
    # - text lives ONLY in <div type="Language" lang="Latvian|German|Latin|
    #   Estonian|Greek|Polish|Aramaic|Italian|English|French|Flemish"> runs
    #   (561,051) and as bare text in three furniture divs —
    #   type="Parallel" (10,434 marginal cross-references), "Title (even)"
    #   / "Title (odd)" / "Title (column)" (1,138 running titles) and
    #   "Sheet" (399 signature marks: "A iij");
    # - Language runs nest inside type="Paragraph" (18,164), "Remark"
    #   (19,316 marginal glosses) and "Comment" (1,932 headings and
    #   editorial captions); <lb/> (495,949) marks the print line;
    # - three citation grains, never mixed in one TEI: <pb n> page breaks
    #   (10,877, always body children — 99 page-bearing TEIs), <div
    #   type="Verse" n id="BOOK_ch:v."> (36,686 — the 84 Bible books of
    #   the 1685 New Testament, the 1689–94 Old Testament and the 1689
    #   Apocrypha) and <div type="Section" n id> (123 — four law/oath
    #   prints);
    # - <corr>…</corr><sic>…</sic> pairs (6,256): sic is the print's own
    #   reading, corr the editors'; a <sic> directly after a body-level
    #   <pb> (333) is the PRINTED page number where the print misnumbered
    #   (<pb n="13"/><sic>14</sic>).
    #
    # == The passage grain (the declared rule)
    #
    # One Unit per citation-grain unit: a page (p.<n>, from the pb's n —
    # upstream's own page labels: "6", "A2A", "1v", "148B"; the unnumbered
    # "--" reads p.u, any other non-alphanumeric run reads "_"), a verse
    # (<chapter>.<verse> from the id's "ch:v." tail — verse 0 is the
    # chapter summary) or a section (s.<n> from @n, trailing dot dropped:
    # "5.6." → s.5.6). Body-level material outside any verse/section (the
    # book and chapter headings in Comment divs, 1,342 runs) is its own
    # unit cited <the next unit's citation>.head (1.0.head, 12.5.head —
    # a heading can stand mid-chapter); material after the last one is
    # "end"; material before a TEI's first pb is "front". Repeated
    # citations (a print's duplicated page number: Ench1586 EB/EB, or an
    # upstream verse id given twice: JT1685::Lk 8:25) take the house :b2
    # suffix in document order.
    #
    # == Text and layers
    #
    # Unit text is the MAIN layer: Language runs outside the furniture
    # divs, Remark and Comment runs included (they are printed text — the
    # glosses and headings of the page). Runs on one print line join with
    # a space; print lines join with "\n" — the line-faithful surface,
    # end-of-line hyphens kept (Chri-\nſtum). The search form rejoins them
    # (SenieTeiParser.search_source — a conventions §9 derivation,
    # recomputable from the stored text alone). sic readings are the
    # text; corr readings ride as "corrections" [{sic, corr}]. Furniture
    # rides as annotations, never text: "parallels", "running_titles",
    # "signatures"; "marginalia" / "comments" list the Remark / Comment
    # runs that ARE in the text. Per-unit language census "languages"
    # {code => characters} over the main layer; "foreign" lists the main-
    # layer runs whose language is not the unit's majority language
    # (upstream's lang tag verbatim — AP1622's Polish catechism lines are
    # tagged Latvian upstream and read lv here). A unit with no main-layer
    # text (a page of only running titles) emits nothing.
    class SenieTeiParser < StreamingTeiParser
      # SENIE's lang values → the house codes (the registry's anchors:
      # two-letter where it anchors the modern language, three-letter
      # where it anchors the historical one). Greek in these prints is the
      # quoted scriptural language (grc); Flemish rides nl.
      LANGUAGES = {
        "Latvian" => "lv", "German" => "de", "Latin" => "lat", "Estonian" => "et",
        "Greek" => "grc", "Polish" => "pl", "Aramaic" => "arc", "Italian" => "it",
        "English" => "en", "French" => "fr", "Flemish" => "nl"
      }.freeze

      Unit = Data.define(:citation, :text, :language, :annotations)

      # The search source: +text+ with every print-line break rejoined —
      # a line ending in a letter + "-" glues to the next line's first
      # letter (the hyphen dropped), every other line break reads as a
      # space. Pure and deterministic over the stored text.
      def self.search_source(text, _annotations = {})
        text.gsub(/(\p{L})-\n(?=\p{L})/, '\1').tr("\n", " ")
      end

      # +xml+ is one <TEI>…</TEI> element as a String. Returns the Units in
      # document order, collisions disambiguated.
      def units(xml, path:)
        disambiguate_collisions(extract(StringIO.new(xml), path: path))
      end

      private

      def extraction_class = Extraction

      # The body walk.
      class Extraction < StreamingTeiParser::Walker
        FURNITURE = {
          "Parallel" => "parallels", "Title (even)" => "running_titles", "Title (odd)" => "running_titles",
          "Title (column)" => "running_titles", "Sheet" => "signatures"
        }.freeze
        TEXT_LAYERS = { "Remark" => "marginalia", "Comment" => "comments" }.freeze
        VERSE_ID = /_(?<chapter>\d+):(?<verse>\d+)\.\z/

        def initialize(reader:, path:)
          super
          @in_body = false
          @units = []
          @unit = nil          # the open grain unit, or nil
          @pending = nil       # interstitial body-level material awaiting its citation
          @grain_seen = false
          @divs = []           # the open div types, outermost first
          @run = nil           # the open text run, or nil
          @corr = nil          # an open <corr> buffer
          @sic = nil           # an open <sic> buffer
          @last_corr = nil     # a closed corr awaiting its sic
          @after_pb = false    # a body-level <sic> right after a pb is a printed page number
        end

        def call
          @reader.each { |node| process(node) }
          finish_pending(next_citation: nil)
          close_unit
          @units
        end

        private

        def start_element(node)
          name = local_name(node)
          return @in_body = true if name == "body"
          return unless @in_body

          empty = node.empty_element?
          @after_pb = false unless %w[pb sic].include?(name)
          case name
          when "pb" then page_break(node.attribute("n").to_s)
          when "lb" then line_break
          when "div" then open_div(node, empty)
          when "sic" then @sic = +"" unless empty
          when "corr" then @corr = +"" unless empty
          end
        end

        def end_element(node)
          name = local_name(node)
          return @in_body = false if name == "body"
          return unless @in_body

          case name
          when "div" then close_div
          when "sic" then finish_sic
          when "corr" then finish_corr
          end
        end

        def text_node(node)
          return unless @in_body

          value = node.value.to_s
          if @corr
            @corr << value
          else
            @sic << value if @sic
            @run[:text] << value if @run
          end
        end

        # -- grains --------------------------------------------------------

        def page_break(label)
          @grain_seen = true
          finish_pending(next_citation: nil)
          close_unit
          @unit = new_unit("p.#{page_label(label)}")
          @unit[:annotations]["page"] = label
          @after_pb = true
        end

        def page_label(label)
          return "u" if label == "--"

          label.gsub(/[^0-9A-Za-z]+/, "_")
        end

        def open_div(node, empty)
          type = node.attribute("type").to_s
          case type
          when "Verse", "Section" then open_grain_div(node, type)
          when "Language" then open_run(lang: node.attribute("lang").to_s)
          else open_run(lang: nil, furniture_type: type) if FURNITURE.key?(type) && @run.nil?
          end
          return close_div_now(type) if empty

          @divs.push(type)
        end

        def close_div_now(type)
          @divs.push(type)
          close_div
        end

        def close_div
          type = @divs.pop
          case type
          when "Language" then finish_run
          when "Verse", "Section" then close_unit
          else finish_run if FURNITURE.key?(type) && @run && @run[:lang].nil?
          end
        end

        def open_grain_div(node, type)
          citation = grain_citation(node, type)
          @grain_seen = true
          finish_pending(next_citation: citation)
          close_unit
          @unit = new_unit(citation)
        end

        def grain_citation(node, type)
          if type == "Verse"
            match = VERSE_ID.match(node.attribute("id").to_s) or
              raise ParseError, "#{@path}: verse id #{node.attribute('id').inspect} has no chapter:verse tail"
            "#{Integer(match[:chapter], 10)}.#{Integer(match[:verse], 10)}"
          else
            n = node.attribute("n").to_s.delete_suffix(".")
            raise ParseError, "#{@path}: section without @n" if n.empty?

            "s.#{n}"
          end
        end

        # The unit a run lands in: the open grain unit, else the pending
        # interstitial one (cited once what follows it is known).
        def current_unit
          @unit || (@pending ||= new_unit(nil))
        end

        def finish_pending(next_citation:)
          return if @pending.nil?

          pending = @pending
          @pending = nil
          pending[:citation] = if next_citation then head_citation(next_citation)
                               elsif @grain_seen then "end"
                               else "front"
                               end
          emit(pending)
        end

        def head_citation(next_citation) = "#{next_citation}.head"

        def new_unit(citation)
          { citation: citation, lines: [+""], languages: Hash.new(0), runs: [], annotations: {} }
        end

        def close_unit
          return if @unit.nil?

          unit = @unit
          @unit = nil
          emit(unit)
        end

        # -- runs ----------------------------------------------------------

        # A Language run (lang given) or a furniture div's bare text (nil).
        # A Language run inside a furniture div is furniture too.
        def open_run(lang:, furniture_type: nil)
          finish_run if @run
          furniture = furniture_type || @divs.reverse.find { |type| FURNITURE.key?(type) }
          layer = @divs.reverse.find { |type| TEXT_LAYERS.key?(type) }
          @run = { lang: lang, furniture: furniture && FURNITURE[furniture], layer: layer && TEXT_LAYERS[layer],
                   text: +"", corrections: [] }
        end

        def finish_run
          run = @run
          @run = nil
          return if run.nil?

          unit = current_unit
          (unit[:annotations]["corrections"] ||= []).concat(run[:corrections]) unless run[:corrections].empty?
          text = flatten(run[:text]) or return

          if run[:lang].nil? || run[:furniture]
            (unit[:annotations][run[:furniture]] ||= []) << Normalize.nfc(text)
          else
            append_run(unit, run, text)
          end
        end

        def append_run(unit, run, text)
          code = LANGUAGES.fetch(run[:lang]) do
            raise ParseError, "#{@path}: unknown SENIE language #{run[:lang].inspect}"
          end
          line = unit[:lines].last
          line << " " unless line.empty?
          line << text
          unit[:languages][code] += text.length
          unit[:runs] << { "lang" => code, "text" => Normalize.nfc(text) }
          (unit[:annotations][run[:layer]] ||= []) << Normalize.nfc(text) if run[:layer]
        end

        def finish_corr
          @last_corr = flatten(@corr)
          @corr = nil
        end

        # A sic closes: inside a run it pairs with the corr just before it;
        # at body level right after a pb it is the printed page number.
        def finish_sic
          reading = flatten(@sic)
          @sic = nil
          corr = @last_corr
          @last_corr = nil
          if @run
            @run[:corrections] << { "sic" => Normalize.nfc(reading.to_s), "corr" => Normalize.nfc(corr.to_s) } if corr
          elsif @after_pb && @unit && reading
            @unit[:annotations]["printed_page"] = Normalize.nfc(reading)
          end
        end

        def line_break
          unit = @unit || @pending
          return if unit.nil? || unit[:lines].last.empty?

          unit[:lines] << +""
        end

        # -- emission ------------------------------------------------------

        def emit(unit)
          text = unit[:lines].map(&:strip).reject(&:empty?).join("\n")
          return if text.empty?

          language = majority(unit[:languages])
          annotations = unit[:annotations]
          annotations["languages"] = unit[:languages].sort.to_h
          foreign = unit[:runs].reject { |run| run["lang"] == language }
          annotations["foreign"] = foreign unless foreign.empty?
          @units << SenieTeiParser::Unit.new(citation: unit[:citation], text: Normalize.nfc(text),
                                             language: language, annotations: annotations)
        end

        # The language with the most characters (ties: alphabetical).
        def majority(languages)
          languages.min_by { |code, count| [-count, code] }.first
        end
      end
    end
  end
end
