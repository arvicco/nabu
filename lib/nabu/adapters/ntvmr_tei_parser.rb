# frozen_string_literal: true

require "nokogiri"

require_relative "../errors"
require_relative "../normalize"

module Nabu
  module Adapters
    # The ntvmr-tei parser family: one manuscript transcription as the INTF
    # New Testament Virtual Manuscript Room serves it (transcript/get,
    # format=teiraw — the IGNTP/ECM transcription TEI, censused first-hand on
    # the fixture answers of 2026-11-23, test/fixtures/ntvmr/README.md).
    #
    # == The shape
    #
    # teiHeader: titleStmt/title[@type=document]@n (the GA number), the
    # availability paragraphs (the copyright line and the CC BY 4.0 statement,
    # each a CDATA HTML snippet), msDesc/msIdentifier (country, settlement,
    # repository, idno — the manuscript's PRESENT holding, not its origin),
    # handNotes/listWit (firsthand, corrector1, corrector2a …). The body is a
    # stream of page milestones (pb n="001r" type="folio" | n="15"
    # type="page"; cb, lb) with book/chapter div wrappers re-opened per page,
    # and one ab per verse: n="B04K18V31" (INTF book number, chapter, verse —
    # the whole-manuscript pageID=ALL answer) or n="Phlm.1.1" (OSIS — the
    # indexContent answer). A verse a page break splits is two (or more) ab
    # elements with the same n and part="I" / "M" / "F"; a word the break
    # splits is w part="I" … w part="F" likewise.
    #
    # Inside ab: w (the words), pc (punctuation), app/rdg (a correction:
    # rdg type="orig" hand="firsthand" beside rdg type="corr"
    # hand="corrector…"), supplied (editorial restoration, with
    # source="na28" for the illegible), unclear, abbr type="nomSac" / "num"
    # wrapping hi rend="overline", gap, lb (break="no" inside a word).
    #
    # == The text policy (the cntr precedent, at the witness layer)
    #
    # The TEXT is the first hand's reading with restorations read through
    # (supplied and unclear letters are text), words space-joined,
    # punctuation as written attached to its word, a word-internal line or
    # page break joined. Nomina sacra and numerals stay AS WRITTEN (the
    # contracted χυ, ιυ — the overline is markup and drops; ex expansions,
    # notes, fw page furniture and space never enter the text — canonical
    # means canonical). A gap is one "[…]". In a correction the text takes
    # the first hand's rdg (type orig; failing one, the first rdg); every
    # rdg rides the "corrections" annotation as {"readings" => [{hand, type,
    # reading}, …]} (an empty reading is an omission — that hand wrote
    # nothing there).
    #
    # Per verse passage the annotations carry: tokens (one per word — form,
    # the nt hub's citation_part "JOHN 18.31", and only non-default marks:
    # supplied word|partial, abbreviation nomen-sacrum|numeral, unclear
    # letters, corrected), extant (the reading with every supplied stretch
    # collapsed to "[…]", only when it differs), leiden {supplied_chars,
    # unclear_chars, gaps} (zero counts omitted), corrections, pages (the pb
    # n values the verse sits on) and parts (the ab count, only when > 1).
    #
    # Verses are keyed by (book, chapter, verse); every ab sharing a key
    # merges into ONE passage in first-occurrence order. An ab whose n reads
    # no known verse key (or carries none) falls back to the PAGE grain: its
    # words join the page passage of the pb it opens on (key p<page n>).
    # Letterless verses mint no passage; they are counted.
    class NtvmrTeiParser
      # INTF book number (the B-prefix of ab n) → [OSIS name, sblgnt's urn
      # stem, the nt hub's work token]. NA order: B18 is Philemon, confirmed
      # on the 01 fixture's div type="book" n="B18" wrapping Phlm.1.1–25.
      BOOKS = {
        1 => %w[Matt matt MATT], 2 => %w[Mark mark MARK], 3 => %w[Luke luke LUKE], 4 => %w[John john JOHN],
        5 => %w[Acts acts ACTS], 6 => %w[Rom rom ROM], 7 => %w[1Cor 1cor 1COR], 8 => %w[2Cor 2cor 2COR],
        9 => %w[Gal gal GAL], 10 => %w[Eph eph EPH], 11 => %w[Phil phil PHIL], 12 => %w[Col col COL],
        13 => %w[1Thess 1thess 1THESS], 14 => %w[2Thess 2thess 2THESS], 15 => %w[1Tim 1tim 1TIM],
        16 => %w[2Tim 2tim 2TIM], 17 => %w[Titus titus TIT], 18 => %w[Phlm phlm PHILEM], 19 => %w[Heb heb HEB],
        20 => %w[Jas jas JAS], 21 => %w[1Pet 1pet 1PET], 22 => %w[2Pet 2pet 2PET], 23 => %w[1John 1john 1JOHN],
        24 => %w[2John 2john 2JOHN], 25 => %w[3John 3john 3JOHN], 26 => %w[Jude jude JUDE], 27 => %w[Rev rev REV]
      }.freeze
      OSIS = BOOKS.to_h { |number, (osis, _, _)| [osis, number] }.freeze
      INTF_KEY = /\AB(\d{2})K(\d+)V(\d+)\z/
      OSIS_KEY = /\A([1-3]?[A-Z][a-z]+)\.(\d+)\.(\d+)\z/
      GAP = "[…]"
      CC_BY = %r{creativecommons\.org/licenses/by/(\d\.\d)}

      # Elements whose content never enters the text.
      SKIPPED = %w[note fw ex space milestone lb cb pb comment].freeze

      Header = Data.define(:ga, :country, :settlement, :repository, :idno, :hands, :copyright,
                           :license_statement, :license_url, :language)
      Verse = Data.define(:key, :urn_tail, :citation, :text, :annotations)
      Result = Data.define(:header, :verses, :letterless, :page_passages)

      # One word under construction: its text and extant forms, and marks.
      class Word
        attr_accessor :text, :extant, :punct, :supplied_chars, :letter_chars, :unclear_chars,
                      :abbreviation, :corrected, :part, :gap

        def initialize
          @text = +""
          @extant = +""
          @punct = +""
          @supplied_chars = 0
          @letter_chars = 0
          @unclear_chars = 0
          @gap = false
        end

        def display = "#{text}#{punct}"
        def extant_display = "#{extant}#{punct}"
      end

      def self.parse(xml, label:)
        new(xml, label: label).parse
      end

      def initialize(xml, label:)
        @xml = xml
        @label = label
      end

      def parse
        error = @xml[/\A\s*(?:<\?xml[^>]*\?>\s*)?(<error\b[^>]*>)/, 1]
        raise ParseError, "#{@label}: an upstream error answer, not a transcription: #{error}" if error

        header = nil
        @groups = {}
        @page = nil
        skip_depth = nil
        reader = Nokogiri::XML::Reader(@xml)
        reader.each do |node|
          next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
          next if skip_depth && node.depth > skip_depth

          skip_depth = nil
          case node.local_name
          when "teiHeader"
            header = read_header(node.outer_xml)
            skip_depth = node.depth
          when "pb" then @page = node.attribute("n")
          when "ab"
            read_ab(node.outer_xml)
            skip_depth = node.depth
          end
        end
        raise ParseError, "#{@label}: no teiHeader" unless header

        finish(header)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{@label}: malformed TEI: #{e.message}"
      end

      private

      # -- header --------------------------------------------------------------

      def read_header(xml)
        doc = fragment(xml)
        ident = doc.at_xpath("//msIdentifier")
        paragraphs = doc.xpath("//publicationStmt/availability/p").map(&:text)
        statement = paragraphs.find { |p| p.match?(CC_BY) }
        Header.new(
          ga: clean(doc.at_xpath("//titleStmt/title[@type='document']")&.[]("n")),
          country: clean(ident&.at_xpath("country")&.text), settlement: clean(ident&.at_xpath("settlement")&.text),
          repository: clean(ident&.at_xpath("repository")&.text), idno: clean(ident&.at_xpath("idno")&.text),
          hands: doc.xpath("//handNotes//witness").filter_map { |w| clean(w["n"]) },
          copyright: clean(paragraphs.map { |p| strip_html(p) }.find { |p| p.start_with?("(C)") }),
          license_statement: statement && clean(strip_html(statement)),
          license_url: statement && statement[%r{https?://creativecommons\.org/licenses/by/\d\.\d/?}],
          language: clean(doc.at_xpath("//langUsage/language")&.[]("ident"))
        )
      end

      def strip_html(text) = Nokogiri::HTML.fragment(text).text.gsub(/[[:space:]]+/, " ").strip

      def clean(value)
        text = value.to_s.gsub(/[[:space:]]+/, " ").strip
        text.empty? ? nil : Normalize.nfc(text)
      end

      def fragment(xml)
        doc = Nokogiri::XML(xml, &:strict)
        doc.remove_namespaces!
        doc
      end

      # -- body ----------------------------------------------------------------

      # One ab → its words appended to its verse (or page) group.
      def read_ab(xml)
        ab = fragment(xml).root
        key = verse_key(ab["n"])
        group_key = key || [:page, @page.to_s]
        group = (@groups[group_key] ||= { key: key, page: @page, words: [], corrections: [], pages: [], parts: 0,
                                          gaps: 0, n: ab["n"] })
        group[:parts] += 1
        group[:pages] << @page unless @page.nil? || group[:pages].last == @page
        @group = group
        walk(ab, corrected: false, supplied: false)
      end

      def verse_key(label)
        if (match = INTF_KEY.match(label.to_s))
          book = Integer(match[1], 10)
        elsif (match = OSIS_KEY.match(label.to_s))
          book = OSIS[match[1]]
        end
        return nil unless match && BOOKS.key?(book)

        [book, Integer(match[2], 10), Integer(match[3], 10)]
      end

      # The ab-level walk: words, punctuation, corrections, gaps, wrappers.
      def walk(node, corrected:, supplied:)
        node.children.each do |child|
          if child.text?
            loose_text(child.text, supplied: supplied)
            next
          end
          next unless child.element?

          case child.name
          when "w" then add_word(child, corrected: corrected, supplied: supplied)
          when "pc" then punctuate(child.text)
          when "app" then read_app(child, supplied: supplied)
          when "gap" then add_gap
          when "pb"
            @page = child["n"]
            @group[:pages] << @page unless @page.nil? || @group[:pages].last == @page
          when *SKIPPED then next
          else walk(child, corrected: corrected, supplied: supplied || child.name == "supplied")
          end
        end
      end

      # Non-whitespace text outside any w (rare): one word of it per run.
      def loose_text(text, supplied:)
        text.split(/[[:space:]]+/).reject(&:empty?).each do |piece|
          word = Word.new
          letters!(word, piece, supplied: supplied, unclear: false)
          push(word)
        end
      end

      def add_word(element, corrected:, supplied:)
        word = Word.new
        word.part = element["part"]
        word.corrected = true if corrected
        build_word(element, word, supplied: supplied, unclear: false)
        return if word.text.empty? && !word.gap

        push(word)
      end

      def push(word)
        words = @group[:words]
        previous = words.last
        if previous && %w[I M].include?(previous.part) && %w[M F].include?(word.part)
          join!(previous, word)
        else
          words << word
        end
      end

      # A page-split word's halves become one word.
      def join!(previous, word)
        previous.text << word.text
        previous.extant << word.extant
        previous.punct = word.punct
        %i[supplied_chars letter_chars unclear_chars].each do |field|
          previous.public_send(:"#{field}=", previous.public_send(field) + word.public_send(field))
        end
        previous.abbreviation ||= word.abbreviation
        previous.corrected ||= word.corrected
        previous.part = word.part
      end

      def build_word(node, word, supplied:, unclear:)
        node.children.each do |child|
          if child.text?
            letters!(word, child.text.gsub(/[[:space:]]+/, ""), supplied: supplied, unclear: unclear)
            next
          end
          next unless child.element?

          case child.name
          when *SKIPPED then next
          when "gap"
            word.text << GAP
            word.extant << GAP
            word.gap = true
            @group[:gaps] += 1
          when "abbr"
            word.abbreviation ||= { "nomSac" => "nomen-sacrum", "num" => "numeral" }[child["type"]]
            build_word(child, word, supplied: supplied, unclear: unclear)
          else
            build_word(child, word, supplied: supplied || child.name == "supplied",
                                    unclear: unclear || child.name == "unclear")
          end
        end
      end

      def letters!(word, text, supplied:, unclear:)
        return if text.empty?

        word.text << text
        count = text.scan(/\p{L}/).size
        word.letter_chars += count
        if supplied
          word.supplied_chars += count
          word.extant << GAP unless word.extant.end_with?(GAP)
        else
          word.extant << text
          word.unclear_chars += count if unclear
        end
      end

      def punctuate(text)
        mark = text.to_s.strip
        return if mark.empty?

        last = @group[:words].last
        if last
          last.punct << mark
        else
          word = Word.new
          word.punct << mark
          @group[:words] << word
        end
      end

      def add_gap
        word = Word.new
        word.text << GAP
        word.extant << GAP
        word.gap = true
        @group[:gaps] += 1
        @group[:words] << word
      end

      # A correction: the text takes the first hand (rdg type orig, else the
      # first rdg); every rdg's reading rides the corrections annotation.
      def read_app(app, supplied:)
        readings = app.xpath("./rdg")
        chosen = readings.find { |rdg| rdg["type"] == "orig" } || readings.first
        @group[:corrections] << { "readings" => readings.map do |rdg|
          { "hand" => rdg["hand"], "type" => rdg["type"], "reading" => reading_text(rdg) }.compact
        end }
        walk(chosen, corrected: true, supplied: supplied) if chosen
      end

      # A rdg's reading as plain text (words space-joined; empty = omission).
      def reading_text(rdg)
        saved = @group
        @group = { words: [], corrections: [], pages: [], gaps: 0, parts: 0 }
        walk(rdg, corrected: true, supplied: false)
        text = @group[:words].map(&:display).join(" ")
        @group = saved
        Normalize.nfc(text)
      end

      # -- assembly ------------------------------------------------------------

      def finish(header)
        verses = []
        letterless = 0
        pages = 0
        @groups.each_value do |group|
          text = Normalize.nfc(group[:words].map(&:display).reject(&:empty?).join(" "))
          next letterless += 1 unless text.match?(/\p{L}/)

          pages += 1 unless group[:key]
          verses << verse_for(group, text)
        end
        Result.new(header: header, verses: verses, letterless: letterless, page_passages: pages)
      end

      def verse_for(group, text)
        if group[:key]
          book, chapter, verse = group[:key]
          _, stem, token = BOOKS.fetch(book)
          tail = "#{stem}.#{chapter}.#{verse}"
          citation = "#{token} #{chapter}.#{verse}"
        else
          tail = "p#{page_slug(group[:page])}"
        end
        Verse.new(key: group[:key], urn_tail: tail, citation: citation, text: text,
                  annotations: annotations(group, text, citation))
      end

      def page_slug(page)
        slug = page.to_s.downcase.gsub(/[^\p{Alnum}]+/, "-").gsub(/\A-|-\z/, "")
        slug.empty? ? "0" : slug
      end

      def annotations(group, text, citation)
        words = group[:words].reject { |word| word.text.empty? || word.gap }
        extant = Normalize.nfc(group[:words].map(&:extant_display).reject(&:empty?).join(" ")
                                            .gsub(/#{Regexp.escape(GAP)}(?:\s*#{Regexp.escape(GAP)})+/o, GAP))
        leiden = { "supplied_chars" => words.sum(&:supplied_chars), "unclear_chars" => words.sum(&:unclear_chars),
                   "gaps" => group[:gaps] }.reject { |_, count| count.zero? }
        {
          "tokens" => words.map { |word| token(word, citation) },
          "extant" => extant == text ? nil : extant,
          "leiden" => leiden.empty? ? nil : leiden,
          "corrections" => group[:corrections].empty? ? nil : group[:corrections],
          "pages" => group[:pages].empty? ? nil : group[:pages],
          "parts" => group[:parts] > 1 ? group[:parts] : nil,
          "page" => group[:key] ? nil : group[:page],
          "n" => group[:key] ? nil : group[:n]
        }.compact
      end

      def token(word, citation)
        token = { "form" => Normalize.nfc(word.text) }
        token["citation_part"] = citation if citation
        if word.supplied_chars.positive?
          token["supplied"] = word.supplied_chars >= word.letter_chars ? "word" : "partial"
        end
        token["abbreviation"] = word.abbreviation if word.abbreviation
        token["unclear"] = word.unclear_chars if word.unclear_chars.positive?
        token["corrected"] = true if word.corrected
        token
      end
    end
  end
end
