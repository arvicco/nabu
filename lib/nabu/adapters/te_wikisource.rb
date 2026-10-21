# frozen_string_literal: true

require_relative "indexed_wikisource"

module Nabu
  module Adapters
    # te-wikisource (P140, under the owner-ruled Wikisource posture): the
    # classical Telugu cone of the Telugu Wikisource — the work trees of
    # the kāvya / prabandha / śataka tradition (Nannaya and Tikkana to
    # Kūcimañci Timmana, 11th–18th c.) as the 1891–1930 Madras prints
    # (Vavilla, Ananda Mudranalayam …) the wiki transcribes from scans,
    # under the mechanical year filter.
    #
    # == The census (2026-10-21) — the cone is COMPOSITION-bounded
    #
    # 12,635 pages carry the {{తలకట్టు}} header; its సంవత్సరం= states the
    # print year (7,121 after 1930, 3,097 in 1800–1930, 2,311 none). The
    # 1800–1930 slice is mostly MODERN composition (encyclopedias,
    # biographies, the 1910s–20s textbooks and poets), so the cone is the
    # censused work list below — every work whose author is a pre-1800
    # classical poet (the census read each work's రచయిత= against the
    # poet's era) and whose print falls in the window: 73 work trees +
    # the Sanskrit specimen below, 565 pages (prefix + subpages). Census
    # fetch: 453 documents / 208,794 passages admitted; 112 skipped by
    # rule — 60 edition_taint (scans whose Index states a post-1930
    # reprint), 25 edition_unstated, 21 apparatus, 5 translation (C. P.
    # Brown's 1911 Vemana: the header's అనువాదం= names Brown's English
    # layer), 1 sanskrit_overlap.
    #
    # == The Sanskrit-in-Telugu-script overlap (EXCLUDED, censused)
    #
    # The wiki hosts Sanskrit in Telugu script: the ఋగ్వేదము (1,035
    # pages), యజుర్వేదము (43), సామవేదము (37), అథర్వణవేదము (21) and the
    # వ్యాస మహాభారతము (2,016) categories, plus single works (Jagannātha's
    # భామినీవిలాసమ్, 1902) — all held through the Sanskrit lanes
    # (DCS/GRETIL). None of the category trees enters the prefix cone;
    # the rule (sanskrit_overlap) still guards every page by its category
    # tags, its Index భాష=sa and the censused SANSKRIT_ROOTS, so a
    # re-categorized page can never leak in.
    #
    # == Apparatus and the year
    #
    # The editors' notices and indexes skip (విజ్ఞప్తి, విషయసూచిక,
    # ఉపోద్ఘాతము, భూమిక, ప్రవేశిక, INDEX, PREFACE). పీఠిక is KEPT and
    # declared: in some prints it is the poem's own invocatory pīṭhika
    # (కాశీఖండము), in others the editor's preface (హరివంశము) — no page
    # field separates them. The header సంవత్సరం= and the Index సంవత్సరం=
    # are the edition evidence (#years_in drops years before 1800: no
    # Telugu print predates that, so an earlier year is the composition's,
    # never an edition); REQUIRE_EDITION_YEAR. The print year rides
    # source_date (MetadataDates :edition_year_text, date_class edition).
    # Language tel (Telugu script, implied).
    class TeWikisource < IndexedWikisource
      API_URL = "https://te.wikisource.org/w/api.php"
      STATE_FILE = ".te-wikisource-fetch.json"
      URN_PREFIX = "urn:nabu:te-wikisource:"
      INDEX_NS = "సూచిక"
      PAGE_NS = 104
      FIRST_PRINT_YEAR = 1800

      # Census 2026-10-21: the classical works printed 1891–1930.
      WORKS = [
        "భక్తిరసశతకసంపుటము", "హరివంశము", "దశకుమారచరిత్రము", "దశావతారచరిత్రము",
        "వరాహపురాణము (నంది మల్లయ, ఘంట సింగయ)", "శ్రీరంగమాహాత్మ్యము", "భారతం-శాంతిసప్తకం",
        "కావ్యాలంకారచూడామణి", "కాశీఖండము", "పరమయోగి విలాసము", "ఆంధ్ర శ్రీవిష్ణుపురాణము", "సమీరకుమారవిజయము",
        "భాస్కరరామాయణము", "రామాభ్యుదయము", "భారతం-విరాటోద్యోగం", "భీమేశ్వరపురాణము", "కవికర్ణరసాయనము",
        "కవిరాజమనోరంజనము", "శశాంకవిజయము", "భారతం-ఆరణ్యం", "పారిజాతాపహరణము", "కుమారసంభవము",
        "కుమారసంభవము (1909)", "కుమారసంభవము (మానవల్లి)", "బహులాశ్వచరిత్రము", "రసికజనమనోభిరామము",
        "రుక్మిణీపరిణయము", "మత్స్యపురాణము", "నరసభూపాలీయము", "పంచతంత్రము (దూబగుంట నారాయణ)", "ఛందోదర్పణము",
        "నృసింహపురాణము", "పంచతంత్రము (బైచరాజు)", "కువలయాశ్వచరిత్రము", "చంద్రభానుచరిత్రము", "కకుత్స్థవిజయము",
        "శ్రీకృష్ణవిజయము", "ప్రభులింగలీల", "యయాతిచరిత్రము", "రామేశ్వరమాహాత్మ్యము", "ఆనందరంగరాట్ఛందము",
        "రుక్మాంగదచరిత్రము", "సర్వలక్షణసారసంగ్రహము", "వైజయంతీవిలాసము", "వేమన పద్యములు (సి.పి.బ్రౌన్)",
        "అనిరుద్ధచరిత్రము", "శృంగార మల్హణచరిత్ర", "బిల్హణీయము (చిత్రకవి సింగరాచార్యుఁడు)", "బద్ది నీతులు",
        "రాజశేఖరవిలాసము", "మొల్ల రామాయణం", "మొల్ల రామాయణము (వావిళ్ళ)", "మొల్ల రామాయణం (రామా అండ్ కో)",
        "అహల్యాసంక్రందనము", "సర్పపురమాహాత్మ్యము", "చంద్రరేఖావిలాపము", "కవిసంశయవిచ్ఛేదము",
        "సారంగధరచరిత్రము (చేమకూర వేంకటపతి)", "సారంగధరచరిత్రము (కూచిమంచి తిమ్మన)", "శృంగార సావిత్రి",
        "కేయూరబాహుచరిత్రము", "శివలీలావిలాసము", "బసవపురాణము (పిడుపర్తి సోమన)", "పండితారాధ్యచరిత్ర (గుజిలీప్రతి)",
        "రంగనాథరామాయణము - ఉత్తరకాండ", "కృష్ణార్జునసంవాదము", "సులక్షణసారము", "ధ్రువోపాఖ్యానము", "ద్విపద భారతము",
        "హరిశ్చంద్రనలోపాఖ్యానము", "క్రీడాభిరామము", "భాస్కర శతకము", "శాసనపద్యమంజరి (మొదటిభాగం)"
      ].freeze
      SANSKRIT_ROOTS = {
        "భామినీవిలాసమ్" => "Jagannātha Paṇḍitarāja's Bhāminīvilāsa (1902 print) — Sanskrit in Telugu script"
      }.freeze
      SANSKRIT_CATEGORIES = ["ఋగ్వేదము", "యజుర్వేదము", "సామవేదము", "అథర్వణవేదము", "వ్యాస మహాభారతము",
                             "సంస్కృత రచన", "సంస్కృత కావ్యాలు"].freeze
      SANSKRIT_LANGUAGES = %w[sa].freeze

      CONE = { categories: {}, prefixes: WORKS + SANSKRIT_ROOTS.keys, titles: [], indexes: [] }.freeze

      APPARATUS_SEGMENT = /\A(విజ్ఞప్తి|విషయసూచిక|ఉపోద్ఘాతము|భూమిక|ప్రవేశిక|పదపట్టిక|INDEX|PREFACE)\z/
      EDITION_FIELDS = %w[సంవత్సరం].freeze
      TRANSLATOR_FIELDS = %w[అనువాదం].freeze
      HEADER_TEMPLATE = "తలకట్టు"
      HEADER_FIELDS = { "author" => "రచయిత", "section" => "విభాగము", "year" => "సంవత్సరం",
                        "notes" => "వివరములు" }.freeze
      INDEX_FIELDS = {
        "title" => "శీర్షిక", "author" => "రచయిత", "editor" => "ఎడిటర్", "publisher" => "ప్రచురణకర్త",
        "place" => "చిరునామా", "year" => "సంవత్సరం", "source" => "మూలం", "progress" => "పురోగతి",
        "language" => "భాష"
      }.freeze
      REQUIRE_EDITION_YEAR = true
      LANGUAGES = { "te" => "tel", nil => "tel" }.freeze

      RULE_NOTES = IndexedWikisource::RULE_NOTES.merge(
        sanskrit_overlap: "Sanskrit-in-Telugu-script page(s) — held through the Sanskrit lanes " \
                          "(SANSKRIT_ROOTS / SANSKRIT_CATEGORIES / Index భాష=sa)"
      ).freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "te-wikisource",
        name: "Telugu Wikisource — the classical cone (kāvya, prabandha, śataka; prints to 1930)",
        license: "Hosted texts PD; the transcription layer Creative Commons Attribution-ShareAlike " \
                 "4.0 (te.wikisource.org rightsinfo verbatim, verified 2026-10-21) → attribution, " \
                 "credit the Wikisource contributors",
        license_class: "attribution",
        upstream_url: "https://te.wikisource.org/",
        parser_family: "wikisource-html",
        credit: "Telugu Wikisource (te.wikisource.org) contributors, CC BY-SA 4.0"
      )

      def self.manifest = MANIFEST

      def wikitext_class(title, wikitext)
        return :sanskrit_overlap if sanskrit_page?(title, wikitext)

        super
      end

      def index_class(envelope)
        languages = Array(envelope["indexes"]).filter_map { |index| index_role(index, "language")&.downcase }
        return :sanskrit_overlap if languages.intersect?(SANSKRIT_LANGUAGES)

        super
      end

      # Every edition year a text states, CE — a year before the first
      # Telugu print is a composition year, never edition evidence.
      def years_in(text)
        super.select { |year| year >= FIRST_PRINT_YEAR }
      end

      private

      def sanskrit_page?(title, wikitext)
        return true if SANSKRIT_ROOTS.key?(title.split("/").first)

        SANSKRIT_CATEGORIES.any? { |category| wikitext.match?(/\[\[\s*వర్గం\s*:\s*#{Regexp.escape(category)}\s*[|\]]/) }
      end

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
          year = index_role(index, "year") or next
          "#{INDEX_FIELDS['year']}: #{year} (#{index['name']})"
        end
        if years.empty? && (header = template_args(envelope.fetch("wikitext"), HEADER_TEMPLATE)["సంవత్సరం"])
          stated = display_text(header)
          years << "#{HEADER_FIELDS['year']}: #{stated} (header)" unless years_in(stated).empty?
        end
        years.empty? ? {} : { "source_date" => Nabu::Normalize.nfc(years.uniq.join(" · ")) }
      end
    end
  end
end
