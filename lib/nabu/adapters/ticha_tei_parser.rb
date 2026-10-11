# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The ticha-tei parser family (P117-5): the Ticha project's TEI
    # transcriptions of colonial Valley Zapotec texts and their period
    # Spanish translations (github.com/HCDigitalScholarship/ticha-xml-tei).
    # A hand-encoded working corpus — the family is shaped by its real
    # quirks, censused file by file 2026-10-11:
    #
    # == Markup repair (only for files that are not well-formed)
    #
    # 86 of the 97 XML files carry NO teiHeader (only Córdova, the AGEO
    # files and the schema/example do); 80 of the adapter's 93 documents
    # are not well-formed as shipped (5,009 repairs in all). Three defect
    # classes, repaired in this order and COUNTED (the count rides the
    # result, never silent):
    #
    # 1. HTML-style <br> line breaks (never closed) inside TEI — read as
    #    TEI <lb/> (the encoders' evident intent: the README's own line-
    #    break guidance, with <br> where <lb/> belongs).
    # 2. Truncated files (the <br>-style manuscripts end without
    #    </text></TEI>) and
    #    stray end tags (Al698T/Al714T close every <choice> with a
    #    "</head>" that never opened; aguero carries add/note swaps, a
    #    bare <note> where </note> belongs, a reg closed as "/reg>") —
    #    a tag balancer: an end tag that matches the open element closes
    #    it; </add> vs </note> on the other one of the pair closes it (the
    #    swap typo); a bare <note>/<add> (no attributes) while the same
    #    element is open is read as its end tag; an end tag naming a
    #    deeper open element closes down to it; any other end tag is
    #    dropped; EOF closes what is open.
    # 3. A start tag broken mid-attribute (aguero line 23184:
    #    `<add place="above" M[?] …`) is not markup at all — its "<" is
    #    escaped and the run stays as text, verbatim.
    #
    # And in the reading: an orphan orig/reg (aguero's "choice><orig>…",
    # the <choice> lost its "<") keeps its own layer. Census over the
    # whole repo after repair: every file parses, and the word count of
    # the parsed tree equals the tag-stripped source's.
    #
    # == The reading
    #
    # Page = the span between <pb/> breaks. Córdova pairs every break: a
    # type="arte" pb (the book's own page/folio number, n="4" … "127r")
    # then a type="pdf" pb (the archive.org facsimile pointer — 264 of
    # them, one carrying a stray n="21"): a type="pdf" pb is never a page
    # of its own, its facs joins the current page. Likewise a <pb/>
    # WITHOUT @n with no text since the last break (the AGEO files'
    # facs-only breaks) joins it.
    # Before any <pb/>, text belongs to an implicit unnumbered first page.
    # Line = <lb/> or <cb/> (break="no" breaks the diplomatic line but
    # joins the regularized reading). Two layers per page:
    #
    #   text         the ORIGINAL reading: <choice> → orig | abbr | sic
    #   regularized  upstream's modern-Spanish reading: <choice> →
    #                reg type="spanish" (else the first reg) | expan | corr
    #
    # Kept OUT of the text, as page annotations: <head type="outline">
    # (the project's navigation outline — "outline"), <fw> (running
    # heads, catchwords — "forme_work"), <note>/<add>/<del> (marginalia,
    # interlinear additions, deletions — "apparatus" with type + place),
    # comments (encoder notes), the teiHeader. <gap/> mints nothing.
    #
    # == Languages
    #
    # The encoding marks the NON-default language: xml:lang on <foreign>
    # or on any ancestor (levanto-cathecismo marks whole divs). Upstream
    # tag values vary by file and are folded here: cvz / zap / xzp →
    # zap (Zapotec — the encoders' "cvz" is their own Colonial Valley
    # Zapotec label, the Córdova header's "xzp" the ISO 639-3 Ancient
    # Zapotec code), esp / span / es → spa, lat / latin → lat, nah →
    # nah. Unrecognized values ("lay", "margin right" — encoder typos)
    # are counted and inherit the enclosing language. The UNMARKED
    # default is a fact about each file, supplied by the caller.
    class TichaTeiParser
      Page = Data.define(:n, :facs, :text, :regularized, :languages, :foreign, :outline,
                         :apparatus, :forme_work)
      # prolog_comments: the encoders' comments before <TEI> (the Teitipac
      # files name their document there: "Testament from San Sebastián
      # Teitipac, 1744").
      Result = Data.define(:pages, :header_title, :header_languages, :prolog_comments, :repairs,
                           :unknown_lang_tags)

      LANG_FOLD = {
        "cvz" => "zap", "zap" => "zap", "xzp" => "zap",
        "esp" => "spa", "span" => "spa", "es" => "spa", "spa" => "spa",
        "lat" => "lat", "latin" => "lat", "la" => "lat",
        "nah" => "nah"
      }.freeze

      ORIG_CHILDREN = %w[orig abbr sic].freeze
      REG_CHILDREN = %w[reg expan corr].freeze
      APPARATUS = %w[note add del].freeze
      SILENT = %w[gap figure graphic teiHeader].freeze
      SWAP_PAIR = %w[add note].freeze

      # The tag grammar the balancer trusts: a name, then only well-formed
      # name="value" / name='value' attributes.
      START_TAG = %r{\A<([A-Za-z_][\w:.-]*)((?:\s+[\w:.-]+\s*=\s*(?:"[^"<]*"|'[^'<]*'))*)\s*(/?)>\z}m
      END_TAG = %r{\A</([A-Za-z_][\w:.-]*)\s*>\z}
      TOKEN = %r{<!--.*?-->|<\?.*?\?>|<!\[CDATA\[.*?\]\]>|<![^<>]*>|</?[A-Za-z_][^<>]*>|<|[^<]+}m
      BR = %r{<br\s*/?>}i
      BARE_AMPERSAND = /&(?!(?:[A-Za-z][\w.-]*|#\d+|#x\h+);)/

      def parse(path, default_language:)
        xml, repairs = load(path)
        doc = Nokogiri::XML(xml)
        doc.remove_namespaces!
        header_languages = doc.xpath("//teiHeader//language").to_h { |l| [l["ident"].to_s, l.text.strip] }
        header_title = doc.at_xpath("//teiHeader//titleStmt/title")&.text&.strip
        root = doc.at_xpath("//text") or raise Nabu::ParseError, "#{path}: no <text> element"

        @unknown = Hash.new(0)
        @pages = []
        open_page(number: nil, facs: [])
        walk(root, lang: default_language, layers: %i[orig reg])
        close_page
        Result.new(pages: @pages, header_title: header_title, header_languages: header_languages,
                   prolog_comments: doc.xpath("/comment()").map { |c| squash(c.text) }.reject(&:empty?),
                   repairs: repairs, unknown_lang_tags: @unknown.dup)
      end

      # [xml, repair_count] — the file verbatim when well-formed, else the
      # repaired reading (class note).
      def load(path)
        raw = File.read(path, encoding: "UTF-8").delete_prefix("﻿")
        begin
          Nokogiri::XML(raw, &:strict)
          return [raw, 0]
        rescue Nokogiri::XML::SyntaxError
          nil
        end
        repaired, count = repair(raw)
        Nokogiri::XML(repaired, &:strict)
        [repaired, count]
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: not well-formed even after repair: #{e.message}"
      end

      # The tag balancer (class note, defects 1–3). Returns [xml, count].
      def repair(raw)
        count = raw.scan(BR).size
        out = +""
        stack = []
        raw.gsub(BR, "<lb/>").scan(TOKEN) do |token|
          count += balance(token, stack, out)
        end
        stack.reverse_each { |name| out << "</#{name}>" }
        [out, count + stack.size]
      end

      private

      # Emits +token+ (repaired) into +out+; returns the repairs it took.
      def balance(token, stack, out)
        return emit(out, token, 0) if token.start_with?("<!--", "<?", "<!")

        if token.start_with?("</")
          close_tag(token, stack, out)
        elsif token.start_with?("<") && token.length > 1
          open_tag(token, stack, out)
        elsif token == "<"
          emit(out, "&lt;", 1)
        else
          text = token.gsub(BARE_AMPERSAND, "&amp;")
          emit(out, text, text == token ? 0 : 1)
        end
      end

      def close_tag(token, stack, out)
        name = token[END_TAG, 1]
        return emit(out, "&lt;#{token[1..]}", 1) if name.nil?
        return pop_emit(stack, out, 0) if stack.last == name
        return pop_emit(stack, out, 1) if SWAP_PAIR.include?(name) && SWAP_PAIR.include?(stack.last)

        depth = stack.rindex(name)
        return 1 if depth.nil? # a stray end tag: dropped

        repairs = stack.size - depth - 1
        out << "</#{stack.pop}>" until stack.size == depth
        repairs
      end

      def open_tag(token, stack, out)
        match = START_TAG.match(token)
        return emit(out, "&lt;#{token[1..]}", 1) if match.nil?

        name, attrs, self_closing = match.captures
        return pop_emit(stack, out, 1) if SWAP_PAIR.include?(name) && attrs.strip.empty? &&
                                          self_closing.empty? && stack.last == name

        stack << name if self_closing.empty?
        emit(out, token, 0)
      end

      def pop_emit(stack, out, repairs)
        out << "</#{stack.pop}>"
        repairs
      end

      def emit(out, text, repairs)
        out << text
        repairs
      end

      # -- the reading ---------------------------------------------------------

      def walk(node, lang:, layers:)
        node.children.each do |child|
          if child.text?
            add_text(child.text, lang: lang, layers: layers)
          elsif child.element?
            element(child, lang: element_lang(child, lang), layers: layers)
          end
        end
      end

      def element_lang(node, inherited)
        raw = node["lang"] or return inherited
        folded = LANG_FOLD[raw.strip.downcase]
        return folded if folded

        @unknown[raw] += 1
        inherited
      end

      def element(node, lang:, layers:)
        case node.name
        when "pb" then page_break(node)
        when "lb", "cb" then line_break(node, layers)
        when "choice" then choice(node, lang: lang, layers: layers)
        # An orphan orig/reg (its <choice> lost to a typo — aguero's
        # "choice><orig>…") keeps its own layer.
        when *ORIG_CHILDREN then walk(node, lang: lang, layers: layers & [:orig])
        when *REG_CHILDREN then walk(node, lang: lang, layers: layers & [:reg])
        when "head" then outline_or_walk(node, lang: lang, layers: layers)
        when "fw" then @page[:forme_work] << flat_text(node)
        when *APPARATUS then apparatus(node)
        when *SILENT then nil
        when "foreign" then foreign(node, lang: lang, layers: layers)
        else walk(node, lang: lang, layers: layers)
        end
      end

      def outline_or_walk(node, lang:, layers:)
        return walk(node, lang: lang, layers: layers) unless node["type"] == "outline"

        @page[:outline] << flat_text(node)
      end

      def choice(node, lang:, layers:)
        kids = node.element_children
        orig = kids.find { |k| ORIG_CHILDREN.include?(k.name) }
        regs = kids.select { |k| REG_CHILDREN.include?(k.name) }
        reg = regs.find { |k| k["type"] == "spanish" } || regs.first
        return walk(node, lang: lang, layers: layers) if orig.nil? && reg.nil?

        orig ||= reg
        reg ||= orig
        walk(orig, lang: element_lang(orig, lang), layers: layers & [:orig]) if layers.include?(:orig)
        walk(reg, lang: element_lang(reg, lang), layers: layers & [:reg]) if layers.include?(:reg)
      end

      def foreign(node, lang:, layers:)
        page = @page
        before = page[:orig].join("\n").length
        walk(node, lang: lang, layers: layers)
        return unless layers.include?(:orig) && page.equal?(@page) # a span across a page break: text only

        span = squash(@page[:orig].join("\n")[before..].to_s)
        @page[:foreign] << { "lang" => lang, "text" => span } unless span.empty?
      end

      def apparatus(node)
        entry = { "type" => node.name }
        entry["place"] = node["place"] if node["place"]
        entry["text"] = flat_text(node)
        @page[:apparatus] << entry unless entry["text"].empty?
      end

      def page_break(node)
        if node["type"] == "pdf" || (node["n"].nil? && !page_has_text?)
          @page[:facs] << node["facs"] if node["facs"]
          return
        end
        close_page
        open_page(number: node["n"], facs: [node["facs"]].compact)
      end

      def line_break(node, layers)
        @page[:orig] << +"" if layers.include?(:orig)
        @page[:reg].last << " " if layers.include?(:reg) && node["break"] != "no"
      end

      def add_text(text, lang:, layers:)
        @page[:orig].last << text if layers.include?(:orig)
        @page[:reg].last << text if layers.include?(:reg)
        return unless layers.include?(:orig)

        words = text.split.size
        @page[:languages][lang] += words if words.positive?
      end

      def open_page(number:, facs:)
        @page = { n: number, facs: facs, orig: [+""], reg: [+""], languages: Hash.new(0), foreign: [],
                  outline: [], apparatus: [], forme_work: [] }
      end

      def page_has_text?
        @page[:orig].any? { |line| !line.strip.empty? }
      end

      def close_page
        lines = @page[:orig].map { |line| squash(line) }.reject(&:empty?)
        return if lines.empty? # a blank page (cover, verso) mints nothing

        @pages << Page.new(
          n: @page[:n], facs: @page[:facs], text: lines.join("\n"),
          regularized: squash(@page[:reg].join(" ")), languages: @page[:languages].dup,
          foreign: @page[:foreign], outline: @page[:outline], apparatus: @page[:apparatus],
          forme_work: @page[:forme_work].reject(&:empty?)
        )
      end

      # An annotation element's text, its line breaks read as spaces.
      def flat_text(node)
        squash(node.xpath(".//text()|.//lb|.//cb").map { |n| n.text? ? n.text : " " }.join)
      end

      def squash(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
