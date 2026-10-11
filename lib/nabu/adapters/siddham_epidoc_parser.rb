# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"
require_relative "dharma_epidoc_parser"

module Nabu
  module Adapters
    # Parser family "siddham-epidoc" (P118-4): one edition file of the
    # Siddham Epigraphic Archive (Dániel Balogh et al.; Gupta, Vākāṭaka,
    # Aulikara, Parivrājaka … Sanskrit epigraphy, EpiDoc TEI). DOM-based:
    # 427 files, the largest ~60 KB.
    #
    # == Why its own (thin) parser, not dharma-epidoc
    #
    # The census of all 427 files (2026-10-11) found three shapes
    # dharma-epidoc would mis-read: (1) verse nests HALF-VERSE groups
    # (<lg n="3"><lg type="halfverse" n="ab"><l>…) — dharma's verse walk
    # reads only an lg's direct <l> children and would drop them; (2)
    # <lb> numbering runs CONTINUOUSLY through verse and prose (6,409 lbs;
    # only 5 files repeat a number), and lbs sit INSIDE <l> (a pāda
    # straddles two physical lines) — so the physical line is the one
    # citation grain everywhere; (3) 682 STANDALONE <sic> elements carry
    # the inscribed text (dharma drops every sic; only sic inside <choice>
    # yields to its <corr>). What IS shared: dharma's marker vocabulary
    # and the clean/marker-only rules (composed, not copied).
    #
    # == Grain
    #
    # - lb mode (426 of 427 files): one unit per physical line, keyed by
    #   the lb @n VERBATIM ("1", "seal.1", "fragment.B.3"); a line runs
    #   from its lb to the next, across <p>/<ab>/<l>/<lg> boundaries (each
    #   a space). break="no" still ends the line (the titus/dharma
    #   precedent). Text before the first lb mints under "pre". A
    #   repeated number takes a deterministic "+2"/"+3" suffix (the dharma
    #   duplicate policy).
    # - no-lb mode (IN02052, verse only): one unit per <l>, keyed by the
    #   ancestor lg @n path + the l's ordinal ("1.ab.2"); a <p>/<ab> outside
    #   verse is "p<ordinal>".
    # - Gap-only units mint nothing; zero units raises ParseError.
    #
    # Annotations (present keys only): "stanza" + "met" — the outermost
    # enclosing <lg>'s @n / @met where the line opens; "textpart" — the
    # enclosing div[@type=textpart] @subtype; "plate" — the current
    # <pb> @n; "column"/"fragment" — the current <milestone unit> @n.
    #
    # == Text policy
    #
    # READ THROUGH: supplied, unclear, add, seg, num, g, subst, damage,
    # standalone sic, corr. CHOICE: corr | reg | expan, else the first
    # child (Siddham's <choice> of alternative <unclear> readings).
    # MARKERS: gap "[…]", del "⟦…⟧", surplus "{…}", space " ". DROP: note
    # and the rest of dharma's DROP list except sic; XML comments (the
    # editors' running commentary) are never text.
    module SiddhamEpidocParser
      XML_NS = "http://www.w3.org/XML/1998/namespace"

      # The census: every edition div is san-Latn (427/427, 2026-10-11).
      LANGUAGES = %w[san-Latn].freeze

      Result = Data.define(:title, :idno, :language, :textparts, :passages)
      Unit = Data.define(:key, :text, :annotations)

      # dharma's DROP list minus sic (standalone sic is inscribed text here).
      DROP = (DharmaEpidocParser::DROP - %w[sic]).freeze
      GAP_MARKER = DharmaEpidocParser::GAP_MARKER
      MILESTONE_UNITS = %w[column fragment].freeze

      module_function

      def parse(path)
        doc = Nokogiri::XML(File.read(path, encoding: "bom|utf-8"))
        doc.remove_namespaces!
        name = File.basename(path)
        edition = doc.at_xpath('//body//div[@type="edition"]') or
          raise Nabu::ParseError, "#{name}: no edition div"

        language = lang_of(edition)
        unless LANGUAGES.include?(language)
          raise Nabu::ParseError, "#{name}: edition language #{language.inspect} is outside the " \
                                  "censused set #{LANGUAGES.inspect} — classify it before ingesting"
        end

        units = edition.at_xpath(".//lb") ? LineWalk.new.run(edition) : verse_units(edition)
        raise Nabu::ParseError, "#{name}: edition has no citable text" if units.empty?

        Result.new(
          title: presence(clean(doc.at_xpath("//teiHeader//titleStmt/title")&.text.to_s)),
          idno: presence(doc.at_xpath("//teiHeader//publicationStmt/idno")&.text.to_s.strip),
          language: language,
          textparts: edition.xpath('.//div[@type="textpart"]').map { |d| d["subtype"] }.compact,
          passages: units
        )
      end

      # The lb-grain walk: a document-order stream that flushes the open
      # line at every <lb>.
      class LineWalk
        def initialize
          @units = []
          @used = Hash.new(0)
          @key = nil
          @buffer = +""
          @annotations = {}
          @context = {}
        end

        def run(edition)
          walk(edition, stanza: nil, textpart: nil)
          flush!
          @units
        end

        private

        def walk(node, stanza:, textpart:)
          node.children.each do |child|
            if child.text?
              @buffer << child.text
            elsif child.element?
              element(child, stanza: stanza, textpart: textpart)
            end
          end
        end

        def element(node, stanza:, textpart:)
          case node.name
          when *DROP then nil
          when "lb" then open_line!(node["n"] || "?", stanza: stanza, textpart: textpart)
          when "pb" then @context["plate"] = node["n"]
          when "milestone"
            @context[node["unit"]] = node["n"] if MILESTONE_UNITS.include?(node["unit"])
          when "lg"
            @buffer << " "
            walk(node, stanza: stanza || node, textpart: textpart)
          when "div"
            @buffer << " "
            walk(node, stanza: stanza, textpart: node["type"] == "textpart" ? node["subtype"] : textpart)
          when "p", "ab", "l"
            @buffer << " "
            walk(node, stanza: stanza, textpart: textpart)
            @buffer << " "
          when "gap", "space", "del", "surplus", "choice"
            @buffer << SiddhamEpidocParser.extract(node)
          else walk(node, stanza: stanza, textpart: textpart)
          end
        end

        def open_line!(number, stanza:, textpart:)
          flush!
          @key = number
          @annotations = {
            "textpart" => textpart, "plate" => @context["plate"],
            "column" => @context["column"], "fragment" => @context["fragment"],
            "stanza" => stanza&.[]("n"), "met" => stanza&.[]("met")
          }.compact
        end

        def flush!
          text = SiddhamEpidocParser.clean(@buffer)
          unless text.empty? || DharmaEpidocParser.marker_only?(text)
            @units << Unit.new(key: disambiguated(@key || "pre"), text: text, annotations: @annotations)
          end
          @buffer = +""
          @key = nil
          @annotations = {}
        end

        def disambiguated(key)
          @used[key] += 1
          @used[key] == 1 ? key : "#{key}+#{@used[key]}"
        end
      end

      # No-lb mode (class note): <l> units keyed by the lg @n path + the
      # l ordinal; prose blocks outside verse as p<ordinal>.
      def verse_units(edition)
        paragraphs = 0
        edition.xpath(".//l | .//p[not(ancestor::lg)] | .//ab[not(ancestor::lg)]").filter_map do |node|
          text = clean(extract(node))
          if node.name == "l"
            lgs = node.ancestors("lg").to_a.reverse
            key = (lgs.map { |lg| lg["n"] } + [(node.parent.xpath("./l").index(node) + 1).to_s]).join(".")
            annotations = { "stanza" => lgs.first&.[]("n"), "met" => lgs.first&.[]("met") }.compact
          else
            key = "p#{paragraphs += 1}"
            annotations = {}
          end
          next if text.empty? || DharmaEpidocParser.marker_only?(text)

          Unit.new(key: key, text: text, annotations: annotations)
        end
      end

      # The keep/drop extraction for one subtree (no lb splitting).
      def extract(node)
        return node.text if node.text?
        return "" unless node.element?

        case node.name
        when *DROP then ""
        when "gap" then GAP_MARKER
        when "space" then " "
        when "lb", "pb", "milestone" then node["break"] == "no" ? "" : " "
        when "del" then "⟦#{inner(node)}⟧"
        when "surplus" then "{#{inner(node)}}"
        when "choice"
          preferred = node.at_xpath("./corr | ./reg | ./expan") || node.element_children.first
          preferred ? extract(preferred) : ""
        else inner(node)
        end
      end

      def inner(node)
        node.children.map { |c| extract(c) }.join
      end

      def clean(text)
        Normalize.nfc(text.gsub(/\s+/, " ").strip)
      end

      def presence(value)
        value.nil? || value.empty? ? nil : value
      end

      def lang_of(node)
        node.attribute_with_ns("lang", XML_NS)&.value || node["lang"]
      end
    end
  end
end
