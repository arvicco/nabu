# frozen_string_literal: true

require_relative "dated_index_wikisource"

module Nabu
  module Adapters
    # br-wikisource (P140, under the owner-ruled Wikisource posture — the
    # dated 19th-century cone on the Macedonian precedent): every page of
    # the Breton Wikisource (Wikimammenn) transcluding a scan Index whose
    # stated print year is at most 1900.
    #
    # == The census (2026-10-21) — 613 Indexes
    #
    #   band                    Indexes  pages    in the cone
    #   ≤ 1800                      4     125     yes (Collocou familier
    #                                             1779, Sales' Introduction
    #                                             1779–92, two 1790s prints)
    #   1800–1900                 144   3,177     yes — the mechanical band
    #   1901–1930                 276   2,293     no (after_cone: Ar Vro /
    #                                             Feiz ha Breiz serial
    #                                             fiction, the 1900s poets —
    #                                             20th-century compositions)
    #   > 1930                     63     819     no (EDITION_TAINT_POST_1930)
    #   unstated                    9      49     no (edition_unstated)
    #
    # The band's heart: Marigo's Buez ar Saent (1837, 179 pages — the
    # lives of the saints), the Vannetais Guerzenneu (1857, 173), the
    # Heuriou (1849, 167), Luzel's Gwerziou (1868/1874) and Soniou
    # Breiz-Izel (1890, 238), the Barzaz Breiz editions (1846/1867/1883),
    # Le Gonidec's Bible (1866), the Canticou spirituel, catechisms and
    # missions hymnals (1815–1836). The Barzaz Breiz songs are held once
    # per edition (1846 / 1867 / 1883 — the orthography moves between
    # them); the "/a-bezh" whole-book pages skip as aggregates. Its
    # French-language pages (the
    # Quellien / Bourgault-Ducoudray song-book roots) skip by MEASURE
    # (foreign_language, the French function-word share). Translations of
    # devotional works are kept: the 19th-century Breton text IS the
    # witness.
    #
    # Language bre (Breton; the 639-3 code aliases onto the br anchor).
    # Every page is post-1650 Modern Breton — bare br, the Middle Breton
    # node (xbm) never claimed. The wiki's Index carries no Language field.
    class BrWikisource < DatedIndexWikisource
      API_URL = "https://br.wikisource.org/w/api.php"
      STATE_FILE = ".br-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:br-wikisource:"
      INDEX_NS = "Meneger"
      INDEX_NS_ID = 100
      PAGE_NS = 102
      LAST_PRINT_YEAR = 1900

      INDEX_FIELDS = {
        "title" => "Title", "author" => "Author", "translator" => "Translator", "editor" => "Editor",
        "publisher" => "Publisher", "place" => "Address", "year" => "Year", "source" => "Source",
        "progress" => "Progress", "remarks" => "Remarks"
      }.freeze
      HEADER_FIELDS = { "author" => "author", "translator" => "translator", "year" => "year",
                        "section" => "section", "notes" => "notes" }.freeze
      # "a-bezh" ("the whole"): the whole book again on one page, duplicating
      # the held song/chapter pages (62 in the cone, census 2026-10-21).
      AGGREGATE_SEGMENT = /\Aa-bezh\z/
      LANGUAGES = { nil => "bre" }.freeze
      FOREIGN_MARKERS = FRENCH_MARKERS

      MANIFEST = Nabu::SourceManifest.new(
        id: "br-wikisource",
        name: "Breton Wikisource — the dated 19th-century cone (prints to 1900: Buez ar Saent · " \
              "Luzel · Barzaz Breiz)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (br.wikisource.org rightsinfo verbatim, verified 2026-10-21) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://br.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Breton Wikisource (br.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST
    end
  end
end
