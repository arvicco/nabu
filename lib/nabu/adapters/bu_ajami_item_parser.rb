# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The bu-ajami-html parser family (P124-1): one item page of Boston
    # University's NEH Ajami collection (sites.bu.edu/nehajami), a
    # WordPress page whose <article> carries
    #
    #   * the item's metadata TABLE — two-cell rows, label | value, in
    #     upstream's own vocabulary (census 2026-10-13 over all 80 items:
    #     Title, Author or Owner, Subject, Content, Genre, Language,
    #     Script, Manuscript condition, Type, Publisher, Provenance, Source
    #     Reference (79; one page omits it), Access condition and
    #     copyright, Contributors, Required citation information (79) /
    #     Required citation (1)) — read VERBATIM by label; nothing is
    #     dropped (the adapter maps the labels it knows and keeps the rest);
    #   * the PDF links: exactly one "…_Transcription.pdf" (the typed
    #     romanized transcription — the text), an English and a French
    #     translation, and one or two manuscript-image PDFs (300/150 ppi).
    #
    # Values are whitespace-collapsed (WordPress pads spans with runs of
    # spaces and non-breaking spaces) and NFC'd. Hrefs are NOT normalized:
    # upstream serves some files under NFD names ("Bàkk-wi" with a
    # combining grave), and a request must carry those bytes.
    module BuAjamiItemParser
      Item = Data.define(:fields, :transcription_href, :translation_hrefs, :manuscript_hrefs, :source_links)

      TRANSCRIPTION = %r{transcription[^/]*\.pdf\z}i
      ENGLISH = %r{english[^/]*\.pdf\z}i
      FRENCH = %r{french[^/]*\.pdf\z}i

      module_function

      def parse_file(path)
        parse(File.read(path, encoding: "UTF-8"), source: path)
      end

      # Raises Nabu::ParseError on a page without the metadata table or
      # with zero / several distinct transcription links.
      def parse(html, source:)
        article = Nokogiri::HTML(html).at_css("article") or raise ParseError, "#{source}: no <article>"
        table = article.at_css("table") or raise ParseError, "#{source}: no metadata table"
        fields, links = read_table(table)
        raise ParseError, "#{source}: metadata table carries no Title row" unless fields.key?("Title")

        pdfs = article.css("a[href]").map { |a| a["href"].to_s.strip }.select { |h| h.downcase.end_with?(".pdf") }.uniq
        transcriptions = pdfs.grep(TRANSCRIPTION)
        unless transcriptions.size == 1
          raise ParseError, "#{source}: expected one transcription PDF, found #{transcriptions.size}"
        end

        Item.new(fields: fields, transcription_href: transcriptions.first,
                 translation_hrefs: { "en" => pdfs.grep(ENGLISH).first, "fr" => pdfs.grep(FRENCH).first }.compact,
                 manuscript_hrefs: pdfs - transcriptions - pdfs.grep(ENGLISH) - pdfs.grep(FRENCH),
                 source_links: links)
      end

      def read_table(table)
        links = []
        fields = {}
        table.css("tr").each do |row|
          cells = row.css("td")
          next unless cells.size == 2

          label = clean(cells[0].text)
          next if label.empty?

          fields[label] = clean(cells[1].text)
          links.concat(cells[1].css("a[href]").map { |a| a["href"].to_s.strip }) if label == "Source Reference"
        end
        [fields, links.reject(&:empty?).uniq]
      end

      def clean(text)
        Normalize.nfc(text.tr(" ", " ").gsub(/\s+/, " ").strip)
      end
    end
  end
end
