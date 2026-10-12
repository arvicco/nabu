# frozen_string_literal: true

require_relative "slavic_wikisource_html"
require_relative "pl_wikisource_bruckner_lane"

module Nabu
  module Adapters
    # pl-wikisource (P116-3, under the owner-ruled Wikisource posture): the Polish Wikisource's
    # premodern Polish-literature cone — the four Polish-literature
    # categories under the epoch tree (Średniowiecze/Renesans/Barok hold
    # mostly 19th–20th-c. TRANSLATIONS of foreign classics, so the cone is
    # their Polish-literature children, censused 2026-10-10) walked to
    # depth 2, plus the two Old Polish sermon collections: 1,295 cone
    # pages at census. ~1,170 of them are ProofreadPage transclusions of
    # 19th–20th-c. scholarly editions (Biblioteka Pisarzów Polskich,
    # Lewental, Akademia Umiejętności) — the rendering resolves them.
    #
    # Rules on top of the family set: whole-work "całość" aggregates skip
    # (their parts are held), the editors' apparatus subpages (Wstęp,
    # Słowniczek, Objaśnienia, Indeks, Omyłki pierwodruku…) skip, and
    # EDITION_TAINT_POST_1930 excludes the 1932 Apologeticus edition (7
    # text pages; its całość/Wstęp/Słowniczek/Omyłki skip as aggregate/
    # apparatus first) — the family rule applied uniformly. Census:
    # 1,230 admitted, 25 aggregates, 33 apparatus, 7 tainted. The Dane tekstu
    # imprint fields (wydawca/miejsce/rok wydania/druk/redaktor) or the
    # Nagłówek adnotacje ride verbatim as base_edition.
    #
    # The cone category a page sits under bands the grade-2 era envelope
    # (ERA_CATEGORIES — conventional Polish literary-period bands; a page
    # under two periods spans both). Language pol — declared coarse (Old
    # Polish to the 1500s, Middle Polish to 1772): the stage claims need a
    # pl anchor + stages that nabu-lects does not yet carry.
    #
    # The second shelf: Brückner's Słownik etymologiczny języka polskiego
    # (Kraków 1927) rides the declared dictionary lane
    # (PlWikisourceBrucknerLane) from its proofread scan pages.
    class PlWikisource < SlavicWikisourceHtml
      API_URL = "https://pl.wikisource.org/w/api.php"
      STATE_FILE = ".pl-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:pl-wikisource:"
      LANGUAGE = "pol"
      BRUCKNER_DIRNAME = "bruckner"

      # Conventional Polish literary-period bands (approximate, declared):
      # the medieval written record from the 12th c.; Renaissance to the
      # 1620s; the Baroque to the Enlightenment's 1764 onset.
      ERA_CATEGORIES = {
        "Kategoria:Średniowieczna pieśń religijna polska" => [1100, 1500],
        "Kategoria:Polska poezja świecka XV wieku" => [1401, 1500],
        "Kategoria:Kazania świętokrzyskie" => [1100, 1500],
        "Kategoria:Kazania gnieźnieńskie" => [1100, 1500],
        "Kategoria:Literatura polskiego renesansu" => [1500, 1620],
        "Kategoria:Literatura polskiego baroku" => [1620, 1764]
      }.freeze

      CONE = {
        categories: {
          "Kategoria:Średniowieczna pieśń religijna polska" => 2,
          "Kategoria:Polska poezja świecka XV wieku" => 2,
          "Kategoria:Kazania świętokrzyskie" => 0,
          "Kategoria:Kazania gnieźnieńskie" => 0,
          "Kategoria:Literatura polskiego renesansu" => 2,
          "Kategoria:Literatura polskiego baroku" => 2
        },
        prefixes: [],
        titles: []
      }.freeze

      VERSIONS_TEMPLATE = /\{\{\s*(disambig|ujednoznacznienie|wersje)\s*[|}]/i
      AGGREGATE_SEGMENT = /całość/i
      APPARATUS_SEGMENT = /\A(Wstęp|Słowniczek.*|Objaśnienia.*|Przypisy wydawcy|Dodatek krytyczny|Indeks|
                            Spis .*|Omyłki .*|Uwagi wstępne|Zakończenie|Treść|Bibliografia.*|
                            Do Czytelnika od Wydawcy)\z/xi
      EDITION_FIELDS = ["wydawca", "miejsce wydania", "rok wydania", "druk", "redaktor", "adnotacje"].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "pl-wikisource",
        name: "Polish Wikisource — the premodern Polish-literature cone (+ Brückner's etymological dictionary)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (pl.wikisource.org footer verbatim, verified 2026-10-10) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://pl.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Polish Wikisource (pl.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      # Brückner's dictionary: the declared secondary dictionary lane.
      def self.dictionary_lane = PlWikisourceBrucknerLane.new

      def era_band(cone)
        categories = Array(cone).select { |entry| ERA_CATEGORIES.key?(entry) }.uniq
        return nil if categories.empty?

        bands = categories.map { |category| ERA_CATEGORIES.fetch(category) }
        { "not_before" => bands.map(&:first).min, "not_after" => bands.map(&:last).max,
          "raw" => categories.map { |category| category.delete_prefix("Kategoria:") }.join(" · ") }
      end

      private

      # The walk records the ROOT category each page was reached from, so
      # the band follows the period the page was filed under.
      def extra_metadata(envelope)
        { "era_band" => era_band(envelope["cone"]) }.compact
      end

      def fetch_extra!(workdir, pins, progress)
        PlWikisourceBrucknerLane.fetch!(workdir, pins: pins, progress: progress,
                                                 batches: method(:title_batches),
                                                 revisions: method(:revisions_payload),
                                                 prefix_titles: method(:prefix_titles))
      end

      def corpus_path?(rel) = rel.start_with?("#{BRUCKNER_DIRNAME}/")

      # Templates whose arguments are links/furniture, never edition text.
      def display_text(value)
        super(value.gsub(/\{\{\s*(wikipedia|wikisłownik|commons|epub|całość)[^{}]*\}\}/i, ""))
      end

      def prefix_titles(prefix, namespace: 0)
        titles = []
        continue = {}
        loop do
          payload = get_json("action" => "query", "format" => "json", "list" => "allpages",
                             "apprefix" => prefix, "apnamespace" => namespace.to_s, "aplimit" => "500",
                             "apfilterredir" => "nonredirects", **continue)
          titles.concat((payload.dig("query", "allpages") || []).map { |page| page.fetch("title") })
          token = payload.dig("continue", "apcontinue") or break

          continue = { "apcontinue" => token }
        end
        titles
      end
    end
  end
end
