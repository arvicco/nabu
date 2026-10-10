# frozen_string_literal: true

require_relative "slavic_wikisource"

module Nabu
  module Adapters
    # mk-wikisource (P116-2, 02-sources row 236): the Macedonian Wikisource
    # 19th-century cone — census 2026-10-10. The wiki has no period
    # categories, so the cone is NAMED collections and authors:
    #
    #   Зборник на Миладиновци 687 (the Miladinov brothers' 1861 folk-song
    #   collection) · Зборник на Шапкарев 18 · Народни приказни собрани од
    #   Марко Цепенков 79 · the pre-1900 author categories (depth 1):
    #   Кирил Пејчиновиќ, Јоаким Крчовски, Ѓорѓија Пулевски (+ Слогница
    #   речовска), Димитар и Константин Миладинов, Рајко Жинзифов, Кузман
    #   Шапкарев, Марко Цепенков · Слово заради страшниот суд
    #
    # — ≈790 pages. OUT by rule: the broad Македонски народни песни
    # category (733 — mixes 20th-century field recordings, partisan songs
    # (Од борбата, Македонски партизански песни) and modern reworkings
    # (Песни преработени од Леб и сол) with no page-level provenance to
    # separate them); Григор Прличев (his works were composed in Greek —
    # the hosted Macedonian is an unstated translation); the "(современ
    # правопис)" modern-orthography DUPLICATES of pages held in original
    # orthography (Слогница речовска); author pages.
    #
    # == The orthography declaration (never silent)
    #
    # The wiki states per page, in the header's забелешки, which orthography
    # the transcription uses: "на современ македонски правопис" (the
    # Miladinov collection, Pejčinović, Cepenkov — MODERNIZED into the
    # 1945 standard) or "на стар македонски правопис" (Pulevski — the
    # original). Metadata "orthography" records it ("modernized" /
    # "original" / "unstated"), the note itself rides verbatim in "notes".
    # A забелешки that states the print year ("Издадена е во 1817 год.")
    # mints a typed date (metadata "date", MetadataDates :structured).
    # Language mkd for the whole cone (bare; the registry has no mk node —
    # reported). Pejčinović (1816) and Krčovski (1814–17) write the
    # Church-Slavonic-tinged vernacular the damaskini lane stages under
    # bul — the census names them; no stage is claimed here.
    class MkWikisource < SlavicWikisource
      API_URL = "https://mk.wikisource.org/w/api.php"
      STATE_FILE = ".mk-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:mk-wikisource:"
      LANGUAGE = "mkd"
      HEADER_TEMPLATES = %w[Заглавје].freeze

      COLLECTIONS = ["Зборник на Миладиновци", "Зборник на Шапкарев",
                     "Народни приказни собрани од Марко Цепенков", "Слово заради страшниот суд"].freeze
      AUTHORS = ["Кирил Пејчиновиќ", "Јоаким Крчовски", "Ѓорѓија Пулевски", "Димитар Миладинов",
                 "Константин Миладинов", "Рајко Жинзифов", "Кузман Шапкарев", "Марко Цепенков"].freeze

      CONE = (COLLECTIONS.map { |name| Cone.new(category: "Категорија:#{name}", depth: 0, label: name) } +
              AUTHORS.map { |name| Cone.new(category: "Категорија:#{name}", depth: 1, label: name) }).freeze

      MODERN = "20th-century composition or reworking (modern-authored)"
      EXCLUSIONS = {
        "Категорија:Македонски партизански песни" => MODERN,
        "Категорија:Од борбата" => MODERN,
        "Категорија:Песни преработени од Леб и сол" => MODERN,
        "Категорија:Григор Прличев" => "composed in Greek (the hosted Macedonian is a translation)"
      }.freeze

      MODERN_DUPLICATE = /\(современ правопис\)/

      MANIFEST = Nabu::SourceManifest.new(
        id: "mk-wikisource",
        name: "Macedonian Wikisource — the 19th-century cone (Миладиновци · Шапкарев · Цепенков · " \
              "Пејчиновиќ · Крчовски · Пулевски)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (mk.wikisource.org footer verbatim, verified 2026-10-10) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://mk.wikisource.org/",
        parser_family: "wikisource-slavic",
        credit: "Macedonian Wikisource (mk.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      private

      def page_skip_reason(envelope, _result)
        return nil unless envelope.fetch("title").match?(MODERN_DUPLICATE)

        "modern-orthography duplicate of a page held in original orthography"
      end

      def extra_metadata(_envelope, result)
        note = header_value(result.header, %w[забелешки])
        { "orthography" => orthography(note), "date" => print_date(note) }.compact
      end

      # The aggressive-mining duty: a забелешки that states the print year
      # ("Издадена е во 1817 год." — Krčovski) is a typed date, a one-year
      # envelope; anything vaguer mints nothing.
      def print_date(note)
        year = note.to_s[/[Ии]здаден\p{L}*\s+(?:е\s+)?во\s+(\d{4})\s*год/, 1] or return nil

        { "not_before" => year.to_i, "not_after" => year.to_i, "raw" => Nabu::Normalize.nfc(note) }
      end

      def orthography(note)
        case note.to_s
        when /современ\p{L}*\s+(?:македонски\s+)?правопис/i then "modernized"
        when /стар\p{L}*\s+(?:македонски\s+)?правопис/i then "original"
        else "unstated"
        end
      end
    end
  end
end
