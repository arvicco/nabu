# frozen_string_literal: true

require_relative "indexed_wikisource"

module Nabu
  module Adapters
    # th-wikisource (P120-3, under the owner-ruled Wikisource posture): the
    # Thai chronicle cone of the Thai Wikisource — the ประชุมพงศาวดาร
    # (Prachum Phongsawadan, the Collected Chronicles the Vajirañāṇa
    # Library / Royal Institute printed in parts from 1914) work tree, plus
    # the two hosted Three Seals Law (กฎหมายตราสามดวง) trees.
    #
    # == The Buddhist-Era calendar (the year filter)
    #
    # Every year the wiki states — the Index ปี= field, the page header
    # year=, the Thai-digit years in Index names (๒๔๖๑) and the "(2475)"
    # title marks — is a BUDDHIST-ERA year. #years_in reads Thai and Arabic
    # digits and converts BE → CE by −543 (the conventional offset; the
    # pre-1941 April new year is not modelled), so EDITION_TAINT_POST_1930
    # excludes every part printed after BE 2473 (1930 CE).
    #
    # == The census verdict (2026-10-12)
    #
    # The parts reprinted from BE 2474 on (the 1932–1966 funeral-book
    # reprints and the late parts 60–81) are the written exclusion; the
    # BE 2457–2473 first prints pass. BOTH Three Seals Law editions the
    # wiki hosts are post-1930 — Lingat's 1939 (BE 2482) Thammasat edition
    # (ประมวลกฎหมายรัชกาลที่ 1 จุลศักราช 1166) and the 1962 (BE 2505)
    # Khurusapha edition (กฎหมายตราสามดวง) — so the filter excludes the
    # whole law code: zero clean pages, censused. REQUIRE_EDITION_YEAR: a
    # page with no stated year (the series root) skips by rule.
    #
    # Apparatus (the funeral-print furniture, not the chronicles): คำนำ /
    # คำอธิบาย (the editor's preface and explanation), ผู้วายชนม์ (the
    # biography of the deceased the print commemorates), สารบาญ/สารบัญ
    # (contents) — and อธิบายประกอบ, the WIKI's own annotation pages (no
    # scan behind them; modern editors' glosses — never the text).
    # ภาคผนวก (a print's appendix of source documents) stays text.
    #
    # The publisher (ผู้เผยแพร่=) rides verbatim in index_editions and
    # base_edition; the print year feeds the edition-year date lane
    # (source_date → MetadataDates :edition_year_text, the CE year beside
    # the verbatim BE value; date_class edition, never composition).
    # Language tha (Thai script); an Index declaring any other language
    # quarantines the page.
    class ThWikisource < IndexedWikisource
      API_URL = "https://th.wikisource.org/w/api.php"
      STATE_FILE = ".th-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:th-wikisource:"
      INDEX_NS = "ดัชนี"
      PAGE_NS = 250

      CONE = {
        categories: {},
        prefixes: ["ประชุมพงศาวดาร", "กฎหมายตราสามดวง", "ประมวลกฎหมายรัชกาลที่ 1 จุลศักราช 1166"],
        titles: [],
        indexes: []
      }.freeze

      APPARATUS_SEGMENT = /\A(คำนำ|คำอธิบาย|ผู้วายชนม์|สารบาญ|สารบัญ|อธิบายประกอบ)\z/
      EDITION_FIELDS = %w[year].freeze
      INDEX_FIELDS = {
        "title" => "ชื่อ", "author" => "ผู้สร้างสรรค์", "editor" => "บรรณาธิการ", "publisher" => "ผู้เผยแพร่",
        "place" => "สถานที่", "year" => "ปี", "source" => "ที่มา", "progress" => "ความคืบหน้า",
        "language" => "ภาษา", "notes" => "หมายเหตุ"
      }.freeze
      HEADER_FIELDS = { "author" => "author", "editor" => "editor", "year" => "year", "section" => "section",
                        "notes" => "notes" }.freeze
      REQUIRE_EDITION_YEAR = true
      LANGUAGES = { "th" => "tha", nil => "tha" }.freeze
      BE_OFFSET = 543
      THAI_DIGITS = "๐๑๒๓๔๕๖๗๘๙"

      MANIFEST = Nabu::SourceManifest.new(
        id: "th-wikisource",
        name: "Thai Wikisource — ประชุมพงศาวดาร (the Collected Chronicles, parts printed to BE 2473)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (th.wikisource.org footer verbatim, verified 2026-10-12) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://th.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Thai Wikisource (th.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      # BE → CE: Thai digits read, every 4-digit year in the Buddhist-Era
      # band (2300–2600) shifted by −543; a year already in the CE band
      # (1000–2099 — e.g. the จุลศักราช 1166 title mark, harmless) as stated.
      def years_in(text)
        text.to_s.tr(THAI_DIGITS, "0123456789").scan(/(?<!\d)(\d{4})(?!\d)/).flatten.filter_map do |digits|
          year = Integer(digits, 10)
          if year.between?(2300, 2600) then year - BE_OFFSET
          elsif year.between?(1000, 2099) then year
          end
        end
      end

      private

      def language_for(envelope)
        declared = Array(envelope["indexes"]).map { |index| index_role(index, "language")&.downcase }.uniq
        codes = declared.map do |language|
          LANGUAGES.fetch(language) do
            raise ParseError, "#{envelope['title']}: Index language #{language.inspect} is not censused " \
                              "(LANGUAGES) — quarantined, never guessed"
          end
        end
        codes.first || LANGUAGES.fetch(nil)
      end

      def extra_metadata(envelope)
        years = Array(envelope["indexes"]).filter_map do |index|
          stated = index_role(index, "year") or next
          converted = years_in(stated)
          next if converted.empty?

          "#{converted.join(', ')} (#{INDEX_FIELDS['year']} #{stated} พ.ศ., #{index['name']})"
        end
        years.empty? ? {} : { "source_date" => Nabu::Normalize.nfc(years.uniq.join(" · ")) }
      end
    end
  end
end
