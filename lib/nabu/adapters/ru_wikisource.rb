# frozen_string_literal: true

require_relative "slavic_wikisource_html"

module Nabu
  module Adapters
    # ru-wikisource (P116-3, under the owner-ruled Wikisource posture): the Old East Slavic shelf
    # of the Russian Wikisource — the DIRECT ns-0 members of the eight
    # censused categories (census 2026-10-10: 72 cone pages). The wiki's
    # premodern strength is thin and EDITION-TAINTED inside the wiki: the
    # ПВЛ page keys to the 1997 Библиотека литературы Древней Руси
    # edition (Творогов's text preparation), so every page's edition
    # statement (ИСТОЧНИК + ДАТАПУБЛИКАЦИИ + the title's dated segment)
    # is censused and the EDITION_TAINT_POST_1930 rule excludes any page
    # whose statement names a year after 1930 or a named post-1930 series
    # (TAINTED_SERIES — the BLDR and PLDR volumes, which ru pages cite by
    # series name and volume without a year). The az.lib.ru imports name
    # only the website in their header but open their BODY with the
    # source book's imprint (BODY_EVIDENCE) — 20 of them the 1989
    # «Виршевая поэзия». Census outcome over the 72 cone pages (live run
    # 2026-10-10): 12 admitted (the 1800 Слово, Костомаров's 1862
    # Памятники, Бычков 1897, the 1893 Мономах text, Кожанчиков's 1861/
    # 1862 prints, and web-sourced pages whose statement names no edition
    # — Никитин, Савва Грудцын, the az.lib.ru Аввакум Житие, the Аввакум
    # prayers, Азбучная молитва — verbatim), 31 edition-tainted (8 by
    # header, 23 by body head), 10 translations, 13 censused exclusions,
    # 2 encyclopedia articles, 2 modern-orthography duplicates, 1
    # apparatus page, 1 versions shell.
    #
    # Language orv throughout — declared coarse: the cone spans the
    # 11th-c. Мономах to the 17th-c. syllabic вирши (the orv:mid stage
    # is a named date-band candidate, never defaulted). The composition
    # date a page states (ДАТАСОЗДАНИЯ: "XIII век", "1672—1673 гг.",
    # "c 1238 по 1246 г") bands the grade-2 era envelope (era_band →
    # MetadataDates :era_band_key).
    class RuWikisource < SlavicWikisourceHtml
      API_URL = "https://ru.wikisource.org/w/api.php"
      STATE_FILE = ".ru-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:ru-wikisource:"
      LANGUAGE = "orv"

      CONE = {
        categories: {
          "Категория:Древнерусская литература" => 0,
          "Категория:Древнерусские повести" => 0,
          "Категория:Летописи" => 0,
          "Категория:Слово о полку Игореве" => 0,
          "Категория:Поучение Владимира Мономаха" => 0,
          "Категория:Молитва Владимира Мономаха" => 0,
          "Категория:Послание к Олегу Святославичу (Мономах)" => 0,
          # Despite its name the category holds ORIGINAL-language pages too
          # (the ПВЛ 1997 page, the 17th-c. вирши) — the rules sort it.
          "Категория:Переводы с древнерусского языка" => 0
        },
        prefixes: [],
        titles: []
      }.freeze

      VERSIONS_TEMPLATE = /\{\{\s*(Неоднозначность|Версии)\s*[|}]/i
      REFERENCE_PREFIXES = %w[ЭСБЕ/ МЭСБЕ/ НЭСГ/ БСЭ1/ РБС/ ЕЭБЕ/].freeze
      APPARATUS_SEGMENT = /\A(Историческое содержание песни|Переложение|Предисловие|Примечания)\z/
      # "(ВТ)" / "ВТ" marks the wiki's modern-orthography rendering of a
      # held old-orthography ("ДО") page — the same scans, re-spelled.
      MODERNIZED_SEGMENT = /\(ВТ\)\s*\z|\AВТ\z/
      EDITION_FIELDS = %w[ИСТОЧНИК ДАТАПУБЛИКАЦИИ].freeze
      TRANSLATOR_FIELDS = %w[ПЕРЕВОДЧИК].freeze
      # Отексте's АВТОР (НЕТ_АВТОРА pages carry none) and ИЗСБОРНИКА, the
      # collection a page belongs to.
      AUTHOR_FIELDS = %w[АВТОР].freeze
      WORK_FIELD = "ИЗСБОРНИКА"
      TAINTED_SERIES = [
        "Библиотека литературы Древней Руси", # BLDR, ИРЛИ РАН 1997–2012
        "Памятники литературы Древней Руси", # PLDR, Художественная литература 1978–1994
        "Подготовка текста" # the BLDR/PLDR text-preparation credit formula
      ].freeze
      # The az.lib.ru imports open with their source book's imprint in the
      # body ("Виршевая поэзия (первая половина XVII века) М., «Советская
      # Россия», 1989", "Полоцкий С. Вирши Мн.: Маст. літ., 1990",
      # "Русские путешественники в странах Востока М., 1938") and some
      # pages credit "Подготовка текста …" — a city-abbreviation imprint
      # with a year, or that credit, in the body head is edition evidence.
      BODY_EVIDENCE = /(?<!\p{L})(?:М|Л|Мн|СПб|К)\.?\s*[,:][^\n]{0,120}?(?<!\d)(?:1[5-9]\d\d|20\d\d)(?!\d)|
                       Подготовка\ текста[^\n=]*/x

      # Censused 2026-10-10 — pages no header field marks but the census
      # read: each reason is the evidence.
      EDITIONS_INDEX = "the work's editions index (lists its редакции/translations, no text)"
      EXCLUDED_TITLES = {
        "Летописи" => "category index page — a list of chronicle editions under a modern " \
                      "encyclopedic blurb, no text",
        "Молитва Владимира Мономаха" => EDITIONS_INDEX,
        "Поучение Владимира Мономаха" => EDITIONS_INDEX,
        "Слово о полку Игореве" => EDITIONS_INDEX,
        "Слово о полку Игореве/Ироическая песнь" => "the 1800 edition's table of contents (Оглавленіе)",
        "Песнь о полку Игореве (Максимович)/ДО" => "M. Maksimovich's 1836 lecture ABOUT the Слово " \
                                                   "(ЖМНП vol. 10) — 19th-c. scholarship, not the text",
        "Песнь об ополчении Игоря, сына Святослава, внука Олегова (Деларю)" =>
          "M. Delarue's 1839 verse translation into modern Russian — the page names no translator field",
        "Поучение Владимира Мономаха/Поучение детям 1893 (ДО)" =>
          "the 1893 book's modern-Russian rendering (its own navigation: «въ переложеніи на соврем. яз.»)",
        "Послание к Олегу Святославичу/Поучение детям 1893 (ДО)" =>
          "the 1893 book's translation sequence (the sibling «Письмо к Олегу» names translator " \
          "В. А. Воскресенский)",
        "Молитвенное обращение (Мономах)/Поучение детям 1893 (ДО)" =>
          "the 1893 book's translation sequence (pp. 39–40, after the Послание)",
        "Житие Константина (Кирилла) Философа" =>
          "a modern-Russian translation of the Vita («Щедрый и милостивый Бог, желая…»), no translator field",
        "Словеса дней, и царей, и святителей московских (Хворостинин)" =>
          "a modern-Russian rendering («Рассказ о временах, и царях…»), no translator field",
        "Слово о многопогибельном и коварном пьянстве (Подольский)" =>
          "a modern-Russian rendering sourced from a 20th–21st-c. monograph («Православное монашество Подолии»)"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ru-wikisource",
        name: "Russian Wikisource — the Old East Slavic cone (edition-filtered)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (ru.wikisource.org footer verbatim, verified 2026-10-10) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://ru.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Russian Wikisource (ru.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      # ДАТАСОЗДАНИЯ → the composition-era band (grade 2, precision era):
      # explicit years span min..max; a century ("XIII век", "12 век")
      # bands its hundred years. Nothing stated → no band.
      def composition_band(wikitext)
        raw = header_field(wikitext, "ДАТАСОЗДАНИЯ")
        raw = display_text(raw) if raw
        return nil if raw.nil? || raw.empty?

        years = raw.scan(YEAR).flatten.map { |year| Integer(year, 10) }
        unless years.empty?
          return { "not_before" => years.min, "not_after" => years.max, "raw" => Nabu::Normalize.nfc(raw) }
        end

        century = century_of(raw) or return nil
        { "not_before" => ((century - 1) * 100) + 1, "not_after" => century * 100,
          "raw" => Nabu::Normalize.nfc(raw) }
      end

      ROMAN = { "I" => 1, "V" => 5, "X" => 10, "L" => 50 }.freeze

      private

      def century_of(raw)
        if (match = raw.match(/\b([IVXL]+)\s*(?:век|в\.)/))
          roman_value(match[1])
        elsif (match = raw.match(/(?<!\d)(\d{1,2})\s*(?:век|в\.)/))
          Integer(match[1], 10)
        end
      end

      def roman_value(numeral)
        values = numeral.chars.map { |char| ROMAN.fetch(char) }
        values.each_with_index.sum { |value, index| values[index + 1].to_i > value ? -value : value }
      end

      def extra_metadata(envelope)
        { "era_band" => composition_band(envelope.fetch("wikitext")) }.compact
      end
    end
  end
end
