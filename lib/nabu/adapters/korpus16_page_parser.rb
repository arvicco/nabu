# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The korpus16-html family: one Korpus 16 reading page
    # (fran.si/korpus16/Knjiga/<id>/<slug>?stran=<n>) — the portal's HTML
    # rendering of upstream's TEI, every TEI element a div/span carrying a
    # k16-<element>[-<type>] class inside section.k16-page.
    #
    # Body blocks (k16-p, k16-head, k16-label, k16-seg, and any other
    # non-furniture child) are the page's running text, one per line,
    # whitespace runs collapsed (the portal renders it that way; no
    # white-space rule preserves the source's line breaks) and inline
    # highlights (k16-hi-*) closed up — upstream keys a roman initial and
    # its italic run as separate spans of one word ("O" + "zha nash").
    #
    # Forme work (k16-fw-*) is page furniture, not text: pageNum → folio
    # (the print's own page/folio label, "I,56a"), head → running head,
    # catch → catchword, sig → signature mark; any other fw type rides as
    # fw_<type>. k16-cb (column break) carries nothing.
    #
    # Marginal notes (k16-note-content, the print's margin glosses) leave
    # the running text — their anchor sits mid-sentence, so inlining them
    # would break the line they gloss — and ride in document order as
    # +notes+. The k16-note-placeholder "*" is the portal's anchor marker,
    # not print text, and is dropped.
    #
    # Every page also carries the book header (div.book-page-title: four
    # h3 — siglum, author/editor, title, "Place, Year") and the pager
    # (input#gopage max = the book's page count).
    class Korpus16PageParser
      Header = Data.define(:siglum, :author, :title, :imprint)

      Page = Data.define(:header, :page_count, :blocks, :notes, :folio, :running_head,
                         :catchword, :signature, :other_forme_work) do
        def text = blocks.join("\n")
      end

      FW_FIELDS = { "pageNum" => :folio, "head" => :running_head, "catch" => :catchword, "sig" => :signature }.freeze

      def reading_page?(html)
        !Nokogiri::HTML(html).at_css("section.k16-page").nil?
      end

      def parse(html)
        doc = Nokogiri::HTML(html)
        section = doc.at_css("section.k16-page")
        fields = { blocks: [], notes: [], fw: Hash.new { |h, k| h[k] = [] } }
        section&.element_children&.each { |node| read_block(node, fields) }
        fw = fields[:fw]
        Page.new(
          header: header(doc), page_count: page_count(doc),
          blocks: fields[:blocks], notes: fields[:notes],
          folio: joined(fw.delete("pageNum")), running_head: joined(fw.delete("head")),
          catchword: joined(fw.delete("catch")), signature: joined(fw.delete("sig")),
          other_forme_work: fw.to_h { |type, texts| ["fw_#{type}", texts.join(" ")] }
        )
      end

      private

      def read_block(node, fields)
        classes = node["class"].to_s.split
        if (fw = classes.find { |c| c.start_with?("k16-fw-") })
          text = flat(node.text)
          fields[:fw][fw.delete_prefix("k16-fw-")] << text unless text.empty?
          return
        end
        return if classes.include?("k16-cb")

        block = node.dup
        block.css("span.k16-note-content").each do |note|
          text = flat(note.text)
          fields[:notes] << text unless text.empty?
          note.remove
        end
        block.css("span.k16-note-placeholder").each(&:remove)
        text = flat(block.text)
        fields[:blocks] << text unless text.empty?
      end

      def header(doc)
        heads = doc.css("div.book-page-title h3").map { |h3| flat(h3.text) }
        return nil if heads.size < 4

        Header.new(siglum: heads[0], author: heads[1], title: heads[2], imprint: heads[3])
      end

      def page_count(doc)
        max = doc.at_css("input#gopage")&.[]("max")
        max.to_s.match?(/\A\d+\z/) ? Integer(max, 10) : nil
      end

      def joined(texts)
        texts.nil? || texts.empty? ? nil : texts.join(" ")
      end

      def flat(text) = Normalize.nfc(text.gsub(/[[:space:]]+/, " ").strip)
    end
  end
end
