# frozen_string_literal: true

require_relative "slavic_wikisource"

module Nabu
  module Adapters
    # hr-wikisource (P116-2, 02-sources row 234): the Croatian Wikisource
    # premodern CENTURY cone — census 2026-10-10: the wiki files its old
    # literature under period categories inside Hrvatska književnost, and
    # the cone is every ns-0 page reachable (depth 2) from the five
    # premodern ones —
    #
    #   Hrvatski srednji vijek 12 · Hrvatsko 15. stoljeće 3 (+ the Džore
    #   Držić / Vetranović author cats) · Hrvatsko 16. stoljeće 598
    #   (+ Judita, Marin Držić's plays, Vetranović, Bunić Vučić, Sasin,
    #   Planine, the Siget epics …) · Hrvatsko 17. stoljeće 39 (+ Osman,
    #   Gundulić, Đurđević, Frankopan …) · Hrvatsko 18. stoljeće 41
    #   (+ Razgovor ugodni, Satir, Sveta Rožalija …)
    #
    # — union 1,401 pages / ~5.9 MB of wikitext. Hrvatsko 19./20./21.
    # stoljeće are OUT by rule (the modern standard; the cone stops at
    # 1800); translations out by rule (the header's prevoditelj param).
    #
    # == Claims
    #
    # Language hrv (the transcriptions are the editions' normalized Latin
    # script — Judita's "vojsko(m)" restorations included, verbatim). The
    # century categories a page reaches band the grade-2 era envelope
    # ("era_band" → MetadataDates :era_band_key, precision era — an
    # attribution, never a typed date); author categories filed under two
    # centuries (Vetranović 15+16, Bunić Vučić 16+17, Đurđević 17+18) give
    # the honest two-century span. The medieval band (1000–1500) is the
    # conventional Croatian medieval-literature span — declared, coarse.
    # Census note (not claimed): Povaljska listina (1250) is a Croatian
    # vernacular / Church Slavonic mix in Croatian Cyrillic — a chu/cro
    # recension candidate, reported, never guessed.
    class HrWikisource < SlavicWikisource
      API_URL = "https://hr.wikisource.org/w/api.php"
      STATE_FILE = ".hr-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:hr-wikisource:"
      LANGUAGE = "hrv"
      HEADER_TEMPLATES = %w[zaglavlje].freeze

      # The premodern period categories with each one's CE band.
      ERAS = {
        "Hrvatski srednji vijek" => [1000, 1500],
        "Hrvatsko 15. stoljeće" => [1401, 1500],
        "Hrvatsko 16. stoljeće" => [1501, 1600],
        "Hrvatsko 17. stoljeće" => [1601, 1700],
        "Hrvatsko 18. stoljeće" => [1701, 1800]
      }.freeze

      CONE = ERAS.keys.map { |era| Cone.new(category: "Kategorija:#{era}", depth: 2, label: era) }.freeze
      EXCLUSIONS = {}.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "hr-wikisource",
        name: "Croatian Wikisource — the premodern century cone (srednji vijek–18. stoljeće)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (hr.wikisource.org footer verbatim, verified 2026-10-10) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://hr.wikisource.org/",
        parser_family: "wikisource-slavic",
        credit: "Croatian Wikisource (hr.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      private

      def extra_metadata(envelope, _result)
        eras = Array(envelope["cone"]).select { |label| ERAS.key?(label) }
        { "eras" => (eras unless eras.empty?), "era_band" => era_band(eras) }.compact
      end

      def era_band(eras)
        bands = eras.map { |era| ERAS.fetch(era) }
        return nil if bands.empty?

        { "not_before" => bands.map(&:first).min, "not_after" => bands.map(&:last).max,
          "raw" => eras.join(" · ") }
      end
    end
  end
end
