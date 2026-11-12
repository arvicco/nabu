# frozen_string_literal: true

require_relative "titus_levels_adapter"

module Nabu
  module Adapters
    # TITUS Old Lithuanian texts — the Lithuanian editions TITUS hosts as
    # retrievable text (J. W. Goethe-Universität Frankfurt, Prof. Jost
    # Gippert), censused from TITUS's own text index (texte2.htm,
    # 2026-11-12): Mažvydas's Catechism, his Ambrosian hymn and his
    # baptismal Forma, the Wolfenbüttel Postil, Szyrwid's Punktai sakymų,
    # Daukša's, Vilentas's, Lysius's and Engel's catechisms, the Dzūkian
    # prayers and Donelaitis's Metai. Language `lit` (the lect posture
    # stages it lt:old — config/lect_overrides.yml).
    #
    # == Terms and the credit duty
    #
    # Gated — contact TITUS for a license grant. The titus-avestan
    # mechanisms verbatim: `grant_required: true` guards the fetch right;
    # license_class `nc` + the manifest +credit+ line carry the display duty
    # (every edition's data-entry editors named in it; each document's own
    # "editors" metadata names its edition's).
    #
    # == Delivery grains (census 2026-11-12) and the reconciliation
    #
    # Each edition is its own frameset (<dir>/<prefix>.htm: text frame
    # <prefix>001.htm, index frame <prefix>xx.htm → <prefix>x.htm →
    # <prefix>x1.htm …, whose option lists ARE the page map — page n is
    # option n + the frame's offset). Index census, pages per edition:
    # dzuk 3, mazvga 5, forma 13 (FC 4 + the FCNot. notes 9), mazvkat 10,
    # wp 75 (its last page "Notes"), spslt 25, dauksakt 5, vilentas 16 (its
    # last page the "N." notes), lysius 13, engels 19, donmetai 4 — 188
    # pages in the 11 accepted editions. Accepted grain: a page carrying a
    # run of the Lithuanian lanes is one document; a page with none (the
    # editions' notes pages — vilen016 pinned) skips by rule, counted in
    # discovery_skips. Rejected whole editions, never fetched: Szyrwid's
    # Polish text (spspl, 25 pages — not Lithuanian; a Polish shelf is its
    # own packet) and his Latin notes (spsnt, 2 pages — the editor's
    # apparatus); the framesets and index frames are navigation. EXPECTED
    # FIRST SYNC: 188 pages → ~176 documents (the notes pages skip; the
    # exact split reconciles here after the retrieval).
    #
    # == Lanes (see Nabu::Adapters::TitusLevelsParser)
    #
    # The Lithuanian lanes are `bpal*` (Mažvydas, the Postil) and `baal*`
    # (Vilentas, Donelaitis), with the typography/quotation flavors the
    # sample census shows — x (hyphen-broken fragment), r (roman), b, i,
    # and the Postil's quotation classes j, k, l; `…f12` footnotes and the
    # Postil's `bpalv16` footnote-link holders are apparatus. The Latin
    # (`wela*`) and Greek (`gr*`) of the prints ride the `latin` / `greek`
    # annotations. Units: the printed LINE (Mažvydas's XLevel lines, the
    # Postil's Level lines), Donelaitis's verse, the catechisms' paragraph.
    #
    # == Dating and place: deliberately coarse
    #
    # Only what upstream states: three catechisms carry their print year in
    # TITUS's own text siglum (the index frame's "Text" value, verbatim in
    # every anchor) — Daukša "Kat.1595", Vilentas "Kat.1579", Lysius
    # "Kat.1719" — dated as class edition. The other editions' title pages
    # were not in the fixture census: their imprints are read from the held
    # pages after the first retrieval (the titus-old-prussian precedent),
    # never supplied from scholarship. No place is claimed.
    class TitusOldLithuanian < TitusLevelsAdapter
      SLUG = "titus-old-lithuanian"
      LANGUAGE = "lit" # Lithuanian (the lect stage lt:old via lect_overrides)
      NAME = "TITUS Old Lithuanian Texts"
      TITLE = "Old Lithuanian"

      BASE_URL = "https://titus.uni-frankfurt.de/texte/etcs/balt/lit/"

      # The other-language lanes, classified from the first retrieval's 27
      # quarantined pages (2026-11-12, the loud-quarantine discipline):
      # oend* is the GERMAN lane exactly as in the Old Prussian family —
      # Mažvydas's German hymn/source lines ("Nu bitten wir…") and Engel's
      # German title text, oendx its hyphen-broken flavor; bpla* is the
      # LATIN lane (the -la stem, the Albanian bula twin): rubrics
      # ("Dicat"), "&c." and Roman numerals inside the Lithuanian text,
      # bplax its drop-cap/display flavor; oec is the German apparatus's
      # quire-signature furniture (a lone "B" beside the v-flavor
      # apparatus lanes of the Wolfenbüttel Postil) — excluded like the
      # family's other furniture, nothing lexical rides it; oeopl* is the
      # OLD POLISH source lane of the same oe- family ("O Anno pany…",
      # the Polish hymn sources beside Mažvydas's German ones).
      LANES = TitusLevelsParser::Lanes.new(
        prefixes: %w[bpal baal], text_flavors: "bijklrx",
        others: { /\Awela/ => "latin", /\Agrx?\d/ => "greek",
                  /\Aoend/ => "german", /\Aoeopl/ => "polish", /\Abpla/ => "latin" },
        excluded: [/\Aoec\d+\z/]
      )

      # A catechism whose TITUS text siglum names its print year (the index
      # frame's "Text" value, verbatim in every anchor): class edition.
      def self.siglum_year(siglum)
        year = Integer(siglum[/\d{4}\z/], 10)
        { "not_before" => year, "not_after" => year, "raw" => siglum, "class" => "edition" }.freeze
      end

      # census: 11 Lithuanian editions on texte2.htm, 2026-11-12 (names and
      # editors verbatim from the index; spspl/spsnt rejected — class doc)
      EDITIONS = {
        "dzuk" => Edition.new(path: "dzuk/dzuk.htm", prefix: "dzuk", name: "Dzukian Prayers",
                              editors: "J. Gelumbeckaite (Frankfurt), SLIEKKAS project",
                              credit_name: "Gelumbeckaitė"),
        "mazvga" => Edition.new(path: "mazvga/mazvg.htm", prefix: "mazvg",
                                name: "Martynas Mažvydas, Giesme S. Ambraßeijaus",
                                editors: "P.U. Dini (Pisa)", credit_name: "Dini"),
        "forma" => Edition.new(path: "forma/forma.htm", prefix: "forma",
                               name: "Martynas Mažvydas, Forma Chrikstima",
                               editors: "D. Ardoino (Pisa), SLIEKKAS project", credit_name: "Ardoino"),
        "mazvkat" => Edition.new(path: "mazvkat/mazvk.htm", prefix: "mazvk", name: "Martynas Mažvydas, Katekizmas",
                                 editors: "D. Ardoino (Pisa) and J. Gelumbeckaite (Frankfurt), SLIEKKAS project",
                                 credit_name: "Ardoino/Gelumbeckaitė"),
        "wp" => Edition.new(path: "wp/wp.htm", prefix: "wp", name: "Wolfenbüttel Postilla",
                            editors: "J. Gelumbeckaite (Frankfurt)", credit_name: "Gelumbeckaitė"),
        "spslt" => Edition.new(path: "spslt/spslt.htm", prefix: "spslt",
                               name: "Constantin Szyrwid, Punktai Sakimu (Lithuanian text)",
                               editors: "Felix Thies (Berlin)", credit_name: "Thies"),
        "dauksakt" => Edition.new(path: "dauksakt/dauks.htm", prefix: "dauks", name: "Mikalojus Daukša, Catechism",
                                  editors: "Steven Young (UMBC)", credit_name: "Young",
                                  date: siglum_year("Kat.1595")),
        "vilentas" => Edition.new(path: "vilentas/vilen.htm", prefix: "vilen", name: "Baltramejus Vilentas, Catechism",
                                  editors: "R.P. Ritter (Frankfurt)", credit_name: "Ritter",
                                  date: siglum_year("Kat.1579")),
        "lysius" => Edition.new(path: "lysius/lysiu.htm", prefix: "lysiu",
                                name: "Heinrich Johann Lysius, Catechism",
                                editors: "P.U. Dini (Pisa)", credit_name: "Dini",
                                date: siglum_year("Kat.1719")),
        "engels" => Edition.new(path: "engels/engel.htm", prefix: "engel", name: "Gabriel Engels, Catechism",
                                editors: "D. Ardoino (Pisa), SLIEKKAS project", credit_name: "Ardoino"),
        "donmetai" => Edition.new(path: "donelait/donmetai/donme.htm", prefix: "donme", name: "Donelaitis, Metai",
                                  editors: "G. Keydana (Münster)", credit_name: "Keydana")
      }.freeze

      LICENSE = "gated — contact TITUS for a license grant; held on the TITUS family terms: one " \
                "retrieval, local research use only, no redistribution; TITUS and the editors " \
                "clearly indicated wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Old Lithuanian text editions, data entry " \
               "#{EDITIONS.values.map(&:credit_name).flat_map { _1.split('/') }.uniq.join(', ')} " \
               "(each document names its edition's editors).".freeze
    end
  end
end
