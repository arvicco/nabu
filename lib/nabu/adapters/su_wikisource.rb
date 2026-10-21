# frozen_string_literal: true

require_relative "dated_index_wikisource"

module Nabu
  module Adapters
    # su-wikisource (P140, under the owner-ruled Wikisource posture — the
    # dated 19th-century cone on the Macedonian precedent): every page of
    # the Sundanese Wikisource transcluding a scan Index whose stated print
    # year is at most 1900, plus one censused later print (the Carita
    # Parahyangan, an Old Sundanese text).
    #
    # == The census (2026-10-21) — 171 Indexes
    #
    #   band                    Indexes  pages   in the cone
    #   1800–1900                  20      78    yes — the mechanical band
    #   1901–1930                  38      65    1 EXTRA_INDEXES only (the
    #                                            Poesaka Soenda 1922–24
    #                                            issues, the Volksalmanak and
    #                                            Dewi Sartika's 1912 book are
    #                                            20th-century)
    #   > 1930                     18      60    no (EDITION_TAINT_POST_1930)
    #   unstated                    6       6    no (edition_unstated)
    #
    # Census fetch: 79 cone pages → 78 documents / 8,351 passages (sun 56 ·
    # sun-Java 21 · osn 1), 1 Dutch introduction measured out.
    #
    # The 1800–1900 band is Muhamad Musa's wawacan and dongeng (1858–1888),
    # Lasminingrat's Warnasari (1876), the Kitab Dongeng-Dongeng nu Araneh
    # (1866), Meijer's Badui pantun (1891), the Soendanesche bloemlezing
    # (1891, 18 chapters) and the TBG/Bijdragen texts. Their Dutch
    # introductions and articles (Badoejsche Pantoenverhalen/Inleiding)
    # skip by MEASURE (foreign_language); a Sundanese text inside a Dutch
    # journal stays (its Dutch share is ~4%).
    #
    # Language sun, the script MEASURED per page (the Cacarakan subpages are
    # Sundanese in Javanese script → sun-Java; Sundanese script → sun-Sund;
    # Latin → bare sun). The 1926 TBG edition of the Carita Parahyangan
    # (late 16th c., Old Sundanese) is pinned to osn (INDEX_LECTS).
    class SuWikisource < DatedIndexWikisource
      API_URL = "https://su.wikisource.org/w/api.php"
      STATE_FILE = ".su-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:su-wikisource:"
      INDEX_NS = "Indéks"
      INDEX_NS_ID = 252
      PAGE_NS = 250
      LAST_PRINT_YEAR = 1900

      PARAHYANGAN = "Tijdschrift voor Indische Taal- Land- en Volkenkunde, LXVI.pdf"
      EXTRA_INDEXES = {
        PARAHYANGAN => "the Carita Parahyangan (Old Sundanese, late 16th c.) in TBG LXVI (1926) — " \
                       "the volume's only transcluded text"
      }.freeze
      INDEX_LECTS = { PARAHYANGAN => "osn" }.freeze

      INDEX_FIELDS = {
        "title" => "Title", "author" => "Author", "translator" => "Translator", "editor" => "Editor",
        "publisher" => "Publisher", "place" => "Address", "year" => "Year", "source" => "Source",
        "progress" => "Progress", "language" => "Language", "remarks" => "Remarks"
      }.freeze
      HEADER_FIELDS = { "author" => "author", "translator" => "translator", "year" => "year",
                        "section" => "section", "notes" => "notes" }.freeze
      # The Index Language= values the cone carries (census 2026-10-21).
      LANGUAGES = { nil => "sun", "su" => "sun", "nl,su" => "sun", "nl,su,jv" => "sun" }.freeze
      SCRIPTS = { "Java" => /\p{Javanese}/, "Sund" => /\p{Sundanese}/, "Latn" => /\p{Latin}/ }.freeze
      FOREIGN_MARKERS = DUTCH_MARKERS

      MANIFEST = Nabu::SourceManifest.new(
        id: "su-wikisource",
        name: "Sundanese Wikisource — the dated 19th-century cone (prints to 1900 · the Carita Parahyangan)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (su.wikisource.org rightsinfo verbatim, verified 2026-10-21) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://su.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Sundanese Wikisource (su.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST
    end
  end
end
