# frozen_string_literal: true

require_relative "indexed_wikisource"

module Nabu
  module Adapters
    # gu-wikisource (P120-3, under the owner-ruled Wikisource posture): the
    # Gujarati bhakti cone of the Gujarati Wikisource — the author
    # categories of the medieval/early-modern poets (Narsinh Mehta, Mirabai,
    # Dayaram, Akho, Premanand) plus every page transcluding the Bruhat
    # Kavyadohan scan Indexes (Ichchharam Suryaram Desai's anthology,
    # Bombay 1888–1913).
    #
    # == The census verdict (2026-10-12) — the edition lives on the Index
    #
    # The pages carry no edition in their {{header}}; the scan's Index
    # page states it (વર્ષ= year, સંપાદક= editor). The author categories
    # transclude from MANY Indexes, and only the Bruhat Kavyadohan family
    # (and Akhegita 1914, Rasik Vallabh 1890) states a year: the large
    # Meerabai Lekhan / Narasinh lekhan 2 / Mira Ane Narsinh / Bhajan Sar
    # Sindhu / Dayaram Lekhan scans state NONE. REQUIRE_EDITION_YEAR: an
    # undated edition cannot pass EDITION_TAINT_POST_1930, so those pages
    # skip by rule (edition_unstated) — the conservative default; dating
    # those scans is a recorded future look, never guessed.
    #
    # The year (verbatim) feeds the edition-year date lane (source_date →
    # MetadataDates :edition_year_text, date_class edition — never the
    # poets' composition era). Language guj (Gujarati script); an Index
    # declaring any other language quarantines the page (LANGUAGES).
    class GuWikisource < IndexedWikisource
      API_URL = "https://gu.wikisource.org/w/api.php"
      STATE_FILE = ".gu-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:gu-wikisource:"
      INDEX_NS = "સૂચિ"
      PAGE_NS = 104

      POETS = ["નરસિંહ મહેતા", "મીરાંબાઈ", "દયારામ", "અખો", "પ્રેમાનંદ"].freeze
      KAVYADOHAN = [
        "Bruhad Kavyadohan Granth 1.pdf",
        "Bruhad Kavyadohan Granth 3.pdf",
        "Bruhad Kavyadohan Granth X.pdf",
        "Bruhat Kavyadohan Granth 2 (1913 - Edition 3).pdf",
        "Bruhat Kavyadohan Granth 8 (1913).pdf",
        "Burhat Kavya Dohan - Granth 1 (1890 - Edition 3).pdf"
      ].freeze

      CONE = {
        categories: POETS.to_h { |name| ["શ્રેણી:#{name}", 0] },
        prefixes: [],
        titles: [],
        indexes: KAVYADOHAN
      }.freeze

      INDEX_FIELDS = {
        "title" => "શીર્ષક", "author" => "સર્જક", "editor" => "સંપાદક", "publisher" => "પ્રકાશક",
        "place" => "સરનામું", "year" => "વર્ષ", "source" => "સ્રોત", "progress" => "પ્રગતિ",
        "language" => "ભાષા"
      }.freeze
      HEADER_FIELDS = { "author" => "author", "section" => "section", "year" => "year", "notes" => "notes" }.freeze
      REQUIRE_EDITION_YEAR = true
      EXCLUDED_INDEXES = {
        "Mameru.pdf" => "the Index's વર્ષ=1683 is Premanand's composition year, not the scan's print " \
                        "(no edition is stated) — never edition evidence"
      }.freeze
      LANGUAGES = { "gu" => "guj", nil => "guj" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "gu-wikisource",
        name: "Gujarati Wikisource — the bhakti cone (Narsinh Mehta · Mirabai · Dayaram · Akho · " \
              "Premanand; Bruhat Kavyadohan)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (gu.wikisource.org footer verbatim, verified 2026-10-12) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://gu.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Gujarati Wikisource (gu.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      private

      def language_for(envelope)
        declared = Array(envelope["indexes"]).map { |index| index_role(index, "language") }.uniq
        codes = declared.map do |language|
          LANGUAGES.fetch(language&.downcase) do
            raise ParseError, "#{envelope['title']}: Index language #{language.inspect} is not censused " \
                              "(LANGUAGES) — quarantined, never guessed"
          end
        end
        codes.first || LANGUAGES.fetch(nil)
      end

      def extra_metadata(envelope)
        years = Array(envelope["indexes"]).filter_map do |index|
          year = index_role(index, "year") or next
          "#{INDEX_FIELDS['year']}: #{year} (#{index['name']})"
        end
        years.empty? ? {} : { "source_date" => Nabu::Normalize.nfc(years.uniq.join(" · ")) }
      end
    end
  end
end
