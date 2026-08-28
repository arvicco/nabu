# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser family "onw-tei" (P84-7): the Corpus Oudnederlands TEI P5 layout
    # (INT/IvdNT, "een verzameling van al het overgebleven Nederlandse
    # woordmateriaal uit de periode 475-1200"). One file = one work (a source
    # text); its body is a run of <div1> CITATIONS (citaten), each a single
    # attested Old-Dutch snippet.
    #
    # == The teiHeader
    #
    #   <idno type="sourceID">onw_<id></idno>   the stable source id
    #   <idno type="pid">INT_<uuid></idno>      the persistent handle
    #   <date>701-800</date> | <date>831</date> the witness-year span
    #   <interpGrp type="place|region|country">  the flattened localisation
    #
    # The <id> half of sourceID is exactly the filename stem (act.fl..xml →
    # onw_act.fl.), so the adapter mints the urn from the filename and this
    # parser reads sourceID/pid only to CONFIRM and to carry as metadata.
    #
    # == One citation → one passage
    #
    #   <div1 xml:id="…citaat…">
    #     <cit type="context"><quote>…</quote></cit>       raw context (kept)
    #     <cit type="translation"><quote>…</quote></cit>   modern-Dutch gloss
    #     <p> <w pos=… lemma=…><seg>form</seg>…</w> … </p> the tokenised reading
    #
    # This is a GOLD lemma+POS source: the reading text is the space-join of
    # the <w>/<seg> surface forms, and each <w> yields a token carrying its
    # form, its upstream lemma (the CAPS citation form, e.g. KAM / NEDERGAAN)
    # and its full pos string — the treebank "tokens" shape the indexer's
    # lemma layer reads. A <w> with no @lemma (a foreign RES gloss) contributes
    # a form-only token, so the odt lemma index is never polluted with Latin.
    # A citation whose <p> flattens to nothing falls back to its context quote;
    # one that flattens to nothing at all is skipped (never a zero-text passage).
    class OnwTeiParser
      Work = Data.define(:source_id, :pid, :title, :not_before, :not_after,
                         :date_raw, :place, :region, :country, :citations)
      Citation = Data.define(:seq, :citaat_id, :text, :translation, :context, :tokens)

      DATE_SHAPE = /\A(\d{1,4})(?:-(\d{1,4}))?\z/

      # Parse one work from XML bytes; +name+ is the member/file name for
      # error messages only.
      def work(xml_bytes, name:)
        doc = parse_xml(xml_bytes, name)
        doc.remove_namespaces!
        header = doc.at_xpath("//teiHeader")
        raise ParseError, "#{name}: no teiHeader" if header.nil?

        nb, na, raw = date_span(header)
        Work.new(
          source_id: idno(header, "sourceID"), pid: idno(header, "pid"),
          title: text_of(header.at_xpath(".//titleStmt/title")),
          not_before: nb, not_after: na, date_raw: raw,
          place: interp(header, "place"), region: interp(header, "region"),
          country: interp(header, "country"),
          citations: citations(doc, name)
        )
      end

      private

      def parse_xml(bytes, name)
        document = Nokogiri::XML(bytes, &:strict)
        raise ParseError, "#{name}: malformed ONW TEI: #{document.errors.first}" unless document.errors.empty?

        document
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{name}: malformed ONW TEI: #{e.message}"
      end

      def citations(doc, _name)
        seq = 0
        doc.xpath("//text//body//div1").filter_map do |div1|
          tokens = tokens_of(div1)
          text = token_text(tokens)
          context = normalize(text_of(div1.at_xpath(".//cit[@type='context']/quote")))
          text = context if text.empty?
          next if text.empty?

          seq += 1
          Citation.new(
            seq: seq, citaat_id: div1["id"] || div1["xml:id"],
            text: text, context: context,
            translation: normalize(text_of(div1.at_xpath(".//cit[@type='translation']/quote"))),
            tokens: tokens
          )
        end
      end

      # One token per <w>: form (the joined <seg> surface), the upstream lemma
      # (dropped when blank — foreign/unlemmatised words), and the pos strings.
      def tokens_of(div1)
        div1.xpath(".//p//w").filter_map do |w|
          form = normalize(w.xpath(".//seg").map(&:text).join(" "))
          next if form.empty?

          token = { "form" => form }
          lemma = w["lemma"].to_s.strip
          token["lemma"] = lemma unless lemma.empty?
          pos = w["pos"].to_s.strip
          token["pos"] = pos unless pos.empty?
          main = w["groupingMainPos"].to_s.strip
          token["main_pos"] = main unless main.empty?
          token
        end
      end

      def token_text(tokens)
        normalize(tokens.map { |t| t["form"] }.join(" "))
      end

      def idno(header, type)
        value = text_of(header.at_xpath(".//idno[@type='#{type}']"))
        value.empty? ? nil : value
      end

      # The flattened <interpGrp type="place"><interp>…</interp> — first
      # non-blank interp, or nil.
      def interp(header, type)
        header.xpath(".//interpGrp[@type='#{type}']/interp").map { |i| normalize(i.text) }
                                                            .find { |v| !v.empty? }
      end

      def date_span(header)
        raw = text_of(header.at_xpath(".//publicationStmt//date"))
        m = DATE_SHAPE.match(raw) or return [nil, nil, (raw.empty? ? nil : raw)]

        lo = Integer(m[1], 10)
        hi = m[2] ? Integer(m[2], 10) : lo
        [lo, hi, raw]
      end

      def text_of(node)
        node.nil? ? "" : normalize(node.text)
      end

      def normalize(text)
        Nabu::Normalize.nfc(text.to_s.gsub(/\s+/, " ").strip)
      end
    end
  end
end
