# frozen_string_literal: true

require_relative "litopys_html_parser"

module Nabu
  module Adapters
    # litopys's declared secondary dictionary lane (Adapter.dictionary_lane,
    # the P104-4 multi-shelf seam): the three PD-edition glossaries of the
    # site's «Лексикони» shelf (the edition triage lives on Litopys::TRIAGE).
    # Each glossary is its own small dictionary shelf:
    #
    #   litopys-lexis-prosto      zyzlex/zyz100.htm — «Лексисъ съ толкованіемъ
    #       словенскихъ мовъ просто» (Amfilokhii, Чтения ОИДР 1884): Church
    #       Slavonic words glossed "plainly" in the vernacular; 688 entries
    #   litopys-rech-zhidovska    zyzlex/zyz101.htm — «Рѣчь жидовьскаго языка,
    #       преложена на Роускую…» (the 1282 Kormchaya onomasticon): Hebrew
    #       names glossed in Slavonic; 174 entries
    #   litopys-tlkovanie         zyzlex/zyz102.htm — «Тлъкованїє неудобь
    #       познаваемомъ въ писаныхъ речемь» (1431): hard words of the
    #       translated books (Slavonic, Serbian, Bulgarian, Greek) glossed in
    #       Rus'; 61 entries (the Kanzler list breaks off at «Балство»)
    #   (entry counts: live census 2026-10-11)
    #
    # Entry = the site's "<b>headword</b>, gloss." line; entry_id = its
    # 1-based ordinal on the page (a frozen 19th-c. edition — the order IS
    # the edition's), headword verbatim (the 1884 editor's "(л)" expansions,
    # the site's stress accents that stand for the print's superscript dots
    # — upstream's own note), gloss = the rest of the line, footnote keys
    # dropped. zyz100's column header line «по слове(н)ску, просто» is the
    # print's table head, not an entry (censused, HEADERS).
    #
    # Language orv — DELIBERATELY COARSE, declared: the headwords are Church
    # Slavonic (zyz100, zyz102) and Hebrew names in Cyrillic (zyz101), the
    # glosses East Slavic; the shelf is filed under the East Slavic
    # manuscript tradition that carried all three.
    class LitopysGlossaryLane < Nabu::Adapter
      LANGUAGE = "orv"
      REF_PREFIX = "litopys-glossary:"

      Glossary = Data.define(:path, :slug, :title, :headers)
      GLOSSARIES = [
        Glossary.new(path: "zyzlex/zyz100.htm", slug: "litopys-lexis-prosto",
                     title: "Лексисъ съ толкованіемъ словенскихъ мовъ просто (Amfilokhii, Чтения ОИДР 1884)",
                     headers: ["по слове(н)ску"]),
        Glossary.new(path: "zyzlex/zyz101.htm", slug: "litopys-rech-zhidovska",
                     title: "Рѣчь жидовьскаго языка, преложена на Роускую (1282)", headers: []),
        Glossary.new(path: "zyzlex/zyz102.htm", slug: "litopys-tlkovanie",
                     title: "Тлъкованїє неудобь познаваемомъ въ писаныхъ речемь (1431)", headers: [])
      ].freeze

      def self.manifest = Litopys::MANIFEST

      def self.content_kind = :dictionary

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        GLOSSARIES.each do |glossary|
          path = File.join(workdir, glossary.path)
          next unless File.file?(path)
          next if drifted?(path)

          yield Nabu::DocumentRef.new(source_id: Litopys::SLUG, id: "#{REF_PREFIX}#{glossary.slug}",
                                      path: File.expand_path(path), metadata: { "dictionary" => glossary.slug })
        end
      end

      def parse(document_ref)
        glossary = GLOSSARIES.find { |candidate| document_ref.id == "#{REF_PREFIX}#{candidate.slug}" } or
          raise Nabu::ParseError, "litopys: unknown glossary ref #{document_ref.id}"
        page = LitopysHtmlParser.glossary(File.binread(document_ref.path),
                                          path: document_ref.path, headers: glossary.headers)
        raise Nabu::ParseError, "litopys: #{glossary.path}: no glossary entries" if page.entries.empty?

        document = Nabu::DictionaryDocument.new(slug: glossary.slug, language: LANGUAGE, title: glossary.title,
                                                canonical_path: document_ref.path)
        page.entries.each_with_index do |entry, index|
          document << build_entry(entry, index + 1)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "litopys glossary #{document_ref.id}: #{e.message}"
      end

      private

      # The discover-time rule re-check: a glossary page whose own "[…]"
      # statement now names a post-1930 edition is skipped.
      def drifted?(path)
        statement = LitopysHtmlParser.glossary(File.binread(path), path: path).statement
        LitopysHtmlParser.tainted?(statement)
      rescue Nabu::ParseError
        true
      end

      def build_entry(entry, ordinal)
        Nabu::DictionaryEntry.new(
          entry_id: ordinal.to_s, key_raw: entry.headword, language: LANGUAGE,
          headword: entry.headword,
          headword_folded: Nabu::Normalize.search_form(entry.headword, language: LANGUAGE),
          gloss: entry.gloss, body: "#{entry.headword}, #{entry.gloss}"
        )
      end
    end
  end
end
