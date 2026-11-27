# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one transcript TEI of the Herzog August
    # Bibliothek's digital editions (diglib.hab.de/edoc/, the
    # `hab-edoc-tei` family). The editions are some two dozen separate
    # projects (2003–2024), each encoded by its own team — a print
    # transcribed page by page, a manuscript letter, a dictionary in
    # alphabet parts, a DTA-basisformat reprint — so the family is the
    # DTA page mold (Nabu::Adapters::DtaTeiParser): the one grain every
    # one of them carries is the page.
    #
    # == Page grain (the addressing)
    #
    # The reading flow of <front>, <body> and <back> accumulates; every
    # <pb> flushes the open page. Citation token:
    #
    #   p<n>     the printed/foliated page label when the pb carries @n
    #            ("2r", "fol. a i r" → "folair"; non-alphanumerics stripped)
    #   f<digits> else the trailing digits of @facs ("#drucke_ed000366_00004"
    #            → "f00004")
    #   px<k>    else an ordinal
    #   p0       text before any pb
    #
    # Residual duplicate tokens disambiguate positionally (":b2"), the
    # house belt. Every page's printed @n and @facs ride annotations.
    #
    # == As keyed (no cleanup)
    #
    # <choice> keeps the source half — <orig>, <sic>, <abbr> — and drops
    # the editors' <reg>/<corr>/<expan> (a standalone <expan> or <corr>
    # outside a choice is the only form the editors keyed and stays).
    # <app> keeps its <lem>, drops the <rdg> variants. <fw>, <figure> and
    # <facsimile> drop (furniture). Everything else (<hi>, <persName>,
    # <term>, <w>, <supplied>, <del>, …) is transparent reading text; an
    # <lb/> is one space (the keyed line-end hyphen stays as keyed), and
    # block-element ends contribute a space.
    #
    # == Notes never enter the text
    #
    # <note> is authorial in one edition (Böhmer's printed footnotes, the
    # Hans Sachs margins) and the editors' commentary in the next (the
    # Calenberg inventory's footnotes, the Lüne letters' "Lesart
    # unsicher"), and the encodings do not tell the two apart reliably
    # (type="footnote" is both). So no note text joins a passage: each
    # note rides the page's "notes" annotation with its @type/@place —
    # nothing lost, the canonical text never polluted.
    #
    # == Header (mined, never guessed)
    #
    # The teiHeader is read as one DOM (it is small): titleStmt title and
    # author; the availability <licence @target> (the adapter's licence
    # law reads it); sourceDesc's print or manuscript facts — author,
    # title, the imprint/publication date (@when/@notBefore/@notAfter or
    # the text's years), pubPlace, publisher (the printer), msIdentifier,
    # origDate/origPlace — falling back to a free-text sourceDesc <bibl>
    # ("Helmstedt: Georg. Wolfg. Hammius, 1708."); a letter's correspDesc
    # sender/addressee/date/place; msContents textLang @mainLang;
    # langUsage idents; classCode/term keywords. A file with no teiHeader
    # at all (the Dasypodius alphabet parts) parses with an empty header.
    class HabEdocTeiParser < StreamingTeiParser
      Unit = Data.define(:citation, :text, :annotations)
      Result = Data.define(:units, :header)
      private_constant :Unit

      # +language+ is the adapter's decision (its edition table; the
      # header's textLang/langUsage readings ride metadata only). The
      # document metadata is the mined header merged with +metadata+ —
      # or, given a block, whatever the block shapes from the header.
      # +dropped+ names further elements an edition's editors interleave
      # with the text (Christian II's <index> regests, Bahnsen's <head>
      # labels) — dropped like <fw>, never read as text.
      def parse(source, urn:, language:, title: nil, metadata: {}, canonical_path: nil, license_override: nil,
                dropped: [])
        path = resolve_canonical_path(source, canonical_path)
        result = extract(source, path: path, dropped: dropped)
        units = disambiguate_collisions(result.units)
        shaped = block_given? ? yield(result.header) : result.header.merge(metadata)
        build_document(units, urn: urn, language: language,
                              title: title || result.header["title"], path: path,
                              metadata: shaped, license_override: license_override)
      end

      # The header alone (the adapter's discovery-time licence peek): the
      # teiHeader slice of the file, DOM-mined. {} when the file has none.
      def header(path)
        text = SourceRead.utf8_file(path, label: "hab-edoc transcript")
        start = text.index(/<teiHeader[\s>]/)
        finish = text.index("</teiHeader>")
        return {} unless start && finish

        HeaderMiner.mine(text[start...(finish + "</teiHeader>".length)])
      end

      # A letter's DESCRIPTION file (the FMG letters' <stem>_tei-msDesc_fmg.xml
      # beside <stem>_tei-transcript.xml, a whole small TEI read as one DOM):
      # its teiHeader mined as a transcript's (correspDesc sender/addressee/
      # place/date, keywords), plus the msDesc its <text><body> carries —
      # msContents textLang @mainLang (the per-letter language upstream
      # states nowhere else), msIdentifier idno, the description's head
      # title.
      def description(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "hab-edoc letter description"))
        doc.remove_namespaces!
        header = doc.at_xpath("/*/teiHeader")
        facts = header ? HeaderMiner.mine(header.to_xml) : {}
        ms = doc.at_xpath("/*/text/body/msDesc") or return facts

        facts.merge({ "text_lang" => ms.at_xpath("./msContents/textLang/@mainLang")&.value&.strip,
                      "shelfmark" => HeaderMiner.text(ms.at_xpath("./msIdentifier/idno")),
                      "letter_title" => HeaderMiner.text(ms.at_xpath("./head/title")) }.compact)
      end

      private

      def extraction_class = Extraction

      def no_passages_message = "no transcribed text found"

      # One teiHeader as a DOM → the mined header hash (blank fields omitted).
      module HeaderMiner
        module_function

        YEAR = /(?<!\d)(1\d{3})(?!\d)/

        def mine(xml)
          doc = Nokogiri::XML(xml)
          doc.remove_namespaces!
          root = doc.root or return {}
          source = root.at_xpath(".//sourceDesc")
          out = {
            "title" => text(root.at_xpath("./fileDesc/titleStmt/title[not(@type) or @type='main']")),
            "header_author" => person(root.at_xpath("./fileDesc/titleStmt/author")),
            "licence_target" => root.at_xpath(".//publicationStmt//availability//licence/@target")&.value&.strip,
            "availability" => text(root.at_xpath(".//publicationStmt//availability")),
            "text_lang" => root.at_xpath(".//msContents/textLang/@mainLang")&.value,
            "lang_usage" => root.xpath(".//profileDesc/langUsage/language/@ident").map(&:value).uniq,
            "keywords" => root.xpath(".//profileDesc/textClass//classCode | .//profileDesc/textClass//term")
                              .map { |node| text(node) }.compact.uniq
          }
          out.merge!(source_facts(source)) if source
          out.merge!(correspondence(root.at_xpath(".//profileDesc/correspDesc")))
          out.reject { |_k, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
        end

        def source_facts(source)
          print = source.at_xpath(".//biblStruct | .//biblFull | .//bibl[*]")
          ms = source.at_xpath(".//msDesc")
          facts = {
            "source_author" => person(source.at_xpath(".//author")),
            "source_title" => text(source.at_xpath(".//title[not(@type) or @type='main']")),
            "pub_place" => text(source.at_xpath(".//pubPlace")),
            "printer" => text(source.at_xpath(".//publisher")),
            "shelfmark" => text(ms&.at_xpath("./msIdentifier")),
            "orig_place" => text(source.at_xpath(".//origPlace"))
          }
          imprint = source.at_xpath(".//imprint/date | .//publicationStmt/date | .//bibl/date | " \
                                    ".//biblStruct//date | .//biblFull//date")
          facts["source_date"] = date_reading(imprint, basis: "imprint") if print && imprint
          orig = source.at_xpath(".//origDate")
          facts["source_date"] ||= date_reading(orig, basis: "origDate") if orig
          facts.merge!(free_bibl(source)) if facts["source_date"].nil? && print.nil?
          facts
        end

        # A sourceDesc whose only content is a prose <bibl> ("Helmstedt:
        # Georg. Wolfg. Hammius, 1708.") — the place before the colon, the
        # printer before the year, the years themselves.
        def free_bibl(source)
          raw = text(source.at_xpath(".//bibl")) or return {}
          years = raw.scan(YEAR).flatten.map(&:to_i)
          return {} if years.empty?

          place, _, rest = raw.partition(":")
          out = { "source_date" => { "not_before" => years.min, "not_after" => years.max,
                                     "raw" => raw, "basis" => "imprint" },
                  "source_bibl" => raw }
          unless rest.empty?
            out["pub_place"] ||= place.strip
            printer = rest.sub(/,?\s*#{years.first}.*\z/, "").strip
            out["printer"] ||= printer unless printer.empty?
          end
          out
        end

        def correspondence(desc)
          return {} if desc.nil?

          sent = desc.at_xpath("./correspAction[@type='sent']")
          received = desc.at_xpath("./correspAction[@type='received']")
          out = {
            "sender" => text(sent&.at_xpath("./persName | ./rs[@type='person'] | ./name")),
            "addressee" => text(received&.at_xpath("./persName | ./rs[@type='person'] | ./name")),
            "sent_place" => text(sent&.at_xpath("./placeName | ./rs[@type='place'] | ./settlement"))
          }
          date = sent&.at_xpath("./date")
          out["letter_date"] = date_reading(date, basis: "correspDesc") if date
          out
        end

        # {not_before, not_after, raw, basis} from a date element: its
        # @when/@notBefore/@notAfter/@from/@to years, else the years its
        # text names; nil when it names none ("undatiert").
        def date_reading(node, basis:)
          attrs = %w[when notBefore notAfter from to].filter_map { |name| node[name] }
          raw = text(node) || attrs.join("/")
          years = (attrs.join(" ").scan(YEAR) + (attrs.empty? ? raw.to_s.scan(YEAR) : [])).flatten.map(&:to_i)
          return nil if years.empty?

          { "not_before" => years.min, "not_after" => years.max, "raw" => raw, "basis" => basis }
        end

        def person(node)
          return nil if node.nil?

          surname = text(node.at_xpath(".//surname"))
          forename = text(node.at_xpath(".//forename"))
          return [surname, forename].compact.join(", ") if surname

          text(node)
        end

        def text(node)
          return nil if node.nil?

          value = node.text.gsub(/[[:space:]]+/, " ").strip
          value.empty? ? nil : Normalize.nfc(value)
        end
      end

      # The single-pass Reader state machine: the teiHeader subtree is
      # handed whole to HeaderMiner; the text phase runs the page chunker.
      class Extraction < StreamingTeiParser::Walker
        DROPPED_ELEMENTS = %w[fw figure facsimile rdg].freeze
        CHOICE_DROPPED = %w[reg corr expan].freeze
        BLOCK_ELEMENTS = %w[p head l lg ab item list opener closer salute dateline signed byline
                            argument docTitle titlePart docImprint docAuthor docDate trailer
                            div table row cell sp speaker stage entry form sense].freeze
        private_constant :DROPPED_ELEMENTS, :CHOICE_DROPPED, :BLOCK_ELEMENTS

        def initialize(reader:, path:, dropped: [])
          super(reader: reader, path: path)
          @dropped = DROPPED_ELEMENTS + dropped
          @header = {}
          @in_text = false
          @text_depth = nil
          @drop_depth = nil
          @choice_depth = nil
          @note = nil # [depth, attributes, buffer]
          @notes = []
          @page = ["p0", {}]
          @fallback = 0
          @buffer = +""
          @units = []
        end

        def call
          @reader.each { |node| process(node) }
          flush_page
          Result.new(units: @units, header: @header)
        end

        private

        def start_element(node)
          name = local_name(node)
          if name == "teiHeader" && !@in_text
            @header = HeaderMiner.mine(node.outer_xml) unless node.empty_element?
            @drop_depth = node.depth unless node.empty_element?
            return
          end
          return if dropping?

          if name == "text" && !@in_text
            @in_text = true unless node.empty_element?
            @text_depth = node.depth
            return
          end
          text_element(node, name) if @in_text
        end

        def end_element(node)
          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end
          return unless @in_text

          name = local_name(node)
          case name
          when "text" then @in_text = false if node.depth == @text_depth
          when "note" then close_note(node)
          when "choice" then @choice_depth = nil if node.depth == @choice_depth
          else target << " " if BLOCK_ELEMENTS.include?(name)
          end
        end

        def text_node(node)
          return unless @in_text && !dropping?

          target << node.value.to_s
        end

        def text_element(node, name)
          return drop(node) if @dropped.include?(name)
          return drop(node) if @choice_depth && CHOICE_DROPPED.include?(name) && node.depth == @choice_depth + 1

          case name
          when "pb" then page_break(node)
          when "lb", "cb" then target << " "
          when "note" then open_note(node)
          when "choice" then @choice_depth ||= node.depth unless node.empty_element?
          end
        end

        def drop(node)
          @drop_depth = node.depth unless node.empty_element?
        end

        def target = @note ? @note[2] : @buffer

        def page_break(node)
          flush_page
          @page = [page_token(node), { "page" => presence(node.attribute("n")&.strip),
                                       "facs" => presence(node.attribute("facs")) }.compact]
        end

        def page_token(node)
          printed = node.attribute("n").to_s.gsub(/[^0-9A-Za-z]/, "")
          return "p#{printed}" unless printed.empty?

          digits = node.attribute("facs").to_s[/(\d+)\D*\z/, 1]
          return "f#{digits}" if digits

          "px#{@fallback += 1}"
        end

        def open_note(node)
          return if node.empty_element? || @note # a nested note rides its outer one

          attrs = { "type" => presence(node.attribute("type")), "place" => presence(node.attribute("place")) }
          @note = [node.depth, attrs.compact, +""]
        end

        def close_note(node)
          return unless @note && node.depth == @note[0]

          text = @note[2].gsub(/[[:space:]]+/, " ").strip
          @notes << @note[1].merge("text" => Normalize.nfc(text)) unless text.empty?
          @note = nil
        end

        def flush_page
          text = @buffer
          notes = @notes
          @buffer = +""
          @notes = []
          return if text.strip.empty?

          citation, annotations = @page
          annotations = annotations.merge("notes" => notes) unless notes.empty?
          @units << Unit.new(citation: citation, text: text, annotations: annotations)
        end
      end
    end
  end
end
