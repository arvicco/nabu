# frozen_string_literal: true

require_relative "slavic_wikisource"

module Nabu
  module Adapters
    # sr-wikisource (P116-2, 02-sources row 233): the Serbian Wikisource
    # oral-tradition cone — census 2026-10-10 (MediaWiki API, category
    # walk):
    #
    # - Српске епске народне песме (2,505 direct; 2,923 with the Марко/
    #   Старина Новак/Бајо Пивљанин cycle subcategories, depth 2);
    # - Ерлангенски рукопис (216 — the c.-1720 Erlangen manuscript in the
    #   Detelić/Samardžija/Delić rendering after Gesemann 1925: the page's
    #   own "Интервенције" section lists the editors' orthographic
    #   normalizations, ѣ → е etc. — riding in metadata "apparatus",
    #   declared, never hidden);
    # - Збирке Вука Стефановића Караџића (the 14 per-volume categories,
    #   depth 1 — Vienna/State edition books I–IX + the SANU I–V
    #   manuscript volumes), Вук … женске из Херцеговине (373) and
    #   Вукова грађа (32).
    #
    # Union 4,930 pages / ~43 MB of wikitext at census.
    #
    # == Exclusions BY RULE (counted in discovery_skips)
    #
    # - Bulgarian-source collections (Народне песме из бугарских извора
    #   252, Шапкарев-Сборник 41, Верковић): Bulgarian/Macedonian-dialect
    #   texts the wiki files beside the Serbian songs — outside the srp
    #   cone (the Miladinov material rides mk-wikisource);
    # - Народне песме из НОБ-а (4 in the cone): 20th-century partisan
    #   compositions — modern-authored;
    # - the Vuk volume index pages (title rule) and any link-list index.
    #
    # == Claims
    #
    # Language per page by SCRIPT (censused: 136 Latin-script pages, all
    # Croatian-collected — Matica hrvatska, Istria, the Dalmatian islands,
    # Hrvati u Mađarskoj): Cyrillic pages claim srp, Latin-script pages
    # hrv; metadata "script" names the basis. Verse is line grain (one
    # passage per verse line); the edition's verse numbering ({{стих|N}},
    # the Erlangen "0001" prefixes) is apparatus. Base edition (owner ruling):
    # the page's Извор/Избор source line verbatim (the Vuk Sabrana dela
    # volume), else the header's белешке (the Erlangen edition statement),
    # else "unstated". Undated at page grain (no date field exists);
    # recording ≠ composition — the oral-tradition category also holds
    # 20th-century collections (e.g. Вукановић's WWI songs), carried
    # with their collection categories verbatim, not filtered.
    class SrWikisource < SlavicWikisource
      API_URL = "https://sr.wikisource.org/w/api.php"
      STATE_FILE = ".sr-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:sr-wikisource:"
      LANGUAGE = "srp"
      LATIN_LANGUAGE = "hrv"
      HEADER_TEMPLATES = %w[заглавље zaglavlje].freeze

      CONE = [
        Cone.new(category: "Категорија:Српске епске народне песме", depth: 2,
                 label: "Српске епске народне песме"),
        Cone.new(category: "Категорија:Ерлангенски рукопис", depth: 0, label: "Ерлангенски рукопис"),
        Cone.new(category: "Категорија:Збирке Вука Стефановића Караџића", depth: 1,
                 label: "Збирке Вука Стефановића Караџића"),
        Cone.new(category: "Категорија:Вук Стефановић Караџић: Српске народне пјесме женске из Херцеговине",
                 depth: 0, label: "Вук Стефановић Караџић: Српске народне пјесме женске из Херцеговине"),
        Cone.new(category: "Категорија:Вукова грађа", depth: 0, label: "Вукова грађа")
      ].freeze

      BULGARIAN_SOURCE = "Bulgarian-source collection (outside the Serbian cone)"
      EXCLUSIONS = {
        "Категорија:Народне песме из бугарских извора" => BULGARIAN_SOURCE,
        "Категорија:Шапкарев-Сборник от български народни умотворения" => BULGARIAN_SOURCE,
        "Категорија:Стефан Верковић: Народне песме македонски Бугара" => BULGARIAN_SOURCE,
        "Категорија:Народне песме из НОБ-а" => "20th-century partisan composition (modern-authored)"
      }.freeze

      INDEX_TITLE = /\A(?:Вук Стефановић Караџић: |Сабрана дела Вука Караџића)/

      MANIFEST = Nabu::SourceManifest.new(
        id: "sr-wikisource",
        name: "Serbian Wikisource — the oral-tradition cone (епске песме · Ерлангенски рукопис · Vuk)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (sr.wikisource.org footer verbatim, verified 2026-10-10) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://sr.wikisource.org/",
        parser_family: "wikisource-slavic",
        credit: "Serbian Wikisource (sr.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      private

      def page_skip_reason(envelope, _result)
        "Vuk volume index page (navigation, no hosted text)" if envelope.fetch("title").match?(INDEX_TITLE)
      end

      def language_for(envelope, result)
        script(envelope, result) == "Latn" ? LATIN_LANGUAGE : LANGUAGE
      end

      def extra_metadata(envelope, result)
        { "script" => script(envelope, result) }
      end

      def script(_envelope, result)
        text = result.passages.map(&:text).join
        text.match?(/\p{Cyrillic}/) || !text.match?(/\p{Latin}/) ? "Cyrl" : "Latn"
      end

      def base_edition(envelope, result)
        stated = super
        return stated unless stated == "unstated"

        notes = result.header.find { |key, _| key.strip.downcase == "белешке" }&.last
        notes ? Nabu::Normalize.nfc(notes) : stated
      end
    end
  end
end
