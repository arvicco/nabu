# frozen_string_literal: true

require_relative "dated_index_wikisource"

module Nabu
  module Adapters
    # jv-wikisource (P140, under the owner-ruled Wikisource posture — the
    # dated 19th-century cone on the Macedonian precedent): every page of
    # the Javanese Wikisource transcluding a scan Index whose stated print
    # year is at most 1900, plus three censused later prints (inside the
    # post-1930 rule) of works composed before 1900.
    #
    # == The census (2026-10-21) — 839 Indexes, most still at the OCR stage
    #
    # Only ~200 Indexes have a transcluding ns-0 page; the wiki renders a
    # whole book on ONE page (a <pages index> over the full range), so the
    # documents are books. By the stated print year:
    #
    #   band                    Indexes  pages   in the cone
    #   ≤ 1800                      0       0    (the 14 BL pre-1800
    #                                             manuscripts are OCR-only)
    #   1800–1900                  13      34    yes — the mechanical band
    #   1901–1930                  30      33    3 EXTRA_INDEXES only (the
    #                                            Kajawen 1927 issues and the
    #                                            1920s schoolbooks are
    #                                            20th-century compositions)
    #   > 1930                     72     128    no (EDITION_TAINT_POST_1930)
    #   unstated                   84     230    no (an undated edition
    #                                            cannot pass the filter)
    #
    # + Wretansacaya (Kern 1875): the Index states no year, its file name
    # does — inside the band (the name year is edition evidence). Census
    # fetch: 38 cone pages → 36 documents / 2,855 passages (jav-Java 33 ·
    # jav 2 · kaw 1), 2 Dutch pages measured out.
    #
    # The 1800–1900 band: the BL MSS Jav 24/28 manuscripts (1803, 1804),
    # Gericke's New Testament (1848, 22 pages) and Old Testament (1854),
    # Winter's Adji Såkå (1857), the Babad Dipa Nagara manuscript (D Or. 13,
    # 1866), Palmer van den Broek's Serat Kancil (1878), Gericke's
    # schoolbook (1839) and the bilingual Gericke–Roorda / de Nooy word
    # lists. Dutch-language apparatus pages (the Woordenboek front matter,
    # the Verhandelingen) skip by MEASURE (foreign_language, the Dutch
    # function-word share). Translations (the Bible) are kept: the
    # 19th-century Javanese text IS the witness, not a modern layer.
    #
    # Language jav, the script MEASURED per page (jav-Java for aksara Jawa,
    # bare jav for Latin); Wretansacaya — Mpu Tanakung's 14th-century Old
    # Javanese treatise on metres — is pinned to kaw (INDEX_LECTS).
    class JvWikisource < DatedIndexWikisource
      API_URL = "https://jv.wikisource.org/w/api.php"
      STATE_FILE = ".jv-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:jv-wikisource:"
      INDEX_NS = "Indhèks"
      INDEX_NS_ID = 252
      PAGE_NS = 250
      LAST_PRINT_YEAR = 1900

      EXTRA_INDEXES = {
        "Serat Pararaton.pdf" => "the Pararaton chronicle (15th–16th c.), Mangkudimedja's 1912 print",
        "Serat Wulangreh.pdf" => "Pakubuwana IV's Wulangreh (r. 1788–1820), the 1929 print",
        "Serat Wirit.pdf" => "Ranggawarsita's Wirit Hidayat Jati (d. 1873), the 1916 print"
      }.freeze
      INDEX_LECTS = { "Wretansacaya (Kern 1875).pdf" => "kaw" }.freeze

      INDEX_FIELDS = {
        "title" => "Title", "author" => "Author", "translator" => "Translator", "editor" => "Editor",
        "publisher" => "Publisher", "place" => "Address", "year" => "Year", "source" => "Source",
        "progress" => "Progress", "language" => "Language", "remarks" => "Remarks"
      }.freeze
      HEADER_FIELDS = { "author" => "author", "translator" => "translator", "year" => "year",
                        "section" => "section", "notes" => "notes" }.freeze
      # The Index Language= values the cone carries (census 2026-10-21).
      LANGUAGES = { nil => "jav", "jv" => "jav", "jv-java" => "jav", "jv,nl" => "jav", "nl,jv" => "jav" }.freeze
      SCRIPTS = { "Java" => /\p{Javanese}/, "Latn" => /\p{Latin}/ }.freeze
      FOREIGN_MARKERS = DUTCH_MARKERS

      MANIFEST = Nabu::SourceManifest.new(
        id: "jv-wikisource",
        name: "Javanese Wikisource — the dated 19th-century cone (manuscripts and prints to 1900)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (jv.wikisource.org rightsinfo verbatim, verified 2026-10-21) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://jv.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Javanese Wikisource (jv.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST
    end
  end
end
