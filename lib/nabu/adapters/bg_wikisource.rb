# frozen_string_literal: true

require_relative "slavic_wikisource"

module Nabu
  module Adapters
    # bg-wikisource (P116-2, 02-sources row 237): the Bulgarian Wikisource
    # premodern cone — small by census (2026-10-10). Three categories:
    #
    # - Средновековни български текстове (9) and Средновековни сръбски
    #   текстове (10): the medieval charters, each page carrying the
    #   ORIGINAL in {{Script/Slavonic|cu|…}} (the wiki's "Оригинал
    #   (адаптиран текст)" section — sometimes inside the facsimile's
    #   caption) beside a modern-Bulgarian rendering section. Only the
    #   original-script text is read; the rendering section is apparatus.
    #   A page with NO original-script text (Разказ за възстановяването
    #   на патриаршията, Закон за съдене на хората — Bobchev's
    #   translation) skips by rule: modern-language rendering only.
    # - История славянобългарска (10 subpages): Paisiy's 1762 history —
    #   but hosted, by the page's own note, "предаден на съвременен
    #   книжовен език" after Ivanov's 1914 edition of the Zograf copy: a
    #   MODERN-LITERARY-BULGARIAN rendering. Ingested and DECLARED
    #   (metadata "rendering" "modern literary Bulgarian"; base_edition
    #   the note verbatim), language bul — never a claim on the 1762
    #   language.
    #
    # Everything else premodern-looking on the wiki censused as modern
    # translation (Черноризец Храбър, Матей Граматик — no originals) and
    # stays out of the cone.
    #
    # == Claims
    #
    # Charters: language chu (the bare anchor), the wiki's own grouping in
    # metadata "recension" (bulgarian/serbian — a facet a lect rule can
    # map: chu/srp exists in the registry, a Bulgarian-recension node does
    # not — reported), line grain (the charter's own lines). The issuance
    # year stated in бележки ("Издадена на 21 септември 1378 г.") is a
    # typed date: metadata "date" (MetadataDates :structured). Base
    # edition (№R-74): the original section's own edition footnote
    # ("По редакция и издание на …") verbatim, else "unstated".
    class BgWikisource < SlavicWikisource
      API_URL = "https://bg.wikisource.org/w/api.php"
      STATE_FILE = ".bg-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:bg-wikisource:"
      LANGUAGE = "bul"
      CHARTER_LANGUAGE = "chu"
      HEADER_TEMPLATES = %w[Творба].freeze
      SCRIPT_TEMPLATE = "Script/Slavonic"

      RECENSIONS = {
        "Средновековни български текстове" => "bulgarian",
        "Средновековни сръбски текстове" => "serbian"
      }.freeze

      CONE = (RECENSIONS.keys.map { |name| Cone.new(category: "Категория:#{name}", depth: 0, label: name) } +
              [Cone.new(category: "Категория:История славянобългарска", depth: 0,
                        label: "История славянобългарска")]).freeze
      EXCLUSIONS = {}.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "bg-wikisource",
        name: "Bulgarian Wikisource — medieval charters + История славянобългарска",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (bg.wikisource.org footer verbatim, verified 2026-10-10) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://bg.wikisource.org/",
        parser_family: "wikisource-slavic",
        credit: "Bulgarian Wikisource (bg.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      private

      def charter?(envelope) = !recension(envelope).nil?

      def recension(envelope)
        RECENSIONS.find { |name, _| Array(envelope["cone"]).include?(name) }&.last
      end

      # The original-script lane: one passage per line of the hosted
      # original, the template block's ordinal as the stanza.
      def passages_for(envelope, result)
        return result.passages unless charter?(envelope)

        @charter_passages ||= {}
        @charter_passages[envelope.fetch("pageid")] ||=
          parser.template_texts(envelope.fetch("wikitext"), name: SCRIPT_TEMPLATE)
                .each_with_index.flat_map do |lines, block|
                  lines.map do |line|
                    WikisourceSlavicParser::Passage.new(text: line, section: nil, verse: true, stanza: block + 1)
                  end
                end
      end

      def page_skip_reason(envelope, result)
        return nil unless charter?(envelope) && passages_for(envelope, result).empty?

        "modern-language rendering only (no hosted original)"
      end

      def language_for(envelope, _result) = charter?(envelope) ? CHARTER_LANGUAGE : LANGUAGE

      def extra_metadata(envelope, result)
        notes = header_value(result.header, %w[бележки])
        if charter?(envelope)
          { "recension" => recension(envelope), "grain" => "line", "date" => issuance_date(notes) }.compact
        else
          { "rendering" => "modern literary Bulgarian" }
        end
      end

      # "Издадена на 21 септември 1378 г." / "Издадена през 1348 г." /
      # "Издадена между 1369 г. и 1380 г." — the stated years in the
      # issuance note span the envelope.
      def issuance_date(notes)
        years = notes.to_s.scan(/(\d{3,4})\s*г\./).flatten.map(&:to_i)
        return nil if years.empty?

        { "not_before" => years.min, "not_after" => years.max, "raw" => Nabu::Normalize.nfc(notes) }
      end

      def base_edition(envelope, result)
        if charter?(envelope)
          footnote = result.refs.find { |ref| ref.match?(/редакция|издание/i) }
          return footnote ? Nabu::Normalize.nfc(footnote) : "unstated"
        end

        notes = header_value(result.header, %w[бележки])
        notes ? Nabu::Normalize.nfc(notes) : "unstated"
      end
    end
  end
end
