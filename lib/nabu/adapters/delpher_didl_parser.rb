# frozen_string_literal: true

require "nokogiri"

require_relative "source_read"
require_relative "../normalize"

module Nabu
  module Adapters
    # The delpher-didl family: one Delpher newspaper ISSUE as the KB's
    # Databank Digitale Dagbladen ships it in the open newspaper archive —
    # a folder holding the issue's MPEG-21 DIDL record (didl.xml) and one
    # small OCR file per ARTICLE (<prefix>_<nnnn>_articletext.xml:
    # <text><title/><p/>…</text>), beside one ALTO file per page.
    #
    # The DIDL is the issue's table of contents and its catalogue record:
    #
    # - the top Item's metadata Component (srw_dc:dcx): dc:title (the
    #   paper), dc:date (the issue date), dc:publisher, dcterms:spatial
    #   twice — xsi:type dcx:creation is the place of publication, the
    #   untyped one the distribution scope (Landelijk, Regionaal/lokaal) —
    #   dc:language (ISO 639-1, one or more, case varies: "nl", "NL"),
    #   dcx:issuenumber, dcterms:temporal, dcterms:issued (the title's run),
    #   dcterms:alternative / dcterms:isVersionOf (other names of the
    #   title), dc:identifier xsi:type dcx:PPN, dc:source (the holding
    #   copy), dcterms:isPartOf (the digitization collection),
    #   ddd:yearsDigitized;
    # - one Item per page (…:p001), its metadata carrying
    #   ddd:OCRConfidencelevel and ddd:nativePageNumber;
    # - one Item per article (…:a0001, role "article N"), whose ocr
    #   Component names the articletext file (dcx:filename), whose metadata
    #   carries dc:subject (artikel, advertentie, familiebericht, …) and
    #   dc:title, and whose zoning lists the article-parts by pageid (an
    #   article may run over two pages). The page Items repeat each article
    #   as a nested Item (ddd:article_id) — read once, from the article
    #   Items, in document order.
    #
    # The parser reads; the adapter decides what becomes a Document. Text
    # is upstream's uncorrected OCR, NFC-normalized at this boundary and
    # otherwise verbatim (never "cleaned" — canonical means canonical).
    class DelpherDidlParser
      NS = {
        "didl" => "urn:mpeg:mpeg21:2002:02-DIDL-NS",
        "dc" => "http://purl.org/dc/elements/1.1/",
        "dcterms" => "http://purl.org/dc/terms/",
        "dcx" => "http://krait.kb.nl/coop/tel/handbook/telterms.html",
        "ddd" => "http://www.kb.nl/namespaces/ddd",
        "srw_dc" => "info:srw/schema/1/dc-v1.1",
        "xsi" => "http://www.w3.org/2001/XMLSchema-instance"
      }.freeze

      ARTICLE_ID = /:a(\d+)\z/
      PAGE_ID = /:p(\d+)\z/
      ARTICLE_FILE = /_articletext\.xml\z/

      Article = Data.define(:id, :number, :subject, :title, :file, :pages)
      Page = Data.define(:id, :number, :native_number, :ocr_confidence)
      Issue = Data.define(:record_id, :fields, :pages, :articles)
      ArticleText = Data.define(:title, :paragraphs)

      # Read +didl_path+ into an Issue (catalogue fields + pages + articles).
      def read(didl_path)
        doc = Nokogiri::XML(SourceRead.utf8_file(didl_path, label: "delpher didl"), &:strict)
        top = doc.at_xpath("/didl:DIDL/didl:Item", NS) or raise Nabu::ParseError, "#{didl_path}: no top didl:Item"
        record_id = top["dc:identifier"].to_s
        raise Nabu::ParseError, "#{didl_path}: top didl:Item carries no dc:identifier" if record_id.empty?

        meta = component_dcx(top, "#{record_id}:metadata") or
          raise Nabu::ParseError, "#{didl_path}: no issue metadata component"
        Issue.new(record_id: record_id, fields: issue_fields(meta), pages: pages(doc, record_id),
                  articles: articles(doc, record_id))
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{didl_path}: malformed DIDL: #{e.message}"
      end

      # One articletext file → its title and its non-empty paragraphs
      # (whitespace runs folded, NFC).
      def read_article(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "delpher articletext"), &:strict)
        root = doc.root
        raise Nabu::ParseError, "#{path}: articletext root is not <text>" unless root&.name == "text"

        ArticleText.new(title: squash(root.at_xpath("title")&.text),
                        paragraphs: root.xpath("p").filter_map { |p| squash(p.text) })
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed articletext: #{e.message}"
      end

      private

      def issue_fields(meta)
        spatial = meta.xpath("dcterms:spatial", NS)
        creation, scope = spatial.partition { |node| node["xsi:type"] == "dcx:creation" }
        {
          "paper" => text(meta, "dc:title"),
          "date" => text(meta, "dc:date"),
          "publisher" => text(meta, "dc:publisher"),
          "place" => creation.filter_map { |node| squash(node.text) }.first,
          "distribution" => scope.filter_map { |node| squash(node.text) }.first,
          "languages" => meta.xpath("dc:language", NS).filter_map { |node| squash(node.text)&.downcase }.uniq,
          "issue_number" => text(meta, "dcx:issuenumber"),
          "temporal" => text(meta, "dcterms:temporal"),
          "title_run" => text(meta, "dcterms:issued"),
          "alternative_titles" => texts(meta, "dcterms:alternative") + texts(meta, "dcterms:isVersionOf"),
          "ppn" => meta.xpath("dc:identifier[@xsi:type='dcx:PPN']", NS).filter_map { |n| squash(n.text) }.first,
          "holding" => text(meta, "dc:source"),
          "collections" => texts(meta, "dcterms:isPartOf"),
          "years_digitized" => text(meta, "ddd:yearsDigitized")
        }
      end

      def pages(doc, record_id)
        doc.xpath("//didl:Item[starts-with(@dc:identifier, '#{record_id}:p')]", NS).filter_map do |item|
          id = item["dc:identifier"]
          number = id[PAGE_ID, 1] or next
          meta = component_dcx(item, "#{id}:metadata")
          Page.new(id: id, number: Integer(number, 10), native_number: meta && text(meta, "ddd:nativePageNumber"),
                   ocr_confidence: meta && float(text(meta, "ddd:OCRConfidencelevel")))
        end
      end

      def articles(doc, record_id)
        doc.xpath("//didl:Item[starts-with(@dc:identifier, '#{record_id}:a')]", NS).filter_map do |item|
          id = item["dc:identifier"]
          number = id[ARTICLE_ID, 1] or next
          meta = component_dcx(item, "#{id}:metadata")
          file = item.at_xpath("didl:Component/didl:Resource[@dcx:filename]", NS)&.[]("dcx:filename")
          pages = item.xpath(".//dcx:article-part", NS).filter_map { |part| part["pageid"].to_s[PAGE_ID, 1] }
          Article.new(id: id, number: number, subject: meta && text(meta, "dc:subject"),
                      title: meta && text(meta, "dc:title"), file: file,
                      pages: pages.map { |page| Integer(page, 10) }.uniq)
        end
      end

      def component_dcx(item, identifier)
        item.at_xpath("didl:Component[@dc:identifier='#{identifier}']/didl:Resource/srw_dc:dcx", NS)
      end

      def text(node, path) = squash(node.at_xpath(path, NS)&.text)

      def texts(node, path) = node.xpath(path, NS).filter_map { |n| squash(n.text) }

      def float(value)
        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def squash(value)
        return nil if value.nil?

        folded = value.gsub(/[[:space:]]+/, " ").strip
        folded.empty? ? nil : Normalize.nfc(folded)
      end
    end
  end
end
