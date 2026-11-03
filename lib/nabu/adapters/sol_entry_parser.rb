# frozen_string_literal: true

require "date"
require "nokogiri"

require_relative "../betacode"
require_relative "../errors"
require_relative "../normalize"

module Nabu
  module Adapters
    # The Suda On Line entry page (the sol-html parser family): one saved
    # answer of the SOL search CGI to "<letter>,<n> in Adler number" →
    # one Entry. The page is XHTML-ish markup around one record:
    #
    #   <strong>Headword: </strong> <a onclick="openref()">betacode</a>…
    #   <strong>Adler number: </strong><span class='target'>nu</span>,
    #       <span class='target'>27</span>
    #   <strong>Translated headword: </strong>…<br/>
    #   <strong class="high">Vetting Status: high</strong>
    #   <div class="translation"> · <div class="greek"> · <div class="notes">
    #   <div class="bibliography"> · Associated internet address(es) · Keywords
    #   <strong>Translated by</strong>: <a>NAME</a> on 10 July 2009@17:32:56.
    #   <div class="editor"> NAME (note) on DATE.<br/> … (the vetting history)
    #
    # Text rules: <br/> is a line break (lines whitespace-squeezed, blank
    # lines dropped); <g>…</g> is SOL's inline betacode Greek, decoded to
    # Unicode at this boundary (Nabu::Betacode); every other tag keeps
    # its text. The Greek Original block is betacode too; its "#" value
    # (6 entries in the 2025 export) is the CGI's placeholder, no Greek.
    #
    # A page that is not exactly one record — the "no matches" answer, or
    # a query that found several records — raises NoRecord (the adapter
    # skips it by rule).
    module SolEntryParser
      class NoRecord < Nabu::Error; end

      Entry = Data.define(:letter, :number, :headwords_betacode, :headword, :translated_headword,
                          :vetting_status, :translation, :greek_original, :notes, :references,
                          :web_addresses, :keywords, :translator, :translated_at, :vetters)

      NO_MATCHES = %r{translation database has <b>no matches</b>}
      RECORDS_FOUND = /No\. of records found:\s*<span[^>]*>(\d+)</
      # Upstream stamps are "10 July 2009@17:32:56"; one translator stamp
      # in the 2025 export reads "@014:42:39" — matched, kept verbatim.
      STAMP = /\d{1,2} [A-Z][a-z]+ \d{4}@[\d:]+\d/
      CLEAN_TIME = /\A\d{2}:\d{2}:\d{2}\z/
      VETTER = /\A(?<name>.+?)(?: \((?<note>.*)\))? on (?<stamp>\d{1,2} [A-Z][a-z]+ \d{4}@[\d:]+\d)\.?\z/

      module_function

      def parse(html)
        html = html.dup.force_encoding(Encoding::UTF_8)
        raise NoRecord, "no translation record (the CGI's no-matches answer)" if html.match?(NO_MATCHES)

        found = html[RECORDS_FOUND, 1]&.to_i
        raise NoRecord, "not one record (the query found #{found.inspect} records)" unless found == 1

        doc = Nokogiri::HTML(html, nil, "UTF-8")
        letter, number = adler(doc)
        build(doc, letter, number)
      end

      def build(doc, letter, number)
        headwords = headword_links(doc)
        greek = block_text(doc.at_css("div.greek"), greek: true)
        Entry.new(
          letter: letter, number: number,
          headwords_betacode: headwords,
          headword: Normalize.nfc(headwords.map { |h| Betacode.decode(h) }.join(" ")),
          translated_headword: label_text(doc, "Translated headword:"),
          vetting_status: vetting_status(doc),
          translation: block_text(doc.at_css("div.translation")),
          greek_original: greek == "#" ? nil : greek,
          notes: block_text(doc.at_css("div.notes")),
          references: block_text(doc.at_css("div.bibliography")),
          web_addresses: web_addresses(doc),
          keywords: (label_links(doc, "Keywords:") + label_links(doc, "Keyword:")).map { |a| squeeze(a.text) },
          **translator(doc),
          vetters: vetters(doc)
        )
      end

      def adler(doc)
        strong = doc.at_xpath("//strong[normalize-space(.)='Adler number:']") or
          raise NoRecord, "no Adler number on the page"
        spans = strong.xpath("following-sibling::span[@class='target']").first(2).map { |s| s.text.strip }
        raise NoRecord, "unreadable Adler number #{spans.inspect}" unless spans.size == 2 && spans[1].match?(/\A\d+\z/)

        [spans[0], Integer(spans[1], 10)]
      end

      def vetting_status(doc)
        strong = doc.at_xpath("//strong[starts-with(normalize-space(.), 'Vetting Status:')]") or return nil
        strong.text.sub(/\A\s*Vetting Status:\s*/, "").strip
      end

      # The headword links between "Headword:" and "Adler number:" (the
      # Perseus morph links — one per headword form).
      def headword_links(doc)
        doc.xpath("//a[@onclick='openref()']").map { |a| a.text.strip }.reject(&:empty?)
      end

      # The bare text following a <strong> label up to the next <br/>.
      def label_text(doc, label)
        strong = doc.at_xpath("//strong[normalize-space(.)='#{label}']") or return nil
        out = +""
        node = strong.next_sibling
        while node && node.name != "br"
          out << node.text
          node = node.next_sibling
        end
        text = squeeze(out)
        text.empty? ? nil : Normalize.nfc(text)
      end

      # The <a> siblings following a <strong> label up to the next <strong>.
      def label_links(doc, label)
        strong = doc.at_xpath("//strong[normalize-space(.)='#{label}']") or return []
        links = []
        node = strong.next_sibling
        while node && node.name != "strong"
          links << node if node.name == "a"
          node = node.next_sibling
        end
        links
      end

      def web_addresses(doc)
        (label_links(doc, "Associated internet address:") + label_links(doc, "Associated internet addresses:"))
          .filter_map { |a| a["href"]&.strip }
      end

      def translator(doc)
        strong = doc.at_xpath("//strong[normalize-space(.)='Translated by']") or
          return { translator: nil, translated_at: nil }
        name = strong.xpath("following-sibling::a[1]").first&.text
        tail = strong.xpath("following-sibling::text()").find { |t| t.text.match?(STAMP) }&.text.to_s
        { translator: name && Normalize.nfc(squeeze(name)), translated_at: iso(tail[STAMP]) }
      end

      def vetters(doc)
        div = doc.at_css("div.editor") or return []
        block_text(div).to_s.lines.filter_map do |line|
          m = VETTER.match(line.strip) or next
          { "name" => m[:name], "note" => m[:note], "at" => iso(m[:stamp]) }.compact
        end
      end

      # "10 July 2009@17:32:56" → "2009-07-10T17:32:56" (the CGI states no
      # zone; none is invented). Unreadable stamps ride verbatim.
      def iso(stamp)
        return nil if stamp.nil?

        day, time = stamp.split("@")
        return stamp unless time.match?(CLEAN_TIME)

        "#{Date.strptime(day, '%d %B %Y').iso8601}T#{time}"
      rescue Date::Error
        stamp
      end

      # A block's text: <br/> → line break, <g> → decoded Greek, the rest
      # by its text; lines squeezed, blanks dropped. nil when empty.
      def block_text(node, greek: false)
        return nil if node.nil?

        raw = +""
        walk(node, raw)
        raw = Betacode.decode(raw) if greek
        lines = raw.split("\n").map { |line| squeeze(line) }.reject(&:empty?)
        lines.empty? ? nil : Normalize.nfc(lines.join("\n"))
      end

      def walk(node, out)
        node.children.each do |child|
          if child.text?
            out << child.text
          elsif child.name == "br"
            out << "\n"
          elsif child.name == "g"
            out << Betacode.decode(child.text)
          elsif child.element?
            walk(child, out)
          end
        end
      end

      def squeeze(text) = text.gsub(/[[:space:]]+/, " ").strip
    end
  end
end
