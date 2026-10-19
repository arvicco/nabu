# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The papyri translation parser family: one translation file of the
    # idp.data clone → one translation Nabu::Document. Two file shapes share
    # the body: Translations/<bucket>/<HGV>-<n>.xml (the HGV, DDbDP and —
    # since upstream's 2026-07 pull-out — APIS translations, EpiDoc) and
    # the APIS/ record that still carries its translation div. Both are
    # small (≤ 110 KB, census 2026-10-19), so DOM.
    #
    # == Passages: the translator's own line milestones
    #
    # HGV translations mark where the edition's lines begin inside the
    # running prose (<milestone unit="line" n="6"/>), under textpart divs
    # (r/v, columns, fragments). Each milestone opens a passage cited
    # <textpart path>:<n> — the SAME suffix shape DdbdpParser mints for
    # the edition's lines, so `--parallel` anchors the translation on the
    # original's lines with no alignment table. @n is minted as published
    # (canonical means canonical): where upstream's 2026-10 edition-side
    # schema pass rewrote textpart labels ("r,Fr1" → "r1") and the
    # translation still carries the old label, the anchor simply misses
    # and the row renders one-sided — honest, never patched. A repeated
    # (path, n) in one file opens a restart block (b<k>:, the edition's
    # own restart shape) so urns stay unique.
    #
    # Prose with no line milestone — the APIS block translations (one <ab>,
    # 5,214 of 8,005 divs) and text before a file's first milestone — is a
    # block passage <path>:p<k> (k counted per document): it cites no line,
    # so it never claims an anchor it does not have.
    #
    # == Text
    #
    # Running text verbatim, whitespace collapsed, NFC at this boundary:
    # <lem> read (its <app> carries no rdg in translations), <term>/
    # <foreign>/<emph>/<del>/<surplus>/<ref> read as text, <lb/> a space,
    # <gap/> the house lacuna marker "[…]" (DdbdpParser's), <certainty/>
    # nothing. <note> is the translator's aside — kept OUT of the line text
    # and carried per passage as annotation "notes" (verbatim).
    #
    # == Language
    #
    # The translation div's xml:lang (every Translations/ div carries one),
    # else — an APIS record's div carries none — the first translation
    # language the record's <langUsage> names (APIS: "en"). LANGUAGES maps
    # upstream's ISO 639-1 tags to the house codes; it includes the two
    # misspelt tags upstream ships, folded by content: "fe" (88604-1 and its
    # misnamed twin — French prose, "Capito à Cornelius, son frère") and
    # "ge" (91681-1 — German prose, "Schiedsverfahren unter Phidias").
    # An unmapped tag is a ParseError (quarantine), never a guess.
    class PapyriTranslationParser
      LANGUAGES = {
        "en" => "eng", "de" => "deu", "fr" => "fra", "it" => "ita", "es" => "spa",
        "ar" => "ara", "el" => "ell", "pl" => "pol", "bg" => "bul",
        "fe" => "fra", "ge" => "deu"
      }.freeze

      GAP_MARKER = "[…]"
      private_constant :GAP_MARKER

      # The translation language of +path+ (house code), or nil when the
      # file carries none this parser maps — the adapter's discover-time
      # peek uses the same rule as parse.
      def self.language_of(doc)
        div = doc.at_xpath("//body/div[@type='translation']")
        tag = div && div["lang"] # xml:lang, its prefix stripped by .load
        tag ||= doc.xpath("//profileDesc/langUsage/language/@ident").map(&:value).find { |code| LANGUAGES.key?(code) }
        LANGUAGES[tag]
      end

      def self.load(path)
        doc = Nokogiri::XML(File.read(path, encoding: "UTF-8")) { |config| config.strict.nonet }
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # +metadata+ (the adapter's: translation_of, translation_id, …) is
      # merged under the parser's own provenance fields.
      def parse(path, urn:, metadata: {})
        doc = self.class.load(path)
        language = self.class.language_of(doc) or
          raise Nabu::ParseError, "#{path}: no translation language this parser maps"
        divs = doc.xpath("//body/div[@type='translation']")
        segments = Walk.new.run(divs)
        document = Nabu::Document.new(
          urn: urn, language: language, canonical_path: path,
          title: clean(doc.at_xpath("//teiHeader/fileDesc/titleStmt/title")&.text),
          metadata: document_metadata(doc).merge(metadata)
        )
        segments.each do |segment|
          annotations = segment.notes.empty? ? {} : { "notes" => segment.notes }
          document << Nabu::Passage.new(urn: "#{urn}:#{segment.suffix}", language: language,
                                        text: segment.text, sequence: document.passages.size + 1,
                                        annotations: annotations)
        end
        raise Nabu::ParseError, "#{path}: no translation text" if document.passages.empty?

        document
      end

      private

      def document_metadata(doc)
        bibliography = doc.xpath("//body/div[@type='bibliography']//bibl").filter_map { |bibl| clean(bibl.text) }
        {
          "kind" => "translation",
          "authority" => clean(doc.at_xpath("//publicationStmt/authority")&.text),
          "bibliography" => bibliography.empty? ? nil : bibliography
        }.compact
      end

      def clean(text)
        return nil if text.nil?

        value = Nabu::Normalize.nfc(text.gsub(/\s+/, " ").strip)
        value.empty? ? nil : value
      end

      # One passage under construction.
      Segment = Struct.new(:suffix, :buffer, :notes, :block) do
        def text = Nabu::Normalize.nfc(buffer.gsub(/\s+/, " ").strip)
      end
      private_constant :Segment

      # The document-order walk over the translation divs (see the class
      # note): textpart path, line milestones, block passages.
      class Walk
        def initialize
          @segments = []
          @path = []
          @current = nil
          @blocks = 0
          @restart = 1
          @seen = {}
        end

        def run(divs)
          divs.each do |div|
            @current = nil
            walk_children(div)
          end
          @segments.reject { |segment| segment.text.empty? }
        end

        private

        def walk_children(node)
          node.children.each { |child| walk(child) }
        end

        def walk(node)
          if node.text? || node.cdata?
            append(node.text) unless node.text.strip.empty? && @current.nil?
          elsif node.element?
            element(node)
          end
        end

        def element(node)
          case node.name
          when "div" then division(node)
          when "p", "ab" then block_element(node)
          when "milestone" then milestone(node)
          when "note" then note(node)
          when "gap" then append(" #{GAP_MARKER} ")
          when "lb" then append(" ")
          when "app" then node.element_children.each { |child| walk(child) if child.name == "lem" }
          when "certainty" then nil
          else walk_children(node)
          end
        end

        def division(node)
          label = node["type"] == "textpart" ? node["n"].to_s.strip : ""
          @path.push(label) unless label.empty?
          @current = nil
          walk_children(node)
          @path.pop unless label.empty?
          @current = nil
        end

        # A paragraph continues the running line passage; outside one it
        # is its own block.
        def block_element(node)
          @current = nil if @current&.block
          walk_children(node)
          @current = nil if @current&.block
        end

        def milestone(node)
          return unless node["unit"] == "line"

          label = node["n"].to_s.strip
          label.empty? ? open_block : open_line(label)
        end

        def note(node)
          value = node.text.gsub(/\s+/, " ").strip
          return if value.empty?

          open_block if @current.nil?
          @current.notes << Nabu::Normalize.nfc(value)
        end

        def append(text)
          open_block if @current.nil?
          @current.buffer << text
        end

        def open_line(label)
          suffix = (@path + [label]).join(":")
          while @seen[suffix]
            @restart += 1
            suffix = (@path + ["b#{@restart}", label]).join(":")
          end
          start_segment(suffix, block: false)
        end

        def open_block
          @blocks += 1
          start_segment((@path + ["p#{@blocks}"]).join(":"), block: true)
        end

        def start_segment(suffix, block:)
          @seen[suffix] = true
          @current = Segment.new(suffix, +"", [], block)
          @segments << @current
        end
      end
      private_constant :Walk
    end
  end
end
