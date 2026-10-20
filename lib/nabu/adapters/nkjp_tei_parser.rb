# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The `nkjp-tei` parser family (P116-1): the National Corpus of Polish
    # (NKJP) TEI P5 stand-off package, as the KorBa manually annotated
    # subcorpus ships it — one directory per text:
    #
    #   header.xml              teiHeader: the original's bibl (title,
    #                           author, publisher, pubPlace place/region,
    #                           date @when | @notBefore/@notAfter), an
    #                           optional nested modernized-edition bibl,
    #                           idno, and textClass catRefs (text form,
    #                           genre, kind, subject, ironic).
    #   text.xml                the transcription: body/div/ab blocks with
    #                           <pb n=…/> page breaks, <foreign xml:lang>
    #                           and <uncertain reason> spans.
    #   ann_segmentation.xml    p/s/seg — each seg a string-range into a
    #                           text.xml element (the ab, or a foreign /
    #                           uncertain span inside it); segmentation
    #                           ambiguity as <choice> whose nkjp:paren
    #                           alternative segs carry nkjp:rejected="true".
    #   ann_morphosyntax.xml    one seg per segmentation seg: orth (the
    #                           modernized spelling), translit (the
    #                           transcribed spelling, as in text.xml), the
    #                           candidate lex interpretations (base, ctag,
    #                           msd — msd alternatives in vAlt), and the
    #                           disamb choice pointing at one msd symbol.
    #
    # Output: a Text (header hash + blocks). A Block is one <ab>: its text
    # (text content, whitespace runs collapsed — the export is pretty-
    # printed; NFC is the adapter's job), the pages it touches, foreign and
    # uncertain spans, and its tokens in file order. A token is
    # {"form" => translit, "orth" => orth} plus "lemma"/"xpos" (ctag[:msd])
    # when the disamb chose an interpretation with a non-empty base, and
    # "lang" when the seg lies in a <foreign> span (foreign segs carry no
    # interpretation upstream). Rejected segmentation alternatives never
    # become tokens. The morphosyntax layer is streamed (SAX — the largest
    # files run to several MB); the other layers are small DOMs.
    class NkjpTeiParser
      Block = Data.define(:id, :n, :text, :pages, :foreign, :uncertain, :tokens)
      Text = Data.define(:header, :blocks)

      LAYERS = %w[header.xml text.xml ann_segmentation.xml ann_morphosyntax.xml].freeze
      RANGE = /string-range\(([^,]+),/

      def parse(dir)
        missing = LAYERS.reject { |name| File.file?(File.join(dir, name)) }
        raise Nabu::ParseError, "#{dir}: missing NKJP layer(s) #{missing.join(', ')}" unless missing.empty?

        header = parse_header(read_xml(File.join(dir, "header.xml")))
        blocks, owner, langs = parse_text(read_xml(File.join(dir, "text.xml")))
        segments = parse_segmentation(read_xml(File.join(dir, "ann_segmentation.xml")))
        attach_tokens(File.join(dir, "ann_morphosyntax.xml"), blocks, segments, owner, langs)
        Text.new(header: header, blocks: blocks.values.map { |b| Block.new(**b) })
      end

      private

      def read_xml(path)
        doc = Nokogiri::XML(File.read(path, encoding: Encoding::UTF_8), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # --- header ---------------------------------------------------------

      def parse_header(doc)
        bibl = doc.at_xpath("//sourceDesc/bibl[@type='original']") || doc.at_xpath("//sourceDesc/bibl")
        return {} unless bibl

        {
          "title" => text_of(bibl.at_xpath("./title")),
          "author" => text_of(bibl.at_xpath("./author")),
          # The translator of a translated work (korba: 322 headers, one
          # per header — "Paweł Łęczycki", upstream's "Anonim"/"?" claims
          # and "(tł. domn.)" attribution hedges all verbatim).
          "translator" => text_of(bibl.at_xpath("./editor[@role='translator']")),
          "publisher" => text_of(bibl.at_xpath("./publisher")),
          "place" => text_of(bibl.at_xpath("./pubPlace[@role='place']")),
          "region" => text_of(bibl.at_xpath("./pubPlace[@role='region']")),
          "date" => date_of(bibl.at_xpath("./date")),
          "idno" => text_of(bibl.at_xpath("./idno")),
          "availability" => doc.at_xpath("//publicationStmt/availability")&.[]("status"),
          "modernized_edition" => modernized(bibl.at_xpath("./bibl[@type='modernized']")),
          "classes" => classes(doc)
        }.compact
      end

      def text_of(node)
        return nil if node.nil?

        value = node.text.gsub(/[[:space:]]+/, " ").strip
        value.empty? ? nil : value
      end

      def date_of(node)
        return nil unless node

        from = (node["notBefore"] || node["when"]).to_s[/\A-?\d{1,4}/]&.to_i
        to = (node["notAfter"] || node["when"]).to_s[/\A-?\d{1,4}/]&.to_i
        raw = text_of(node)
        # KorBa's one descending range (RespList: notBefore 1733 /
        # notAfter 1709, "między 1733 a 1709" — "between 1733 and 1709"):
        # a between-range of explicit CE years, so the P59-0 ladder's
        # order-normalizing swap stays within upstream's own claim.
        from, to = Nabu::Timeline.normalize_interval(from, to, raw: raw)
        { "not_before" => from, "not_after" => to, "raw" => raw }.compact
      end

      def modernized(node)
        return nil unless node

        {
          "title" => text_of(node.at_xpath(".//bibl[@type='monogr']/title") || node.at_xpath(".//title")),
          "editor" => text_of(node.at_xpath(".//editor")),
          "pub_place" => text_of(node.at_xpath(".//pubPlace")),
          "publisher" => text_of(node.at_xpath(".//publisher")),
          "date" => text_of(node.at_xpath(".//date"))
        }.compact
      end

      # scheme → [codes]: a catRef @target may name several categories,
      # space-separated ("#pisma_rel #satyry" — censused on KorBa's kind
      # and subject schemes).
      def classes(doc)
        refs = doc.xpath("//textClass/catRef").filter_map do |ref|
          scheme = ref["scheme"].to_s.delete_prefix("#")
          targets = ref["target"].to_s.split.map { |t| t.delete_prefix("#") }.reject(&:empty?)
          [scheme, targets] unless scheme.empty? || targets.empty?
        end
        refs.empty? ? nil : refs.to_h
      end

      # --- text.xml -------------------------------------------------------

      # Returns [blocks (id → attrs), owner (any xml:id → its ab id),
      # langs (span id → xml:lang for foreign spans and their descendants)].
      def parse_text(doc)
        blocks = {}
        owner = {}
        langs = {}
        page = nil
        doc.xpath("//body//ab").each do |ab|
          id = ab["id"] or raise Nabu::ParseError, "text.xml: an <ab> without xml:id"
          pages = page ? [page] : []
          ab.xpath(".//pb").each do |pb|
            page = pb["n"]
            pages << page unless pages.include?(page) || page.nil?
          end
          owner[id] = id
          ab.xpath(".//*[@id]").each { |node| owner[node["id"]] = id }
          ab.xpath(".//foreign[@id]").each do |span|
            langs[span["id"]] = span["lang"]
            span.xpath(".//*[@id]").each { |inner| langs[inner["id"]] = span["lang"] }
          end
          blocks[id] = {
            id: id, n: ab["n"], text: ab.text.gsub(/[[:space:]]+/, " ").strip, pages: pages,
            foreign: ab.xpath(".//foreign").map { |f| { "lang" => f["lang"], "text" => text_of(f) }.compact },
            uncertain: ab.xpath(".//uncertain").map { |u| { "reason" => u["reason"], "text" => text_of(u) }.compact },
            tokens: []
          }
        end
        [blocks, owner, langs]
      end

      # --- ann_segmentation.xml -------------------------------------------

      # segm id → target text.xml id, for every seg that is not a rejected
      # alternative.
      def parse_segmentation(doc)
        doc.xpath("//seg").each_with_object({}) do |seg, map|
          next if seg["rejected"] == "true"
          # An empty placeholder seg (type="g", no range, no <w>) marks a
          # join, not a segment — censused in 8 texts; nothing to attach.
          next if seg["corresp"].nil? && seg.at_xpath("w").nil?

          target = seg["corresp"].to_s[RANGE, 1] or
            raise Nabu::ParseError, "ann_segmentation.xml: seg #{seg['id']} has no string-range"
          map[seg["id"]] = target
        end
      end

      # --- ann_morphosyntax.xml (streamed) --------------------------------

      def attach_tokens(path, blocks, segments, owner, langs)
        handler = MorphHandler.new do |segm_id, token|
          target = segments[segm_id]
          next if target.nil? # a rejected alternative

          block_id = owner[target] or
            raise Nabu::ParseError, "#{path}: seg #{segm_id} points at unknown text id #{target}"
          token["lang"] = langs[target] if langs[target]
          blocks.fetch(block_id)[:tokens] << token
        end
        File.open(path, "rb") { |io| Nokogiri::XML::SAX::Parser.new(handler, "UTF-8").parse(io) }
        raise Nabu::ParseError, "#{path}: malformed XML: #{handler.failure}" if handler.failure
      end

      # SAX state machine over morph segs: collects orth/translit, each lex
      # interpretation (base, ctag, msd symbols by id) and the disamb choice.
      class MorphHandler < Nokogiri::XML::SAX::Document
        attr_reader :failure

        def initialize(&on_token)
          super()
          @on_token = on_token
          @seg = nil
          @path = []
          @failure = nil
        end

        def start_element_namespace(name, attrs = [], _prefix = nil, _uri = nil, _namespaces = [])
          attrs = attrs.to_h { |a| [a.localname, a.value] }
          case name
          when "seg"
            @seg = { corresp: attrs["corresp"].to_s.split("#", 2).last, lexes: [], msd: {}, choice: nil }
          when "f" then start_feature(attrs)
          when "fs" then @seg[:lexes] << { id: attrs["id"] } if @seg && attrs["type"] == "lex"
          when "symbol" then symbol(attrs)
          when "string" then @buffer = +""
          end
          @path.push([name, attrs["name"]])
        end

        def end_element_namespace(name, _prefix = nil, _uri = nil)
          @path.pop
          case name
          when "string" then string_done
          when "seg" then seg_done
          end
        end

        def characters(text)
          @buffer << text if @buffer
        end
        alias cdata_block characters

        def error(message)
          @failure = message if @failure.nil?
        end

        private

        def start_feature(attrs)
          return unless @seg

          @seg[:choice] = attrs["fVal"].to_s.delete_prefix("#") if attrs["name"] == "choice"
        end

        def feature
          @path.reverse_each { |(element, fname)| return fname if element == "f" }
          nil
        end

        def symbol(attrs)
          return unless @seg

          lex = @seg[:lexes].last
          case feature
          when "ctag" then lex[:ctag] = attrs["value"] if lex
          when "msd"
            @seg[:msd][attrs["id"]] = [lex, attrs["value"].to_s] if attrs["id"]
          end
        end

        def string_done
          value = @buffer
          @buffer = nil
          return unless @seg

          case feature
          when "orth" then @seg[:orth] = value
          when "translit" then @seg[:translit] = value
          when "base" then (lex = @seg[:lexes].last) && (lex[:base] = value)
          end
        end

        def seg_done
          seg = @seg
          @seg = nil
          return if seg.nil? || seg[:corresp].to_s.empty?

          token = { "form" => seg[:translit] || seg[:orth], "orth" => seg[:orth] }.compact
          lex, msd = seg[:msd][seg[:choice]] if seg[:choice]
          if lex && !lex[:base].to_s.empty?
            token["lemma"] = lex[:base]
            token["xpos"] = [lex[:ctag], msd].reject { |part| part.nil? || part.empty? }.join(":")
          end
          @on_token.call(seg[:corresp], token)
        end
      end
    end
  end
end
