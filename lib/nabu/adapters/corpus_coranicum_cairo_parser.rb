# frozen_string_literal: true

require "nokogiri"

require_relative "source_read"

module Nabu
  module Adapters
    # The Cairo 1924 Qurʾān of the Corpus Coranicum TEI export
    # (data/cairo_quran/cairoquran.xml, the family corpus-coranicum-tei):
    # the <div type="arabic_text"> read into suras → verses → words.
    #
    # Upstream shape (the whole file, census 2026-11-27): a <facsimile> of
    # 826 <surface n="826, Q 111:3- Q 113:3"> page images, then five body
    # divs — arabic_text (the edition), transcription (a word-by-word Latin
    # transcription), and translation en/de/fr. Inside arabic_text: <lg
    # xml:id="sura-NNN"> → <lg xml:id="verse-NNN-VVV"> → one <l n="+++1">
    # → <w xml:id="w-NNN-VVV-WWW">, with <pb> page breaks between verses.
    # Only arabic_text is read; the other divs are walked past (the adapter
    # class note says why).
    #
    # Page: the facsimile surface whose "Q s:v- Q s:v" range covers the
    # verse (826 ranges, every verse covered exactly once), read from the
    # header rather than the <pb> stream so a verse's page does not depend
    # on an earlier sura having been read. Kept verbatim as the surface's
    # leading number ("826", the image's KairoKoranStabi-826.JPG).
    #
    # Strict, never guessed: a word id must sit in its own verse with its
    # ordinal the next one, verses number contiguously from 1, suras
    # ascend, and any element other than lg/l/w/pb inside the arabic text is a
    # ParseError naming it. Streamed with Nokogiri::XML::Reader over the
    # belt-read string (17.5 MB — over the house DOM threshold).
    class CorpusCoranicumCairoParser
      Word = Data.define(:id, :number, :form)

      Verse = Data.define(:sura, :number, :page, :words) do
        # The verse as the edition prints it: words single-space joined.
        def text = words.map(&:form).join(" ")
      end

      SURFACE = /\A(\d+), Q (\d+):(\d+)- Q (\d+):(\d+)\z/
      SURA_ID = /\Asura-(\d{3})\z/
      VERSE_ID = /\Averse-(\d{3})-(\d{3})\z/
      WORD_ID = /\Aw-(\d{3})-(\d{3})-(\d{3})\z/
      ARABIC_DIV = "arabic_text"
      TEXT_ELEMENTS = %w[lg l w pb].freeze
      private_constant :SURFACE, :SURA_ID, :VERSE_ID, :WORD_ID, :ARABIC_DIV, :TEXT_ELEMENTS

      READER = Nokogiri::XML::Reader
      private_constant :READER

      # {sura number => [Verse …]} in document order.
      def suras(path)
        Walk.new(path).call
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # One Reader pass (class note).
      class Walk
        def initialize(path)
          @path = path
          @surfaces = []
          @suras = {}
          @div = nil
          @sura = nil
          @verse = nil
          @word = nil
        end

        def call
          xml = SourceRead.utf8_file(@path, label: "corpus-coranicum cairo")
          Nokogiri::XML::Reader(xml, @path).each { |node| process(node) }
          raise ParseError, "#{@path}: no #{ARABIC_DIV} suras found" if @suras.empty?

          @suras.transform_values { |verses| verses.map { |verse| finish(verse) } }
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start(node)
          when READER::TYPE_END_ELEMENT then stop(node)
          when READER::TYPE_TEXT, READER::TYPE_CDATA then @word[:form] << node.value if @word
          end
        end

        def start(node)
          name = node.local_name
          return surface(node) if name == "surface"
          return @div = node.attribute("type") if name == "div"
          return unless @div == ARABIC_DIV

          raise ParseError, "#{@path}: unexpected <#{name}> in the arabic text" unless TEXT_ELEMENTS.include?(name)

          case name
          when "lg" then open_lg(node)
          when "w" then open_word(node)
          end
        end

        def stop(node)
          case node.local_name
          when "div" then @div = nil
          when "w" then close_word if @div == ARABIC_DIV
          when "lg" then close_lg if @div == ARABIC_DIV
          end
        end

        def surface(node)
          match = SURFACE.match(node.attribute("n").to_s) or
            raise ParseError, "#{@path}: facsimile surface n=#{node.attribute('n').inspect} names no page range"
          page, *bounds = match.captures
          @surfaces << [page, [bounds[0].to_i, bounds[1].to_i], [bounds[2].to_i, bounds[3].to_i]]
        end

        def open_lg(node)
          id = node.attribute("xml:id").to_s
          if @sura.nil?
            open_sura(id)
          elsif @verse.nil?
            open_verse(id)
          else
            raise ParseError, "#{@path}: <lg #{id}> nested inside verse #{@verse[:number]}"
          end
        end

        def open_sura(id)
          match = SURA_ID.match(id) or raise ParseError, "#{@path}: sura lg id #{id.inspect} is not sura-NNN"
          number = match[1].to_i
          raise ParseError, "#{@path}: sura #{number} out of order" if number <= @suras.keys.max.to_i

          @sura = number
          @suras[number] = []
        end

        def open_verse(id)
          match = VERSE_ID.match(id) or raise ParseError, "#{@path}: verse lg id #{id.inspect} is not verse-NNN-VVV"
          sura, number = match.captures.map(&:to_i)
          expected = @suras[@sura].size + 1
          unless sura == @sura && number == expected
            raise ParseError, "#{@path}: #{id} where verse #{@sura}:#{expected} was due"
          end

          @verse = { sura: sura, number: number, words: [] }
        end

        def close_lg
          if @verse
            raise ParseError, "#{@path}: verse #{@sura}:#{@verse[:number]} has no words" if @verse[:words].empty?

            @suras[@sura] << @verse
            @verse = nil
          else
            raise ParseError, "#{@path}: sura #{@sura} has no verses" if @sura && @suras[@sura].empty?

            @sura = nil
          end
        end

        def open_word(node)
          id = node.attribute("xml:id").to_s
          raise ParseError, "#{@path}: word #{id.inspect} outside a verse" if @verse.nil?

          match = WORD_ID.match(id)
          sura, verse, number = match&.captures&.map(&:to_i)
          unless match && sura == @sura && verse == @verse[:number] && number == @verse[:words].size + 1
            raise ParseError, "#{@path}: word #{id.inspect} out of place in verse #{@sura}:#{@verse[:number]}"
          end

          @word = { id: id, number: number, form: +"" }
          close_word if node.empty_element?
        end

        def close_word
          form = @word[:form].strip
          raise ParseError, "#{@path}: word #{@word[:id]} is empty" if form.empty?

          @verse[:words] << Word.new(id: @word[:id], number: @word[:number], form: form)
          @word = nil
        end

        def finish(verse)
          Verse.new(sura: verse[:sura], number: verse[:number], page: page_of([verse[:sura], verse[:number]]),
                    words: verse[:words].freeze)
        end

        # The surface whose range holds +key+ ([sura, verse]): the last one
        # starting at or before it, if it also ends at or after it.
        def page_of(key)
          @sorted ||= @surfaces.sort_by { |_page, first, _last| first }
          index = @sorted.bsearch_index { |_page, first, _last| (first <=> key).positive? } || @sorted.size
          return nil if index.zero?

          page, _first, last = @sorted[index - 1]
          page if (key <=> last) <= 0
        end
      end
      private_constant :Walk
    end
  end
end
