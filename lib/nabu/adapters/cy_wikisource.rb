# frozen_string_literal: true

require_relative "dated_index_wikisource"

module Nabu
  module Adapters
    # cy-wikisource (P140, under the owner-ruled Wikisource posture): the
    # early-modern Welsh cone of the Welsh Wikisource (Wicidestun) — every
    # page transcluding a scan Index whose stated print year is at most
    # 1800 (the mechanical year filter: the prints themselves are the
    # Early Modern Welsh witnesses), plus eight censused later prints
    # (1897–1924, inside the post-1930 rule) of works COMPOSED before 1800.
    #
    # == The census (2026-10-21) — 641 Indexes on the wiki
    #
    #   print ≤ 1800 (the mechanical band)                 Indexes  pages
    #     Oll synnwyr pen Kembero ygyd (Salesbury, 1547)       1       13
    #     Beibl Cyssegr-Lan (William Morgan, 1588)             1        5
    #     Y bibl cyssegr-lan (the 1620 Bible)                  1       67
    #     ballads and hymn prints 1735–1800                    6       10
    #     (Aleluia 1754 and the Red Book of Hergest MS 111 — Index year
    #      1382, the manuscript — have no transcribed pages yet)
    #   EXTRA_INDEXES (later prints of pre-1800 works)         8      250
    #   cone (union, before the rules)                                 346
    #
    # Census fetch: 321 documents / 40,126 passages admitted; 25 skipped
    # by rule (8 composites, 14 apparatus, 3 empty renderings).
    #
    # The 1620 Bible is a faithful transcription of the print; the Cyfres
    # y Fil volumes (O. M. Edwards' "Thousand" series, Llanuwchllyn
    # 1901–1913) MODERNIZE the spelling — metadata "orthography" records
    # it per page ("original" for the ≤ 1800 prints, "modernized (Cyfres y
    # Fil)" for the series, "unstated" otherwise), never silent. Apparatus
    # (Rhagymadrodd introductions, Cynhwysiad/Cynnwys contents, Nodiad
    # notes, Mynegai indexes) and the "(testun cyfansawdd)" composite pages
    # (the whole book again, duplicating the held parts) skip by rule.
    #
    # Language cym (Welsh) for the whole cone, declared coarse: the
    # 1547–1800 prints are Early Modern Welsh (the cy:emod stage is the
    # named refinement); the Cyfres y Fil Dafydd ap Gwilym, the Mabinogion
    # and Brut y Tywysogion are Middle Welsh compositions in MODERNIZED
    # spelling — never claimed as Middle Welsh (wlm) text.
    class CyWikisource < DatedIndexWikisource
      API_URL = "https://cy.wikisource.org/w/api.php"
      STATE_FILE = ".cy-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:cy-wikisource:"
      INDEX_NS = "Indecs"
      INDEX_NS_ID = 106
      PAGE_NS = 104
      LAST_PRINT_YEAR = 1800

      CYFRES_Y_FIL = "a Cyfres y Fil volume (O. M. Edwards, ab Owen, Llanuwchllyn)"
      EXTRA_INDEXES = {
        "Gwaith Dafydd ap Gwilym.pdf" => "Dafydd ap Gwilym (fl. 1340–1370), 1901 — #{CYFRES_Y_FIL}",
        "Gwaith yr Hen Ficer.pdf" => "Rhys Prichard (1579–1644), Canwyll y Cymry, 1908 — #{CYFRES_Y_FIL}",
        "Beirdd y Berwyn 1700-1750.djvu" => "the Berwyn poets 1700–1750, 1902 — #{CYFRES_Y_FIL}",
        "Brut y Tywysogion Cyfres y Fil.djvu" => "the chronicle of the princes (to 1282), 1913 — #{CYFRES_Y_FIL}",
        "Mabinogion - (o Lyfr coch Hergest) (IA mabinogionolyfrc00edwa).pdf" =>
          "the Mabinogion from the Red Book of Hergest (J. M. Edwards, vol. II, Wrexham 1901)",
        "Mabinogion J M Edwards Cyf 1.pdf" =>
          "the Mabinogion from the Red Book of Hergest (J. M. Edwards, vol. I, Wrexham 1921)",
        "Barddoniaeth Goronwy Owen (gol Llyfrbryf).djvu" => "Goronwy Owen (1723–1769), Liverpool 1924",
        "Clasuron Rhyddiaith Cymru.djvu" => "classics of Welsh prose (16th–18th c.), Bangor 1897"
      }.freeze
      # The Index pages carrying [[Categori:Cyfres y Fil]] (census 2026-10-21).
      MODERNIZED_INDEXES = ["Gwaith Dafydd ap Gwilym.pdf", "Gwaith yr Hen Ficer.pdf",
                            "Beirdd y Berwyn 1700-1750.djvu", "Brut y Tywysogion Cyfres y Fil.djvu"].freeze

      APPARATUS_SEGMENT = /\A(Rhagymadrodd|(Y )?Cynhwysiad|Cynnwys|Cynnwysiad|Nodiad|Nodiadau|Mynegai|Rhagair)\z/
      COMPOSITE_TITLE = /\([^()]*testun cyfansawdd\)/

      INDEX_FIELDS = {
        "title" => "Title", "author" => "Author", "publisher" => "Publisher", "year" => "Year",
        "source" => "Source", "progress" => "Progress", "remarks" => "Remarks"
      }.freeze
      HEADER_FIELDS = { "author" => "author", "section" => "section", "year" => "year", "notes" => "notes" }.freeze
      LANGUAGES = { nil => "cym" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "cy-wikisource",
        name: "Welsh Wikisource — the early-modern cone (Salesbury 1547 · the 1588 and 1620 Bibles · " \
              "pre-1800 prints · Cyfres y Fil)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (cy.wikisource.org rightsinfo verbatim, verified 2026-10-21) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://cy.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Welsh Wikisource (cy.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      def wikitext_class(title, wikitext)
        return :aggregate if title.split("/").first.match?(COMPOSITE_TITLE)

        super
      end

      private

      def cone_metadata(envelope)
        { "orthography" => orthography(envelope) }
      end

      def orthography(envelope)
        names = Array(envelope["indexes"]).map { |index| index["name"] }
        return "modernized (Cyfres y Fil)" if names.intersect?(MODERNIZED_INDEXES)

        years = envelope_edition_years(envelope)
        years.any? && years.max <= LAST_PRINT_YEAR ? "original" : "unstated"
      end
    end
  end
end
