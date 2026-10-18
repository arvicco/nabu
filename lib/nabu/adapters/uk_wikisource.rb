# frozen_string_literal: true

require_relative "slavic_wikisource_html"

module Nabu
  module Adapters
    # uk-wikisource (P116-3, under the owner-ruled Wikisource posture): the chronicle shelf of the
    # Ukrainian Wikisource — the 13 ns-0 members of Категорія:Літописи
    # (census 2026-10-10), with the four {{версії}} shells followed one
    # level to the edition pages they list. The admitted texts are the
    # 17th–18th-c. Cossack-era chronicles in their pre-1930 editions
    # (Сборник летописей, Киев 1888; Лѣтопись Самовидца, Киев 1878;
    # Кіевская старина 1890) — the Ruthenian chronicle register. The
    # Львівський літопис / Острозький літописець pages key to Бевзо's 1971
    # edition and are excluded by EDITION_TAINT_POST_1930; the four
    # ukrlit.vn.ua pages are modern-Ukrainian retellings (censused
    # exclusions).
    #
    # Language orv — declared coarse (the orv:ruth stage — Ruthenian
    # prosta mova — is the named refinement candidate, never defaulted).
    # The section's own year (рік_секції — the chronicle's terminal year)
    # bands the era envelope.
    class UkWikisource < SlavicWikisourceHtml
      API_URL = "https://uk.wikisource.org/w/api.php"
      STATE_FILE = ".uk-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:uk-wikisource:"
      LANGUAGE = "orv"

      CONE = { categories: { "Категорія:Літописи" => 0 }, prefixes: [], titles: [] }.freeze

      VERSIONS_TEMPLATE = /\{\{\s*(версії|неоднозначність)\s*[|}]/i
      APPARATUS_SEGMENT = /\A(Вступ|Передмова|Примітки|Коментарі.*|Архівна і бібліографічна довідка.*|Словник .*)\z/
      EDITION_FIELDS = %w[рік місто редактор Джерело Дата_публікації].freeze
      TRANSLATOR_FIELDS = %w[перекладач Перекладач].freeze
      # The section's own author first (a chronicle inside a collected
      # volume), then the work's; назва names the parent volume on a секція
      # page. рік/місто already ride base_edition (EDITION_FIELDS).
      AUTHOR_FIELDS = %w[автор_секції автор Автор].freeze
      WORK_FIELD = "назва"
      WORK_REQUIRES = "секція"

      RETELLING = "a modern-Ukrainian retelling of Primary Chronicle episodes (ukrlit.vn.ua, no " \
                  "edition stated; Мова_оригіналу=українська) — not the chronicle text"
      EXCLUDED_TITLES = {
        "Про заснування Києва" => RETELLING,
        "Про княгиню Ольгу" => RETELLING,
        "Про князя Олега" => RETELLING,
        "Про хрещення Русі" => RETELLING
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "uk-wikisource",
        name: "Ukrainian Wikisource — the chronicles (Літописи, edition-filtered)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (uk.wikisource.org footer verbatim, verified 2026-10-10) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://uk.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Ukrainian Wikisource (uk.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      private

      def extra_metadata(envelope)
        raw = header_field(envelope.fetch("wikitext"), "рік_секції").to_s
        year = raw[YEAR, 1]
        return {} unless year

        { "era_band" => { "not_before" => Integer(year, 10), "not_after" => Integer(year, 10),
                          "raw" => "рік_секції: #{raw}" } }
      end
    end
  end
end
