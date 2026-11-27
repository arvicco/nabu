# frozen_string_literal: true

require "nokogiri"

require_relative "source_read"

module Nabu
  module Adapters
    # One manuscript record of the Corpus Coranicum TEI export
    # (data/quran_manuscripts/manuscript-NNNNN.xml, the family
    # corpus-coranicum-tei): the codicological header (msDesc) and, where
    # the project transcribed the manuscript, its rasm transcription word by
    # word — the witness layer beside the Cairo text.
    #
    # == Upstream shape (all 2,322 records read, census 2026-11-27)
    #
    # <body> holds <pb xml:id="f.1r"/> folio-side breaks and <l n="1"> lines;
    # each line carries one <note> (the transcriber's line note — mostly the
    # Cairo vocalized forms of the line's words, sometimes a German remark)
    # and the words <w n="SSS-VVV-WWW"> between <pc> separators (a space,
    # an NBSP or the Arabic full stop ۔ U+06D4 — the transcription's word
    # spacing and the project's verse-division sign, never text). Inside a
    # word: text, <supplied reason="omitted-in-original"|"illigible"
    # source="#cairo_rasm"> (letters not on the page — lost, omitted or
    # illegible — supplied from the Cairo rasm), <unclear>, <add type="rasm"
    # [subtype="variant"]> (letters added on the page), <mod rend="…">
    # (letters modified) and <del> (letters struck out). A word broken by the
    # line end repeats its key on the next line (the upstream comment
    # "Continued from last line"). Keys that are not a verse word: n =
    # "000-000-000" — the verse-division and tenth/fifth markers (۝ with the
    # Cairo verse number, ornaments), never Qurʾān text; verse 000 —
    # the sura heading band (title, verse count, basmala; 22 of them keyed
    # "SSS-000--01"); word 000 — a verse word whose ordinal the transcriber
    # left open; 4 words carry no key at all (manuscript-00548's basmala);
    # one ornament line is keyed "000-0010-000". The metadata-only records
    # have an empty body or <p>(No content available)</p>.
    #
    # == What this parser returns
    #
    # Manuscript(header:, verses:, unkeyed:, unplaced_markers:) — the header
    # fields as plain values (the adapter maps them onto metadata), and one
    # Verse per (sura, verse) in order of FIRST appearance (a manuscript's
    # folios need not run in Qurʾān order). A sura heading is verse 0. Word
    # rendering (the house Leiden policy, conventions.md §5 / the DdbdpParser
    # header): text, supplied, unclear, add and mod READ THROUGH; <del>
    # renders inside ⟦…⟧; whitespace inside a word is the file's layout and
    # drops. Each word also renders its EXTANT form — every supplied stretch
    # one "[…]" — and counts its supplied / unclear / added / modified
    # letters (non-whitespace grapheme clusters, the DDbDP count). Adjacent
    # fragments under one key join into one word (the line-break split; never
    # a word-000 key, whose repeats are different words). Markers attach to
    # the verse they follow (Verse#markers); one before any verse word is
    # counted in unplaced_markers. A verse whose words come back after
    # another verse intervened (a heading band, a folio that repeats or
    # resumes a verse) MERGES in file order — the CntrMesParser precedent —
    # with Verse#stretches counting the runs and Verse#repeated_words the
    # keys more than one run carries.
    #
    # Strict, never guessed: an element outside the census above, a word
    # outside a line or before the first <pb>, or a key of no known shape
    # is a ParseError naming it. The largest record is 3.6 MB
    # (manuscript-00012.xml) — under the house DOM threshold, so a DOM read
    # over the belt-read string.
    class CorpusCoranicumManuscriptParser
      Word = Data.define(:key, :form, :extant, :supplied, :unclear, :added, :modified, :cancelled,
                         :unclear_word, :parts)

      Verse = Data.define(:sura, :verse, :words, :markers, :lines, :line_notes, :stretches, :repeated_words) do
        def text = words.map(&:form).join(" ")

        # The verse as the page shows it: every supplied stretch one "[…]",
        # adjacent markers collapsed.
        def extant = words.map(&:extant).join(" ").gsub(GAP_RUN, GAP)
      end

      Manuscript = Data.define(:header, :verses, :unkeyed, :unplaced_markers, :empty_words)

      GAP = "[…]"
      GAP_RUN = /\[…\](?:\s*\[…\])+/
      TEI = { "t" => "http://www.tei-c.org/ns/1.0" }.freeze
      XML_ID = "http://www.w3.org/XML/1998/namespace"
      VERSE_KEY = /\A(\d{3})-(\d{3})-(\d{3})\z/
      HEADING_KEY = /\A(\d{3})-000-/
      FOLIO_ID = /\Af\.(.+)\z/
      WORD_PARTS = %w[supplied unclear add mod del].freeze
      SUPPLIED_REASONS = %w[omitted-in-original illigible].freeze
      private_constant :TEI, :XML_ID, :VERSE_KEY, :HEADING_KEY, :FOLIO_ID, :WORD_PARTS, :SUPPLIED_REASONS

      # Does the record carry a transcription (a <w> in its body)? A cheap
      # byte test for discovery: no header element is named w.
      def self.transcribed?(xml) = xml.include?("<w ")

      def parse(path)
        xml = SourceRead.utf8_file(path, label: "corpus-coranicum manuscript")
        doc = Nokogiri::XML(xml, path) { |config| config.strict.nonet }
        Manuscript.new(header: header(doc), **Body.new(path, doc.at_xpath("//t:text/t:body", TEI)).call)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # The repository authority (data/quran_manuscripts/places.xml):
      # {"16" => {"name", "settlement", "country", "geonames"}} — the
      # holding libraries, a PRESENT location each.
      def repositories(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "corpus-coranicum places"), path) { |c| c.strict.nonet }
        doc.xpath("//t:body/t:list/t:item", TEI).to_h do |item|
          id = item.attribute_with_ns("id", XML_ID).to_s
          title = item.at_xpath("t:title", TEI)
          geonames = title&.[]("key").to_s.delete_prefix("geoname_")
          address = ->(part) { squeeze(item.at_xpath("t:address/t:#{part}", TEI)&.text) }
          [id.delete_prefix("repository_"),
           { "name" => squeeze(title&.text), "settlement" => address.call("settlement"),
             "country" => address.call("country"), "geonames" => geonames.empty? ? nil : geonames }.compact]
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def self.squeeze(text)
        value = text.to_s.gsub(/[[:space:]]+/, " ").strip
        value.empty? ? nil : value
      end

      private

      def squeeze(text) = self.class.squeeze(text)

      def header(doc)
        desc = doc.at_xpath("//t:sourceDesc/t:msDesc", TEI) or raise ParseError, "no msDesc"
        repository = desc.at_xpath("t:msIdentifier/t:repository", TEI)
        {
          "record_id" => doc.root.attribute_with_ns("id", XML_ID)&.value,
          "title" => squeeze(doc.at_xpath("//t:titleStmt/t:title", TEI)&.text),
          "repository_key" => repository&.[]("key"), "repository_text" => squeeze(repository&.text),
          "shelfmark" => squeeze(desc.at_xpath("t:msIdentifier/t:idno", TEI)&.text),
          "summary" => desc.xpath("t:msContents/t:summary/t:p", TEI).filter_map { |p| squeeze(p.text) },
          "contents" => desc.xpath("t:msContents/t:msItem", TEI).filter_map { |item| content(item) },
          "material" => squeeze(desc.at_xpath(".//t:supportDesc", TEI)&.[]("material")),
          "extent" => extent(desc.at_xpath(".//t:supportDesc/t:extent", TEI)),
          "width" => squeeze(desc.at_xpath(".//t:dimensions/t:width", TEI)&.text),
          "height" => squeeze(desc.at_xpath(".//t:dimensions/t:height", TEI)&.text),
          "dimensions_unit" => desc.at_xpath(".//t:dimensions", TEI)&.[]("unit"),
          "written_lines" => desc.at_xpath(".//t:layout", TEI)&.[]("writtenLines"),
          "support" => squeeze(desc.at_xpath(".//t:objectDesc/t:supportDesc/t:support", TEI)&.text),
          "script" => squeeze(desc.at_xpath(".//t:scriptNote", TEI)&.text),
          "orig_date_text" => squeeze(desc.at_xpath("t:history/t:origin/t:origDate", TEI)&.text),
          "provenance" => squeeze(desc.at_xpath("t:history/t:provenance", TEI)&.text),
          "record_history" => desc.xpath(".//t:recordHist/t:p", TEI).filter_map { |p| squeeze(p.text) },
          "image_credits" => doc.xpath("//t:publicationStmt/t:availability", TEI).filter_map { |a| squeeze(a.text) },
          "transcription_file" => doc.at_xpath("//t:text/t:body", TEI)&.[]("source")
        }
      end

      # The extent's own text ("Folios: 121"), its <dimensions> child aside.
      def extent(node) = node && squeeze(node.children.select(&:text?).map(&:text).join)

      def content(item)
        range = squeeze(item.at_xpath("t:title", TEI)&.[]("key"))
        range && { "folio" => item["n"].to_s, "range" => range }
      end

      # The body walk (class note).
      class Body
        def initialize(path, body)
          @path = path
          @body = body
          @folio = nil
          @line = nil
          @words = []
          @notes = {}
          @unkeyed = 0
        end

        def call
          return { verses: [], unkeyed: 0, unplaced_markers: 0, empty_words: 0 } if @body.nil?

          @body.element_children.each do |child|
            case child.name
            when "pb" then @folio = folio_of(child)
            when "l" then line(child)
            when "p" then nil # the metadata-only record's "(No content available)"
            else raise ParseError, "#{@path}: unexpected <#{child.name}> in the body"
            end
          end
          group(join_fragments(@words))
        end

        private

        def folio_of(node)
          id = node.attribute_with_ns("id", XML_ID).to_s
          match = FOLIO_ID.match(id) or raise ParseError, "#{@path}: <pb> id #{id.inspect} is not f.<folio>"
          match[1]
        end

        def line(node)
          raise ParseError, "#{@path}: a line before the first <pb>" if @folio.nil?

          @line = "#{@folio}.#{node['n']}"
          node.element_children.each do |child|
            case child.name
            when "note" then (note = squeeze(child.text)) && (@notes[@line] = note)
            when "w" then word(child)
            when "pc" then nil # word spacing / the ۔ division sign (class note)
            else raise ParseError, "#{@path}: unexpected <#{child.name}> in line #{@line}"
            end
          end
        end

        def squeeze(text) = CorpusCoranicumManuscriptParser.squeeze(text)

        # One <w>: [kind, sura, verse, word key, rendering, line].
        def word(node)
          key = node["n"].to_s
          kind, sura, verse = classify(key)
          return @unkeyed += 1 if kind == :unkeyed

          @words << { kind: kind, sura: sura, verse: verse, key: key, line: @line,
                      render: render(node).merge(unclear_word: node["type"] == "unclear") }
        end

        def classify(key)
          return [:unkeyed] if key.empty?
          return [:marker] if key.start_with?("000-")

          if (match = VERSE_KEY.match(key))
            sura, verse = match.captures.first(2).map(&:to_i)
            return [verse.zero? ? :heading : :verse, sura, verse]
          end
          return [:heading, HEADING_KEY.match(key)[1].to_i, 0] if HEADING_KEY.match?(key)

          raise ParseError, "#{@path}: word key #{key.inspect} in line #{@line} has no known shape"
        end

        # The word's reading, extant form and letter counts (class note).
        def render(node)
          out = { form: +"", extant: +"", supplied: 0, unclear: 0, added: 0, modified: 0, cancelled: false }
          node.children.each { |child| part(child, out) }
          out[:form] = out[:form].gsub(/[[:space:]]+/, "")
          out[:extant] = out[:extant].gsub(/[[:space:]]+/, "")
          out
        end

        def part(child, out)
          return append(out, child.text, child.text) if child.text?
          return unless child.element?

          name = child.name
          raise ParseError, "#{@path}: unexpected <#{name}> in a word of line #{@line}" unless WORD_PARTS.include?(name)

          text = child.text
          letters = graphemes(text)
          case name
          when "supplied"
            unless SUPPLIED_REASONS.include?(child["reason"])
              raise ParseError, "#{@path}: <supplied reason=#{child['reason'].inspect}> in line #{@line}"
            end

            out[:supplied] += letters
            append(out, text, letters.zero? ? "" : GAP)
          when "del"
            out[:cancelled] = true
            append(out, "⟦#{text}⟧", "⟦#{text}⟧")
          else
            out[{ "unclear" => :unclear, "add" => :added, "mod" => :modified }.fetch(name)] += letters
            append(out, text, text)
          end
        end

        def append(out, form, extant)
          out[:form] << form
          out[:extant] << extant
        end

        def graphemes(text) = text.scan(/\X/).count { |cluster| !cluster.match?(/\A[[:space:]]+\z/) }

        # Adjacent same-key fragments (not word 000, not markers) → one word.
        def join_fragments(words)
          words.each_with_object([]) do |word, joined|
            last = joined.last
            if last && word[:key] == last[:key] && word[:kind] != :marker && !word[:key].end_with?("-000")
              last[:render] = merge(last[:render], word[:render])
              last[:parts] += 1
              last[:lines] |= [word[:line]]
            else
              joined << word.merge(parts: 1, lines: [word[:line]])
            end
          end
        end

        def merge(left, right)
          { form: left[:form] + right[:form], extant: left[:extant] + right[:extant],
            supplied: left[:supplied] + right[:supplied], unclear: left[:unclear] + right[:unclear],
            added: left[:added] + right[:added], modified: left[:modified] + right[:modified],
            cancelled: left[:cancelled] || right[:cancelled],
            unclear_word: left[:unclear_word] || right[:unclear_word] }
        end

        def group(words)
          verses = {}
          current = nil
          unplaced = 0
          empty = 0
          words.each do |word|
            next empty += 1 if word[:render][:form].empty?

            if word[:kind] == :marker
              current ? current[:markers] << word[:render][:form] : unplaced += 1
              next
            end
            id = [word[:sura], word[:verse]]
            verse = verses[id] ||= { words: [], markers: [], lines: [], runs: [] }
            verse[:runs] << [] unless current.equal?(verse)
            verse[:runs].last << word[:key]
            verse[:words] << finish(word)
            verse[:lines] |= word[:lines]
            current = verse
          end
          { verses: verses.map { |id, verse| build(id, verse) }, unkeyed: @unkeyed, unplaced_markers: unplaced,
            empty_words: empty }
        end

        def finish(word)
          render = word[:render]
          Word.new(key: word[:key], form: render[:form], extant: render[:extant].gsub(GAP_RUN, GAP),
                   supplied: render[:supplied],
                   unclear: render[:unclear], added: render[:added], modified: render[:modified],
                   cancelled: render[:cancelled], unclear_word: render[:unclear_word], parts: word[:parts])
        end

        def build(id, verse)
          runs = verse[:runs].map(&:uniq)
          repeated = runs.flatten.tally.count { |_key, count| count > 1 }
          notes = verse[:lines].filter_map { |line| [line, @notes[line]] if @notes[line] }.to_h
          Verse.new(sura: id[0], verse: id[1], words: verse[:words].freeze, markers: verse[:markers].freeze,
                    lines: verse[:lines].freeze, line_notes: notes, stretches: runs.size, repeated_words: repeated)
        end
      end
      private_constant :Body
    end
  end
end
