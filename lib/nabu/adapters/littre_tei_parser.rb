# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # The Littré TEI parser family: Émile Littré's Dictionnaire de la
    # langue française in the oeuvres/littre TEI P5 (one file per letter,
    # XMLittré v1.3 lineage). Each <entry> — and each <entryFree>, the
    # loosely structured articles (89 at census: suffixes, a few
    # supplement items) — is one DictionaryEntry. Streamed with
    # Nokogiri::XML::Reader (the letter files run to 12.6 MB), one small
    # DOM per article.
    #
    # - entry_id: the article's xml:id verbatim ("baal", "lampe.2"), with
    #   two upstream defects made safe by rule (census 2026-11-02):
    #   an id repeated WITHIN a file numbers its later occurrences ":2"…
    #   (gommeux and lampe.2 — each a supplement article sharing the main
    #   article's id), and an article whose id does not begin with the
    #   file's letter carries "@<letter>" (ignoramment printed again in
    #   s.xml; de_bric_et_de_broc in b.xml) — so the ids stay unique
    #   across the dictionary's 26 files, which the loader upserts as one
    #   shelf.
    # - headword: the id's lemma — the homograph number (".2", "1") and a
    #   trailing "." dropped, "_" read as a space ("de bric et de broc");
    #   key_raw: the printed <orth> verbatim ("GOMMEUX, EUSE").
    # - body: line 1 the printed head (orth, "(pron)", gram); then each
    #   sense's definition ("1° " when the sense is numbered), each
    #   citation as « quote » (AUTHOR, place), the notes (HIST./REM.,
    #   their century labels on their own lines) and "ÉTYM. …"; NFC.
    # - gloss: the first definition, cut at its first ". " or ";",
    #   trailing punctuation trimmed, at most GLOSS_MAX characters; nil
    #   for a citation-only article.
    # - annotations: "pos" — the printed gram verbatim ("s. m.", "adj.");
    #   "first_attested" — the HISTORIQUE's first century label
    #   normalized to "XIIIe s." (21,561 articles carry one at census; the
    #   earliest century Littré quotes the word in, his own dating).
    #
    # Deliberately unmined (declared): citations mint no DictionaryCitation
    # (the house rows need a CTS urn; Littré cites "RAC. Ath. III, 3") —
    # they read verbatim in the body.
    class LittreTeiParser
      ARTICLES = %w[entry entryFree].freeze
      CENTURY = /\A([IVXL]+)\s*e?\.?\s*s\./i
      GLOSS_MAX = 100
      READER_OPTIONS = Nokogiri::XML::ParseOptions::DEFAULT_XML |
                       Nokogiri::XML::ParseOptions::NOWARNING | Nokogiri::XML::ParseOptions::NOERROR
      private_constant :ARTICLES, :CENTURY, :GLOSS_MAX, :READER_OPTIONS

      LANGUAGE = "fra"

      # +letter+ is the file's own letter ("b" for xml/b.xml).
      def entries(path, letter:)
        collected = []
        seen = Hash.new(0)
        xml = SourceRead.utf8_file(path, label: "littre-tei")
        # Upstream repeats a handful of xml:ids (the entry_id note);
        # libxml's ID table would print a validity warning per repeat.
        Nokogiri::XML::Reader(xml, path, nil, READER_OPTIONS).each do |node|
          next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && ARTICLES.include?(node.name)

          doc = Nokogiri::XML(node.outer_xml, &:strict)
          doc.remove_namespaces!
          collected << build(doc.root, path, letter, seen)
        end
        collected
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "littre-tei: malformed XML in #{path}: #{e.message}"
      end

      private

      def build(elem, path, letter, seen)
        xml_id = elem["id"].to_s
        raise Nabu::ParseError, "littre-tei: #{path}: article without xml:id" if xml_id.strip.empty?

        headword = lemma(xml_id)
        orth = text(elem.at_xpath("form/orth"))
        Nabu::DictionaryEntry.new(
          entry_id: entry_id(xml_id, headword, letter, seen), key_raw: orth.empty? ? xml_id : orth,
          language: LANGUAGE, headword: headword,
          headword_folded: Nabu::Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss(elem), body: render(elem).join("\n"), annotations: annotations(elem)
        )
      end

      def entry_id(xml_id, headword, letter, seen)
        seen[xml_id] += 1
        id = seen[xml_id] > 1 ? "#{xml_id}:#{seen[xml_id]}" : xml_id
        initial = headword.unicode_normalize(:nfd)[0].to_s.downcase.tr("œæ", "oa")
        initial == letter ? id : "#{id}@#{letter}"
      end

      def lemma(xml_id)
        base = xml_id.sub(/\.?\d+\z/, "").sub(/\.+\z/, "").tr("_", " ")
        Nabu::Normalize.nfc(base.strip.empty? ? xml_id : base.strip)
      end

      # Block-level rendering, document order.
      def render(elem, out = [])
        elem.element_children.each do |child|
          case child.name
          when "form" then out << head(child)
          when "sense"
            mark = child["n"] ? "#{child['n']}° " : ""
            first = out.size
            render(child, out)
            out[first] = "#{mark}#{out[first]}" if out[first] && !mark.empty?
          when "cit" then out << cit(child)
          when "note"
            out << child["type"].to_s.upcase if child["type"] && child["type"] != "plan"
            render(child, out)
          when "etym" then out << "ÉTYM. #{text(child)}"
          when "list", "re" then render(child, out)
          else out << text(child)
          end
        end
        out.reject!(&:empty?)
        out
      end

      def head(form)
        orth = form.xpath("orth").map { |o| text(o) }.join(", ")
        pron = form.xpath("pron").map { |p| text(p) }.reject(&:empty?)
        gram = form.xpath("gram").map { |g| text(g) }.reject(&:empty?)
        [orth, (pron.empty? ? nil : "(#{pron.join(', ')})"), *gram].compact.reject(&:empty?).join(" ")
      end

      def cit(node)
        quote = text(node.at_xpath("quote"))
        source = node.xpath("bibl").map do |bibl|
          [text(bibl.at_xpath("author")), text(bibl.at_xpath("biblScope"))].reject(&:empty?).join(", ")
        end.reject(&:empty?).join("; ")
        line = quote.empty? ? "" : "« #{quote} »"
        source.empty? ? line : "#{line} (#{source})".strip
      end

      def gloss(elem)
        scrap = elem.xpath("sense//dictScrap | dictScrap").map { |s| text(s) }.find { |t| t.match?(/\p{L}/) }
        return nil unless scrap

        cut = scrap.split(/\.\s|;/, 2).first.to_s.sub(/[\s\p{P}]+\z/, "")
        cut = "#{cut[0, GLOSS_MAX].sub(/\s+\S*\z/, '')}…" if cut.length > GLOSS_MAX
        cut.match?(/\p{L}/) ? cut : nil
      end

      def annotations(elem)
        found = {}
        pos = text(elem.at_xpath("form/gram"))
        found["pos"] = pos unless pos.empty?
        label = elem.xpath("note[@type='HIST.']/label").map { |l| text(l) }.first
        found["first_attested"] = "#{Regexp.last_match(1).upcase}e s." if label&.match(CENTURY)
        found
      end

      def text(node)
        return "" if node.nil?

        Nabu::Normalize.nfc(node.text.gsub(/\s+/, " ").strip)
      end
    end
  end
end
