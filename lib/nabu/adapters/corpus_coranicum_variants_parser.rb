# frozen_string_literal: true

require "nokogiri"

require_relative "source_read"

module Nabu
  module Adapters
    # The variant readings of the Corpus Coranicum TEI export
    # (data/quran_variants/, the family corpus-coranicum-tei): Michael
    # Marx's database of the readings (qirāʾāt) the classical sources
    # ascribe to named readers, with its reader authority file.
    #
    # == Upstream shape (the whole directory, census 2026-11-27)
    #
    # allvariants.xml (8.0 MB — over the house DOM threshold, streamed with
    # Nokogiri::XML::Reader): body > list > 18,000 <item xml:id="variant_N">
    # (N 28–18306), each one reading: 0–17 <persName key="variantreader_K">
    # (the readers it is ascribed to, the authority's display name as
    # text), one <title key="variantsource_"/> (the source key — blank on
    # all 18,000), one <ab> of 0–43 <w n="SSS:VVV:WWW"> (the words the
    # reading touches, always inside ONE verse, in verse order but not
    # always contiguous — 1,693 items skip words), each word's text the
    # reading in the project's DMG-style transliteration ("…" = the word
    # reads as the standard; "|" separates the alternatives one source
    # gives), the inner <w xml:lang="ara"/> empty on all 34,172 words.
    #
    # reader.xml (1.1 MB, DOM): listPerson of 870 <person
    # xml:id="variantsreader_K"> — name type="main" (the full name, often
    # with the death year), name type="display" (the name the items
    # print), an empty Arabic name, <residence>, <note type="sigle"> (Marx's
    # sigle), <death> (prose: "796", "st. 202 AH = 817/818", "758 oder
    # 770"), and a note (the reader's sources — Ibn al-Ǧazarī's Ġāyat
    # an-Nihāya and aḏ-Ḏahabī's Maʿrifat al-qurrāʾ excerpted verbatim).
    #
    # Strict, never guessed: an element outside this census inside an item,
    # a word key of another shape, a reader key the authority lacks, or an
    # item spanning two verses is a ParseError naming it.
    class CorpusCoranicumVariantsParser
      Word = Data.define(:key, :sura, :verse, :number, :form)
      Item = Data.define(:id, :readers, :words)
      Reader = Data.define(:id, :name, :full_name, :residence, :sigle, :death, :note)

      TEI = { "t" => "http://www.tei-c.org/ns/1.0" }.freeze
      XML_ID = "http://www.w3.org/XML/1998/namespace"
      WORD_KEY = /\A(\d{3}):(\d{3}):(\d{3})\z/
      READER_KEY = /\Avariantreader_(\d+)\z/
      AUTHORITY_ID = /\Avariantsreader_(\d+)\z/
      ITEM_ELEMENTS = %w[persName title ab w].freeze
      private_constant :TEI, :XML_ID, :WORD_KEY, :READER_KEY, :AUTHORITY_ID, :ITEM_ELEMENTS

      READER = Nokogiri::XML::Reader
      private_constant :READER

      # The reading items in file order.
      def items(path)
        ItemWalk.new(path).call
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # {"12" => Reader} from reader.xml, in authority order.
      def readers(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "corpus-coranicum readers"), path) { |c| c.strict.nonet }
        doc.xpath("//t:listPerson/t:person", TEI).to_h do |person|
          id = person.attribute_with_ns("id", XML_ID).to_s
          match = AUTHORITY_ID.match(id) or raise ParseError, "#{path}: reader id #{id.inspect}"
          field = ->(xpath) { squeeze(person.at_xpath(xpath, TEI)&.text) }
          [match[1], Reader.new(id: match[1], name: field.call("t:name[@type='display']"),
                                full_name: field.call("t:name[@type='main']"), residence: field.call("t:residence"),
                                sigle: field.call("t:note[@type='sigle']"), death: field.call("t:death"),
                                note: field.call("t:note[not(@type)]"))]
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def self.squeeze(text)
        value = text.to_s.gsub(/[[:space:]]+/, " ").strip
        value.empty? ? nil : value
      end

      def squeeze(text) = self.class.squeeze(text)

      # The reader's death as a CE upper bound — the readings ascribed to
      # him are his by the time he died — or nil when the prose names no
      # CE year honestly readable (the census of all 238 non-empty <death>
      # values, 2026-11-27):
      # - a CE century "(8. Jh.)" / "2./8. Jhdt." → its last year (800);
      #   an AH-only century ("ca. 4. Jhdt. AH") → nil;
      # - else the years inside parentheses ("st. 190 (805-6)" → 806), else
      #   those after "=" ("168 AH = 784-785" → 785) — upstream's CE gloss of
      #   an AH date; else an "AH" anywhere → nil (AH only: "st. 65 AH");
      #   an "a/b" pair whose second half lies 570–640 years later is AH/CE
      #   ("st. ca. 345/956" → 956);
      # - else the bare years ("758 oder 770", "914, 915, 916", "vor 709");
      # - "nach 816" / "oder später" (died AFTER a year) bound nothing → nil.
      # Years outside 600–1500 never count (a two- or three-digit number
      # below 600 is an AH year no Qurʾān reader's CE death can be); a
      # two-digit second half ("744-5", "790/91") completes from the first.
      # The bound is the LATEST year named (the alternatives' envelope).
      def self.death_bound(text)
        text = text.to_s
        return nil if text.match?(/\bnach\s+\d|oder später/)

        if (century = text[%r{\d+\./(\d+)\.\s*Jh}, 1] || text[/\((\d+)\.\s*Jh\.?\)/, 1])
          return Integer(century, 10) * 100
        end
        return nil if text.include?("Jh")

        years = ce_years(text)
        years&.grep(600..1500)&.max
      end

      def self.ce_years(text)
        inner = text.scan(/\(([^()]*)\)/).flatten.join(" ")
        return expand(inner) if inner.match?(/\d{3}/)
        return expand(text.split("=", 2).last) if text.include?("=")

        if (pair = text.match(%r{(\d{2,3})/(\d{3,4})})) && (pair[2].to_i - pair[1].to_i).between?(570, 640)
          return [pair[2].to_i]
        end
        return nil if text.include?("AH")

        expand(text)
      end

      # Every year in +text+, a two-digit second half after "-" or "/"
      # completed from the year before it ("744-5" → 744, 745).
      def self.expand(text)
        text.scan(%r{(\d{3,4})(?:\s*[-/]\s*(\d{1,4}))?}).flat_map do |first, second|
          years = [first.to_i]
          if second
            years << (second.size < first.size ? (first[0, first.size - second.size] + second).to_i : second.to_i)
          end
          years
        end
      end
      private_class_method :ce_years, :expand

      # One Reader pass over allvariants.xml (class note).
      class ItemWalk
        def initialize(path)
          @path = path
          @items = []
          @item = nil
          @word = nil
        end

        def call
          xml = SourceRead.utf8_file(@path, label: "corpus-coranicum variants")
          Nokogiri::XML::Reader(xml, @path).each { |node| process(node) }
          @items
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start(node)
          when READER::TYPE_END_ELEMENT then stop(node)
          when READER::TYPE_TEXT, READER::TYPE_CDATA then text(node)
          end
        end

        def start(node)
          name = node.local_name
          return open_item(node) if name == "item"
          return if @item.nil?

          raise ParseError, "#{@path}: unexpected <#{name}> in #{@item[:id]}" unless ITEM_ELEMENTS.include?(name)

          case name
          when "persName" then reader(node)
          when "w" then open_word(node)
          end
        end

        def stop(node)
          case node.local_name
          when "item" then close_item
          when "w" then close_word
          end
        end

        def text(node)
          @word[:text] << node.value if @word
        end

        def open_item(node)
          @item = { id: node.attribute("xml:id").to_s, readers: [], words: [] }
        end

        def reader(node)
          key = node.attribute("key").to_s
          match = READER_KEY.match(key) or raise ParseError, "#{@path}: #{@item[:id]} reader key #{key.inspect}"
          @item[:readers] << match[1]
        end

        # The outer <w n> opens a word; the inner <w xml:lang="ara"/> (empty
        # on all 34,172) nests one level down and contributes nothing.
        def open_word(node)
          if @word
            raise ParseError, "#{@path}: #{@item[:id]} nests a non-empty <w>" unless node.empty_element?

            return
          end
          @word = { key: node.attribute("n").to_s, text: +"" }
          close_word if node.empty_element?
        end

        def close_word
          return if @word.nil?

          @item[:words] << finish_word(@word)
          @word = nil
        end

        def finish_word(word)
          match = WORD_KEY.match(word[:key]) or
            raise ParseError, "#{@path}: #{@item[:id]} word key #{word[:key].inspect}"
          sura, verse, number = match.captures.map(&:to_i)
          Word.new(key: word[:key], sura: sura, verse: verse, number: number,
                   form: CorpusCoranicumVariantsParser.squeeze(word[:text]).to_s)
        end

        def close_item
          verses = @item[:words].map { |word| [word.sura, word.verse] }.uniq
          raise ParseError, "#{@path}: #{@item[:id]} spans verses #{verses.inspect}" if verses.size > 1

          @items << Item.new(id: @item[:id], readers: @item[:readers].freeze, words: @item[:words].freeze)
          @item = nil
        end
      end
      private_constant :ItemWalk
    end
  end
end
