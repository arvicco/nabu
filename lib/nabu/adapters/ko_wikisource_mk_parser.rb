# frozen_string_literal: true

module Nabu
  module Adapters
    # The ko.wikisource page grammar (P78-4): one wikitext page carries a
    # whole work — a {{머리말}} header template (제목 the display title,
    # 연도 the machine year), optional hanmun preface sections (paratext,
    # ignored), then the cantos as == 제N장 == h2 sections. The layers are
    # TEMPLATE-marked, which is what makes the extraction honest:
    #
    #   {{옛한글 인라인|…}}   Middle Korean verse line (archaic conjoining
    #                         jamo + 방점 tone marks U+302E/302F), wherever
    #                         it appears in the canto — under a === 중세국어
    #                         === heading or bare (84 of 125 cantos carry no
    #                         layer headings at all);
    #   {{윗주|漢字|reading}}  hanmun ruby pair under === 한문 === — the
    #                         1447 print's parallel Chinese verse with the
    #                         wiki's modern-Korean reading gloss; canto 47
    #                         carries PLAIN hanmun lines with no 윗주
    #                         wrapper (text only, reading nil);
    #   plain hangul lines    the modern rendering — under === 현대어 ===,
    #                         or headingless after the MK templates (canto
    #                         125). Template/link/markup lines never
    #                         classify as text.
    #
    # The parser returns verbatim layer lines (markup stripped, NO
    # normalization — NFC is the adapter boundary's job, CLAUDE.md §Ruby).
    class KoWikisourceMkParser
      Work = Data.define(:title, :year, :cantos)
      Canto = Data.define(:number, :mk_lines, :hanmun_lines, :modern_lines)
      HanmunLine = Data.define(:text, :reading)

      H2 = /^==([^=].*?)==\s*$/
      H3 = /^===\s*(.*?)\s*===\s*$/
      CANTO_HEADING = /\A제(\d+)장\z/
      MK_TEMPLATE = /\{\{옛한글 인라인\|(.*?)\}\}/
      RUBY_TEMPLATE = /\{\{윗주\|([^|{}]*)\|([^|{}]*)\}\}/

      def parse(wikitext)
        header = header_params(wikitext)
        Work.new(
          title: presence(header["제목"]),
          year: year_from(header["연도"]),
          cantos: cantos(wikitext)
        )
      end

      private

      # The {{머리말}} block's |key = value lines (first block only; values
      # needed here are plain — 제목, 연도).
      def header_params(wikitext)
        block = wikitext[/\{\{머리말(.*?)^\}\}/m, 1] or return {}
        block.scan(/^\|\s*([^=|]+?)\s*=\s*(.*)$/).to_h { |key, value| [key.strip, value.strip] }
      end

      def year_from(raw)
        raw = raw.to_s[/\d{3,4}/]
        raw&.to_i
      end

      def cantos(wikitext)
        sections(wikitext).filter_map do |heading, body|
          number = heading[CANTO_HEADING, 1] or next
          build_canto(number.to_i, body)
        end
      end

      # [heading, body] pairs of the page's h2 sections, page order.
      def sections(wikitext)
        parts = wikitext.split(H2)
        parts.shift # the pre-section preamble (header template, notices)
        parts.each_slice(2).map { |heading, body| [heading.strip, body.to_s] }
      end

      def build_canto(number, body)
        subsections = subsections(body)
        bare = subsections.fetch(nil, "")
        Canto.new(
          number: number,
          mk_lines: mk_lines(body),
          hanmun_lines: hanmun_lines(subsections.fetch("한문", "")),
          modern_lines: plain_lines(subsections.fetch("현대어", "")) + plain_lines(bare)
        )
      end

      # h3 heading → body within one canto; nil keys the headingless region
      # before the first h3 (the whole body for the 84 bare cantos).
      def subsections(body)
        parts = body.split(H3)
        map = { nil => parts.shift.to_s }
        parts.each_slice(2) { |heading, text| map[heading.strip] = text.to_s }
        map
      end

      # Every MK template in the canto, page order — under a 중세국어
      # heading or bare, the marking is the template itself.
      def mk_lines(body)
        body.scan(MK_TEMPLATE).map { |(text)| text.strip }.reject(&:empty?)
      end

      # 윗주 ruby pairs line by line; a template-free non-markup line is a
      # plain hanmun line (canto 47), reading honestly nil.
      def hanmun_lines(text)
        text.lines.flat_map do |line|
          pairs = line.scan(RUBY_TEMPLATE).map { |hanzi, reading| ruby_line(hanzi, reading) }
          next pairs unless pairs.empty?

          plain = clean(line)
          plain ? [HanmunLine.new(text: plain, reading: nil)] : []
        end
      end

      def ruby_line(hanzi, reading)
        HanmunLine.new(text: hanzi.strip, reading: presence(reading.strip))
      end

      # Markup-free text lines: tags and <br> stripped; template, link,
      # image and leftover-markup lines are never text.
      def plain_lines(text)
        text.lines.filter_map { |line| clean(line) }
      end

      def clean(line)
        return nil if line.include?("{{") || line.lstrip.start_with?("[[", "#")

        stripped = line.gsub(%r{</?(?:br|big)\s*/?>}, "").strip
        return nil if stripped.empty? || stripped.include?("<") || stripped.include?("]]")

        stripped
      end

      def presence(value)
        value = value.to_s.strip
        value.empty? ? nil : value
      end
    end
  end
end
