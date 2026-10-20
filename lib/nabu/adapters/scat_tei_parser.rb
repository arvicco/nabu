# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The scat-tei parser family: the TEI the St. Petersburg Corpus of
    # Hagiographic Texts (SCAT) ships in its release zips (1.2.0 census,
    # all 24 texts). The shape, verbatim from the release:
    #
    # - one <ab> per text, the running text as <w> words (the manuscript
    #   surface as the element text, a normalized spelling in @norm; the
    #   morphology subset adds @lemma/@pos/@msd), <pc>/<c> punctuation,
    #   <num>, <name>, <q source=…> quotations (biblical "BQ:LUK11:20" or
    #   patristic "Q:…"), <head>/<div1>/<div2>/<floatingText> structure on
    #   the structurally annotated subset;
    # - <pb n="N"/> / <pb n="-N"/> folio sides — the plain number is the
    #   recto, the minus-prefixed one its verso (ob. in Russian folio
    #   notation; every text alternates N, -N, N+1 …), with a column letter
    #   on the two-column manuscript (442a, -442a); <lb/> lines;
    # - <note type="corr"> editorial corrections and <add place="margin">
    #   marginal additions (upstream wraps their words in [ ] <c> marks).
    #
    # The passage grain is the folio side: one Page per <pb>, cited
    # f.<N>r / f.<N>v (column letters as f.442r.a). The text is the
    # manuscript surface — words joined by spaces, punctuation glued left,
    # an opening [ glued right, lb-split words rejoined. A <pb> INSIDE a
    # <w> (a word running over the page edge, ~600 in the release) takes
    # effect after that word: the word belongs to the side it starts on.
    # A pb repeating the previous n with text on both sides (one live
    # case, ThdTtm 53/53) keeps both pages apart with a ".2" suffix on
    # the second citation; repeats with nothing between them (DmPrlc
    # -217, GrPelsh 308/-308/-309/-326) emit no empty page, so the side
    # keeps its plain citation. Corrections ride as annotations, never as
    # text (canonical means canonical). Stray text nodes outside <w>/<pc>
    # (two lone periods in KrnKml div2s) are not text — declared.
    class ScatTeiParser
      Page = Data.define(:citation, :folio, :text, :tokens, :corrections, :quotations)

      OPENING = ["[", "("].freeze
      WORD = "w"
      PUNCT = %w[pc c].freeze

      def title(xml, label:)
        reader(xml, label).each do |node|
          next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == "title"

          return Normalize.nfc(node.inner_xml.strip)
        end
        nil
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{label}: malformed SCAT TEI: #{e.message}"
      end

      def pages(xml, label:)
        Walk.new.run(reader(xml, label))
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{label}: malformed SCAT TEI: #{e.message}"
      end

      private

      def reader(xml, _label)
        Nokogiri::XML::Reader(xml)
      end

      # The streaming state machine over one text.
      class Walk
        FOLIO = /\A(-)?(\d+)([a-z])?\z/

        def initialize
          @pages = []
          @emitted = Hash.new(0)
          @page = nil
          @pending_pb = nil
          @stack = []
          @word = nil
          @punct = nil
          @note = nil
        end

        def run(reader)
          reader.each do |node|
            case node.node_type
            when Nokogiri::XML::Reader::TYPE_ELEMENT then open_element(node)
            when Nokogiri::XML::Reader::TYPE_END_ELEMENT then close(node.name)
            when Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_SIGNIFICANT_WHITESPACE
              text(node.value)
            end
          end
          flush
          @pages
        end

        private

        def open_element(node)
          name = node.name
          empty = node.empty_element?
          case name
          when "pb" then pb(node.attribute("n").to_s)
          when WORD then start_word(node)
          when *PUNCT then @punct = +""
          when "note" then @note = +"" if node.attribute("type") == "corr"
          when "q" then quotation(node)
          end
          @stack.push(name) unless empty
          close(name) if empty && name != "pb"
        end

        def close(name)
          @stack.pop if @stack.last == name
          case name
          when WORD then finish_word
          when *PUNCT then finish_punct
          when "note" then finish_note
          end
        end

        def text(value)
          if @note then @note << value
          elsif @word then @word[:pieces] << value.strip
          elsif @punct then @punct << value.strip
          end
        end

        def pb(folio)
          if @word
            @pending_pb = folio
          else
            turn_page(folio)
          end
        end

        def turn_page(folio)
          flush
          @page = { folio: folio, parts: [], tokens: [], corrections: [], quotations: [] }
        end

        def start_word(node)
          @word = { pieces: [], attrs: %w[norm lemma pos msd].to_h { |k| [k, node.attribute(k)] },
                    name: @stack.include?("name"), num: @stack.include?("num") }
        end

        def finish_word
          word = @word
          @word = nil
          form = Normalize.nfc(word[:pieces].join)
          append(form, glue: :none) unless form.empty?
          token(word, form) unless form.empty?
          return unless @pending_pb

          folio = @pending_pb
          @pending_pb = nil
          turn_page(folio)
        end

        def token(word, form)
          return if @page.nil?

          entry = { "form" => form }
          word[:attrs].each { |key, value| entry[key] = Normalize.nfc(value) unless value.nil? || value.empty? }
          entry.delete("lemma") if word[:num] && entry["lemma"]&.match?(/\A\d+\z/)
          entry["name"] = true if word[:name]
          @page[:tokens] << entry
        end

        def finish_punct
          mark = @punct.to_s
          @punct = nil
          return if mark.empty?

          append(mark, glue: OPENING.include?(mark) ? :right : :left)
        end

        def finish_note
          return if @note.nil?

          reading = Normalize.nfc(@note.strip)
          @note = nil
          @page[:corrections] << reading if @page && !reading.empty?
        end

        def quotation(node)
          return if @page.nil?

          entry = { "source" => node.attribute("source"), "type" => node.attribute("type") }.compact
          @page[:quotations] << entry unless entry.empty?
        end

        # parts are [string, glue] — glue :left attaches to the previous
        # part, :right makes the NEXT part attach to this one.
        def append(string, glue:)
          return if @page.nil?

          @page[:parts] << [string, glue]
        end

        def flush
          return if @page.nil?

          page = @page
          @page = nil
          text = render(page[:parts])
          return if text.empty?

          base = citation(page[:folio])
          @emitted[base] += 1
          cite = @emitted[base] == 1 ? base : "#{base}.#{@emitted[base]}"
          @pages << Page.new(citation: cite, folio: page[:folio], text: Normalize.nfc(text),
                             tokens: page[:tokens], corrections: page[:corrections],
                             quotations: page[:quotations])
        end

        def render(parts)
          out = +""
          glue_next = false
          parts.each do |string, glue|
            out << " " unless out.empty? || glue == :left || glue_next
            out << string
            glue_next = glue == :right
          end
          out.strip
        end

        def citation(folio)
          match = FOLIO.match(folio.to_s) or return "pb.#{folio}"

          side = match[1] ? "v" : "r"
          column = match[3] ? ".#{match[3]}" : ""
          "f.#{match[2]}#{side}#{column}"
        end
      end
    end
  end
end
