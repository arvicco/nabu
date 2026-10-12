# frozen_string_literal: true

require_relative "slavic_wikisource_html"

module Nabu
  module Adapters
    # cs-wikisource (P116-3, under the owner-ruled Wikisource posture): the premodern Czech shelf of
    # the Czech Wikisource (Wikizdroje). The wiki has NO epoch category
    # tree (censused 2026-10-10: no century/period categories exist), so
    # the cone is CENSUSED WORKS, prefix-expanded — the zh-wikisource
    # shape:
    #
    # - Rýmovaná kronika česká tak řečeného Dalimila — the Dalimil chronicle
    #   (early 14th c.), Jireček's edition (Praha: Matice česká, 1877):
    #   the root + 112 subpages (the chronicle's own Předmluva, the
    #   chapters, and the editor's Úvod, which skips as apparatus).
    # - Bible kralická (1613) — the Kralice Bible in the 1613 print's own
    #   Brethren orthography (9 books + Předmluva hosted).
    # - Bible kralická (1918) — the complete Kralice text (66 books) in the
    #   1918 New York reprint's modernized orthography (no deuterocanon);
    #   the "(1613, moderní pravopis)" tree supplies the deuterocanonical
    #   books from the 1613 print in modern spelling (Maccabees I–II also
    #   held in the 1613 orthography — two spellings, both declared).
    # - Labyrint světa a ráj srdce — Komenský, the 1663 text.
    # - Harant z Polžic, Cesta z Království Českého… (1608; Praha 1854–55).
    # - Hospodine, pomiluj ny! — keys to the 1959 Český kancionál and is
    #   EXCLUDED by EDITION_TAINT_POST_1930 (the family rule, applied here
    #   as on ru).
    #
    # The Textinfo ZDROJ/VYDÁNO statement rides verbatim (base_edition)
    # and, as "source_date", feeds the edition-year date lane
    # (MetadataDates :edition_year_text — date_class "edition", never a
    # composition claim). Language ces — declared coarse: Old Czech
    # (Dalimil) through Early Modern Czech (Komenský); the stage claims
    # need a cs anchor + stages that nabu-lects does not yet carry.
    class CsWikisource < SlavicWikisourceHtml
      API_URL = "https://cs.wikisource.org/w/api.php"
      STATE_FILE = ".cs-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:cs-wikisource:"
      LANGUAGE = "ces"

      CONE = {
        categories: {},
        prefixes: [
          "Rýmovaná kronika česká tak řečeného Dalimila",
          "Bible kralická (1613)",
          "Bible kralická (1613, moderní pravopis)",
          "Bible kralická (1918)",
          "Labyrint světa a ráj srdce",
          "Cesta z Království Českého do Benátek, odtud do země Svaté, země Judské a dále do " \
          "Egypta, a potom na horu Oreb, Sinai a Sv. Kateřiny v Pusté Arábii"
        ],
        titles: ["Bible kralická", "Hospodine, pomiluj ny!"]
      }.freeze

      VERSIONS_TEMPLATE = /\{\{\s*Rozcestník\s*[|}]/i
      # Registrum: Harant's alphabetical register — an index, not prose.
      APPARATUS_SEGMENT = /\A(Úvod|Poznámky|Rejstřík|Obsah|Registrum.*)\z/
      EDITION_FIELDS = %w[ZDROJ VYDÁNO].freeze
      EXCLUDED_TITLES = {
        "Bible kralická (1918)" => "the edition root: the title leaf plus a section transclusion " \
                                   "({{#lst:}}) of the moderní-pravopis deuterocanon, which is held " \
                                   "as its own pages — a duplicate"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "cs-wikisource",
        name: "Czech Wikisource — censused premodern works (Dalimil · Bible kralická · Komenský · Harant)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (cs.wikisource.org footer verbatim, verified 2026-10-10) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://cs.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Czech Wikisource (cs.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      private

      def extra_metadata(envelope)
        wikitext = envelope.fetch("wikitext")
        statement = %w[VYDÁNO ZDROJ].filter_map do |field|
          value = header_field(wikitext, field)
          value = display_text(value) if value
          value unless value.nil? || value.empty?
        end.join(" · ")
        statement.empty? ? {} : { "source_date" => Nabu::Normalize.nfc(statement) }
      end
    end
  end
end
