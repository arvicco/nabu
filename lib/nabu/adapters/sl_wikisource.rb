# frozen_string_literal: true

require_relative "slavic_wikisource"

module Nabu
  module Adapters
    # sl-wikisource (P116-2, 02-sources row 235): Wikivir — the Slovene
    # Wikisource — through its YEAR categories. Census 2026-10-10: Wikivir
    # files every dated work under "Dela leta N"; the cone is every
    # "Dela leta N" with N ≤ 1899 (86 year categories at census: 1184 …
    # 1584 (the 46 Dalmatin/Trubar pages) … the 1848–51 press peak … 1899)
    # — union 1,673 pages, 1,545 after the exclusions, ~36 MB of
    # wikitext. Wikivir's 19th-century layer is the Hladnik project's
    # human-corrected transcription over the dLib scans (header vir/izdano
    # name the print and the dLib URN). The cone is read at fetch time from
    # list=allcategories (prefix "Dela leta "), so a new year category
    # joins without a code change.
    #
    # == Exclusions BY RULE (counted in discovery_skips)
    #
    # Translations (Prevodi 112 in the cone, Prepesnitve) — modern or not,
    # not Slovene originals; non-Slovene works (Dela v latinščini 14,
    # nemščini/Nemške pesmi (France Prešeren), angleščini, hrvaščini, …);
    # permission-licensed pages (Objavljeno s pisnim/z ustnim dovoljenjem
    # — 0 in the cone at census, kept as a guard: only public-domain
    # pages ride an attribution-class source).
    #
    # == The held-Slovene OVERLAP — the declared policy
    #
    # Census (title-key match, 2026-10-10): of the 1,545 cone pages, 25
    # works also stand in the held corpora — 23 in imp (IMP's diplomatic
    # + modernized layers: Blagodejna zvezdica, Kranjska nevesta, Lesena
    # noga, Turški Pavliha …) and 2 in prilit (Deteljica; Sreča v nesreči,
    # which prilit holds in 7 witness rows); KDSP is not held. POLICY:
    # ingest WITH provenance, never drop — the copies are DIFFERENT
    # editions (Wikivir's corrected transcription of a named print vs
    # IMP's/PriLit's own TEI editions), and dedupe/witness alignment is a
    # catalog-side concern (title + author + year are all in metadata for
    # it). Dropping at the adapter would silently erase an edition.
    #
    # == Claims
    #
    # Language sl (the registry anchor imp/prilit claim); the stage rides
    # the typed year through the ruled sl bands (lect posture dates). The
    # year category is a typed date: metadata "date" {not_before,
    # not_after, raw} (MetadataDates :structured; a page under two years
    # spans them). Orthography is declared, never normalized: Dela v
    # bohoričici → metadata "orthography" "bohoričica"; Dela v
    # prekmurščini → "variety" "prekmurščina". Base edition (№R-74): the
    # header's izdano (publication line) verbatim, else spisano, else vir,
    # else "unstated"; vir rides separately as "source".
    class SlWikisource < SlavicWikisource
      API_URL = "https://sl.wikisource.org/w/api.php"
      STATE_FILE = ".sl-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:sl-wikisource:"
      LANGUAGE = "sl"
      HEADER_TEMPLATES = %w[naslov naslov-mp].freeze
      YEAR_PREFIX = "Dela leta "
      CUTOFF_YEAR = 1899

      NOT_SLOVENE = "not a Slovene original"
      EXCLUSIONS = {
        "Kategorija:Prevodi" => "translation",
        "Kategorija:Prepesnitve" => "translation",
        "Kategorija:Dela v latinščini" => NOT_SLOVENE,
        "Kategorija:Dela v nemščini" => NOT_SLOVENE,
        "Kategorija:Nemške pesmi (France Prešeren)" => NOT_SLOVENE,
        "Kategorija:Dela v angleščini" => NOT_SLOVENE,
        "Kategorija:Dela v francoščini" => NOT_SLOVENE,
        "Kategorija:Dela v italijanščini" => NOT_SLOVENE,
        "Kategorija:Dela v madžarščini" => NOT_SLOVENE,
        "Kategorija:Dela v portugalščini" => NOT_SLOVENE,
        "Kategorija:Dela v hrvaščini" => NOT_SLOVENE,
        "Kategorija:Dela v srbohrvaščini" => NOT_SLOVENE,
        "Kategorija:Dela v srbščini" => NOT_SLOVENE,
        "Kategorija:Objavljeno s pisnim dovoljenjem" => "permission-licensed (not public domain)",
        "Kategorija:Objavljeno z ustnim dovoljenjem" => "permission-licensed (not public domain)"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "sl-wikisource",
        name: "Wikivir (Slovene Wikisource) — the dated cone to 1899",
        license: "Hosted texts PD (Kategorija:V javni domeni); the transcription layer Creative " \
                 "Commons Attribution-ShareAlike 4.0 (sl.wikisource.org footer verbatim, verified " \
                 "2026-10-10) → attribution, credit the Wikivir contributors",
        license_class: "attribution",
        upstream_url: "https://sl.wikisource.org/",
        parser_family: "wikisource-slavic",
        credit: "Wikivir (sl.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      # The year categories ≤ CUTOFF_YEAR, read live (memoized per run).
      def cone
        @cone ||= year_categories.map { |name| Cone.new(category: "Kategorija:#{name}", depth: 0, label: name) }
      end

      private

      def year_categories
        names = []
        continue = {}
        loop do
          payload = get_json("action" => "query", "format" => "json", "list" => "allcategories",
                             "acprefix" => YEAR_PREFIX, "aclimit" => "500", **continue)
          names.concat((payload.dig("query", "allcategories") || []).map { |entry| entry.fetch("*") })
          token = payload.dig("continue", "accontinue") or break

          continue = { "accontinue" => token }
        end
        names.select { |name| (year = year_of(name)) && year <= CUTOFF_YEAR }.sort_by { |name| year_of(name) }
      end

      def year_of(label)
        label[/\A#{YEAR_PREFIX}(\d{3,4})\z/o, 1]&.to_i
      end

      def extra_metadata(envelope, result)
        categories = Array(envelope["categories"])
        {
          "date" => typed_date(envelope),
          "orthography" => ("bohoričica" if categories.include?("Kategorija:Dela v bohoričici")),
          "variety" => ("prekmurščina" if categories.include?("Kategorija:Dela v prekmurščini")),
          "source" => header_value(result.header, %w[vir])
        }.compact
      end

      def typed_date(envelope)
        labels = Array(envelope["cone"]).select { |label| year_of(label) }
        return nil if labels.empty?

        years = labels.map { |label| year_of(label) }
        { "not_before" => years.min, "not_after" => years.max, "raw" => labels.join(" · ") }
      end

      def base_edition(_envelope, result)
        stated = header_value(result.header, %w[izdano]) || header_value(result.header, %w[spisano]) ||
                 header_value(result.header, %w[vir])
        stated ? Nabu::Normalize.nfc(stated) : "unstated"
      end
    end
  end
end
