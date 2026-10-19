# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser family "itkc-xml" (P78-7): the ITKC 한국고전종합DB export
    # schema — Korean-tag XML, one zip per WORK. The suffix-less SIDECAR
    # file (ITKC_GO_1295A.xml) carries the 서지 record: hanja/hangul
    # title pair, the author with 생년/몰년 machine years, and the
    # 원문간행년 ORIGINAL print year (서기년 attr — 1780 for 고운당필기,
    # 1895 for 국조보감; the 간행기간 2020s years are the modern edition,
    # deliberately not read). Each 권차 fascicle file nests 레벨3
    # articles — the citation units — each with its own title, author,
    # 문체분류 genre chain, 고유명사 proper-noun tags in the text, and a
    # 연계정보 pointer into ITKC's own 번역문 translation layer (carried
    # as an annotation: a future crosswalk key, promised nothing).
    #
    # Upstream quirks (censused 2026-08-18, recorded not fixed): the
    # 아이템 name attr is inconsistent across files of ONE work (the
    # 고운당필기 sidecar says 고전원문, its fascicles say 한국문집총간
    # 교감표점서); the 언어 element says "coc" — ITKC's internal code,
    # NOT ISO 639-3 (which assigns coc to Cocopa); the text is Literary
    # Chinese and the adapter says lzh. DOM, not SAX: fascicle files run
    # tens–hundreds of KB, nowhere near the ~5 MB line.
    class ItkcXmlParser
      # The 서지 sidecar. +print_year+ is the 원문간행년 서기년 (nil
      # when the record carries none — claim nothing). +authors+ lists
      # every 저자 with its 생년/몰년 life years (see #author_record);
      # +subject_class+ is the 주제분류 label, +sabu_division+ /
      # +sabu_class+ the 사부분류 대분류/중분류 pair, verbatim. The KP
      # family's third scheme, 고전적분류 (대분류 역사편 over the same
      # 중분류 the 사부분류 already names), DELIBERATELY stays unread —
      # a restatement, not a new claim (census over the 26 held
      # sidecars, 2026-10-18).
      Work = Data.define(:id, :title_hanja, :title_hangul, :author_hanja, :author_hangul, :print_year,
                         :authors, :subject_class, :sabu_division, :sabu_class)

      # 생년/몰년 서기년 values upstream uses for "unknown" (金正浩 18??
      # carries 9999; the KP 校正廳 records 0000/9999) — never a year.
      UNKNOWN_YEARS = %w[0000 9999].freeze

      # One 권차 file. +articles+ are its 레벨3 units in document order.
      Fascicle = Data.define(:id, :title, :articles)

      Article = Data.define(:id, :dci, :title, :author_hangul, :author_hanja,
                            :genre_classes, :translation_ref, :text)

      def parse_work(path)
        level1 = root_level1(path)
        meta = level1.at_xpath("./메타정보")
        Work.new(
          id: level1["id"],
          title_hanja: text_at(meta, ".//제목정보/제목[@type='한자서명']"),
          title_hangul: text_at(meta, ".//제목정보/제목[@type='한글서명']"),
          author_hanja: text_at(meta, ".//저자정보//한자성명"),
          author_hangul: text_at(meta, ".//저자정보//한글성명"),
          print_year: year_attr(meta, ".//간행정보/원문간행년"),
          authors: meta ? meta.xpath(".//저자정보/저자").filter_map { |node| author_record(node) } : [],
          subject_class: text_at(meta, ".//분류항목[@type='주제분류']/분류내용"),
          sabu_division: text_at(meta, ".//분류항목[@type='사부분류']/분류내용[@type='대분류']"),
          sabu_class: text_at(meta, ".//분류항목[@type='사부분류']/분류내용[@type='중분류']")
        )
      end

      def parse_fascicle(path)
        level2 = root_level1(path).at_xpath("./레벨2") or
          raise Nabu::ParseError, "itkc-xml: #{File.basename(path)}: no 레벨2 권차"
        Fascicle.new(
          id: level2["id"],
          title: text_at(level2, "./메타정보/제목정보/제목"),
          # The article is upstream's OWN marker — type="최종정보" — which
          # sits at 레벨3 in the GP works and 레벨4 in GO (whose 레벨3 is
          # a genre section). The marker, not the level name, is the grain.
          articles: level2.xpath(".//*[@type='최종정보']").map { |node| build_article(node) }
        )
      end

      private

      def root_level1(path)
        xml = Nokogiri::XML(File.read(path, encoding: Encoding::UTF_8)) do |config|
          config.strict.nonet
        end
        level1 = xml.root&.at_xpath("./레벨1")
        raise Nabu::ParseError, "itkc-xml: #{File.basename(path)}: no 아이템/레벨1 root" if level1.nil?

        level1
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "itkc-xml: #{File.basename(path)}: #{e.message}"
      end

      def build_article(node)
        meta = node.at_xpath("./메타정보")
        Article.new(
          id: node["id"], dci: node["DCI"],
          title: text_at(meta, ".//제목정보/제목"),
          author_hangul: text_at(meta, ".//저자정보//한글성명"),
          author_hanja: text_at(meta, ".//저자정보//한자성명"),
          genre_classes: meta ? meta.xpath(".//분류항목[@type='문체분류']/분류내용").map { |n| n.text.strip } : [],
          translation_ref: node.at_xpath("./연계정보/연계항목[@type='번역문']")&.attr("연계시작"),
          text: article_text(node)
        )
      end

      # 단락 paragraphs, one line each: 고유명사/페이지 markers flatten
      # to their text, whitespace runs collapse — canonical means
      # canonical, only the markup shed. The 고유명사 proper-noun tags
      # (239,405 over the held works, census 2026-10-18) are UNTYPED —
      # no person/place/book distinction, no authority id — so they
      # DELIBERATELY mint no entity rows; a typed reading needs an
      # external resolver, not this parser.
      def article_text(node)
        paragraphs = node.xpath("./본문정보/내용/단락").map { |paragraph| squish(paragraph.text) }
        paragraphs.reject(&:empty?).join("\n")
      end

      def text_at(node, xpath)
        return nil if node.nil?

        value = node.at_xpath(xpath)&.text
        value = value&.gsub(/\s+/, " ")&.strip
        value unless value.nil? || value.empty?
      end

      # One 저자: hanja/hangul names, the 생년/몰년 서기년 CE years (the
      # unknown sentinels claim nothing) and the elements' own reign-year
      # text raw ("영조 24", "18??"). Nil for a nameless, dateless node.
      def author_record(node)
        record = {
          "name" => text_at(node, "./한자성명"), "name_hangul" => text_at(node, "./한글성명"),
          "birth_year" => life_year(node, "./생년"), "death_year" => life_year(node, "./몰년"),
          "birth" => text_at(node, "./생년"), "death" => text_at(node, "./몰년")
        }.compact
        record.empty? ? nil : record
      end

      def life_year(node, xpath)
        year = node.at_xpath(xpath)&.attr("서기년")
        return nil if year.nil? || UNKNOWN_YEARS.include?(year) || !year.match?(/\A\d{1,4}\z/)

        year.to_i
      end

      def year_attr(node, xpath)
        year = node&.at_xpath(xpath)&.attr("서기년")
        year&.match?(/\A\d{1,4}\z/) ? year.to_i : nil
      end

      def squish(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
