# frozen_string_literal: true

require_relative "ia_scan_shelf"

module Nabu
  module Adapters
    # slavistics-pd — the public-domain German-Slavistics reference
    # canon as archive.org scans: Miklosich's Etymologisches Wörterbuch and
    # Vergleichende Grammatik, Berneker's Slavisches etymologisches
    # Wörterbuch I, Leskien's Handbuch (its back matter: OCS text editions
    # + glossary), Vondrák's Altkirchenslavische Grammatik and Freising
    # study, the Glagolita Clozianus in Kopitar's and Vondrák's editions,
    # and twelve Slavistics monographs of the Vienna Academy's
    # Sitzungsberichte / Denkschriften (the bounded pick — see below).
    # Mechanics: Nabu::Adapters::IaScanShelf (page grain over the hOCR
    # derivative pair; UNCORRECTED OCR declared on every document).
    #
    # == The census (2026-10-11; ITEMS below is its adopted half)
    #
    # Per work the best-OCR scan carrying the hOCR derivative pair was
    # chosen (measured: the share of whitespace tokens that read as words
    # — 0.47–0.89 across the adoptions; the Cyrillic/Glagolitic portions
    # are garbled on EVERY scan, the German/Latin/Czech prose reads).
    # Miklosich's Vergleichende Grammatik rides the one item holding all
    # four volumes from BSB scans under PDM 1.0 (vol. I 2nd ed. 1879,
    # vol. III 2nd ed. 1876, vols. II and IV as Winter's 1926 Manulneudruck
    # facsimiles of 1875 and 1868–74) — its OCR beats the Toronto set.
    # Berneker rides archive.org's own scan of the 1924 "zweite
    # unveränderte Auflage" (vol. I first appeared 1908–13). Skipped, with
    # reasons: scans with no hOCR derivatives (no page grain — Vondrák's
    # 1912 2nd ed., the Google scans of Über die langen Vocale, Die
    # slavischen Monatsnamen, Die slavischen Elemente im Rumunischen);
    # berdenursprungd00miklgoog (a whole mixed Denkschriften volume, not a
    # monograph); Subjectlose Sätze 1883 (Braumüller's trade edition, not
    # an Academy print).
    #
    # The Vienna Sitzungsberichte: the 597 phil.-hist. Classe volumes on
    # archive.org carry no contents metadata, so a Slavistics pick cannot
    # be censused at volume grain; the Academy's Slavistics monographs are
    # censused instead as their own items (separately printed off-prints,
    # each verified by its title page's "abgedruckt aus …" statement) —
    # twelve adopted (the ≤15 bound).
    #
    # == License
    #
    # Public domain: every author died by 1952 (Kopitar 1844, Miklosich
    # 1891, Leskien 1916, Jagić 1923, Vondrák 1925, Berneker 1937, Murko
    # 1952) and every print predates 1931. The scans are archive.org items
    # marked NOT_IN_COPYRIGHT or PDM 1.0 by their contributors (Toronto,
    # LoC, BSB/Google, RCIN, Slovakiana). Google-digitized items carry
    # Google's usage-guidelines page as page 1 — a request, not a license
    # term, ingested verbatim like any page.
    #
    # == Language
    #
    # Each document claims the language its PROSE is written in (deu; the
    # Clozianus editions lat/ces, Frisinské památky ces) — scholarship
    # ABOUT Slavic, not Slavic text; the object-language forms the OCR
    # mangles are never claimed as a Slavic lect.
    class SlavisticsPd < IaScanShelf
      MULTI = "miklosich-vergleichende-grammatik"
      SB = "Sitzungsberichte der kais. Akademie der Wissenschaften, phil.-hist. Classe"
      DS = "Denkschriften der kais. Akademie der Wissenschaften, phil.-hist. Classe"
      BRAUMUELLER = "Wien: Wilhelm Braumüller"
      VIENNA_ACADEMY = "Wien: k. k. Hof- und Staatsdruckerei, in Commission bei Karl Gerold's Sohn"

      ITEMS = [
        Item.new(key: "miklosich-ew-1886", identifier: "etymologischesw00mikluoft", language: "deu",
                 creator: "Franz Miklosich", title: "Etymologisches Wörterbuch der slavischen Sprachen",
                 date: dated(1886), imprint: BRAUMUELLER, genre: "etymological dictionary",
                 scan: "University of Toronto (Robarts)"),
        Item.new(key: "miklosich-vg1-lautlehre-1879", identifier: MULTI,
                 file: "1. Vergleichende Lautlehre (1879)", language: "deu", creator: "Franz Miklosich",
                 title: "Vergleichende Grammatik der slavischen Sprachen I: Lautlehre (2. Ausg.)",
                 date: dated(1879), imprint: BRAUMUELLER, genre: "comparative grammar",
                 scan: "BSB scan (PDM 1.0)"),
        Item.new(key: "miklosich-vg2-stammbildung-1875", identifier: MULTI,
                 file: "2. Vergleichende Stammbildungslehre (1926)", language: "deu",
                 creator: "Franz Miklosich",
                 title: "Vergleichende Grammatik der slavischen Sprachen II: Stammbildungslehre",
                 date: dated(1875, raw: "1875 (Manulneudruck Heidelberg 1926)"), imprint: BRAUMUELLER,
                 genre: "comparative grammar", scan: "BSB scan (PDM 1.0)",
                 note: "scan of the 1926 Manulneudruck (Heidelberg: Carl Winter) of the 1875 first edition"),
        Item.new(key: "miklosich-vg3-wortbildung-1876", identifier: MULTI,
                 file: "3. Vergleichende Wortbildungslehre (1876)", language: "deu",
                 creator: "Franz Miklosich",
                 title: "Vergleichende Grammatik der slavischen Sprachen III: Wortbildungslehre (2. Ausg.)",
                 date: dated(1876), imprint: BRAUMUELLER, genre: "comparative grammar",
                 scan: "BSB scan (PDM 1.0)"),
        Item.new(key: "miklosich-vg4-syntax-1868", identifier: MULTI, file: "4. Vergleichende Syntax (1926)",
                 language: "deu", creator: "Franz Miklosich",
                 title: "Vergleichende Grammatik der slavischen Sprachen IV: Syntax",
                 date: dated(1868, 1874, raw: "1868–1874 (Manulneudruck Heidelberg 1926)"),
                 imprint: BRAUMUELLER, genre: "comparative grammar", scan: "BSB scan (PDM 1.0)",
                 note: "scan of the 1926 Manulneudruck (Heidelberg: Carl Winter) of the 1868–1874 first edition"),
        Item.new(key: "berneker-sew1-1908", identifier: "bwb_KU-309-930", language: "deu",
                 creator: "Erich Berneker", title: "Slavisches etymologisches Wörterbuch I: A–L",
                 date: dated(1908, 1913, raw: "1908–1913 (2. unveränderte Aufl. Heidelberg 1924)"),
                 imprint: "Heidelberg: Carl Winter", genre: "etymological dictionary",
                 scan: "Internet Archive (University of Nottingham copy)",
                 note: "scan of the 1924 second, unchanged printing; archive.org's language field " \
                       "(eng) is wrong — the text is German"),
        Item.new(key: "leskien-handbuch-1905", identifier: "handbuchderaltbu00leskuoft", language: "deu",
                 creator: "August Leskien",
                 title: "Handbuch der altbulgarischen (altkirchenslavischen) Sprache: Grammatik, Texte, " \
                        "Glossar (4. Aufl.)",
                 date: dated(1905), imprint: "Weimar: Hermann Böhlaus Nachfolger", genre: "handbook",
                 scan: "University of Toronto (Robarts)",
                 note: "the back matter (OCS text editions + glossary) is Cyrillic: its OCR is " \
                       "largely unreadable"),
        Item.new(key: "vondrak-aksl-grammatik-1900", identifier: "altkirchenslavis00vond", language: "deu",
                 creator: "Wenzel Vondrák", title: "Altkirchenslavische Grammatik", date: dated(1900),
                 imprint: "Berlin: Weidmannsche Buchhandlung", genre: "grammar",
                 scan: "Princeton Theological Seminary"),
        Item.new(key: "vondrak-frisinske-pamatky-1896", identifier: "vondrak-frisinske-pamatky",
                 file: "Frisinské památky", language: "ces", creator: "Václav Vondrák",
                 title: "Frisinské památky, jich vznik a význam v slovanském písemnictví", date: dated(1896),
                 imprint: "V Praze: Česká akademie císaře Františka Josefa", genre: "monograph",
                 scan: "HathiTrust scan, re-uploaded (PDM 1.0)"),
        Item.new(key: "kopitar-clozianus-1836", identifier: "glagolitaclozia00chrygoog", language: "lat",
                 creator: "Bartholomäus Kopitar (ed.)",
                 title: "Glagolita Clozianus, id est codicis Glagolitici inter suos facile antiquissimi … " \
                        "leipsanon",
                 date: dated(1836), imprint: "Vindobonae: apud Carolum Gerold", genre: "text edition",
                 scan: "Google (Oxford University copy)",
                 note: "Latin prolegomena and apparatus around the OCS text (Glagolitic transcribed " \
                       "in Cyrillic) and its Greek parallels — only the Latin reads"),
        Item.new(key: "vondrak-glagolita-clozuv-1893", identifier: "glagolitaclozvvy00glag", language: "ces",
                 creator: "Václav Vondrák (ed.)", title: "Glagolita Clozův", date: dated(1893),
                 imprint: "V Praze: Česká akademie císaře Františka Josefa", genre: "text edition",
                 scan: "University of Toronto (Robarts)",
                 note: "Czech introduction and commentary around the OCS text — the lowest OCR " \
                       "reading of the shelf (0.47 at census): two-column pages interleave"),
        Item.new(key: "miklosich-nomina-1858", identifier: "10524171bsb", language: "deu",
                 creator: "Franz Miklosich", title: "Die Bildung der Nomina im Altslovenischen",
                 date: dated(1858), imprint: VIENNA_ACADEMY, series: "#{DS} IX",
                 genre: "monograph", scan: "BSB"),
        Item.new(key: "miklosich-personennamen-1860", identifier: "10524173bsb", language: "deu",
                 creator: "Franz Miklosich", title: "Die Bildung der slavischen Personennamen",
                 date: dated(1860), imprint: VIENNA_ACADEMY, series: "#{DS} X", genre: "monograph",
                 scan: "BSB"),
        Item.new(key: "miklosich-ortsnamen-1864", identifier: "10524174bsb", language: "deu",
                 creator: "Franz Miklosich", title: "Die Bildung der Ortsnamen aus Personennamen im Slavischen",
                 date: dated(1864), imprint: VIENNA_ACADEMY, series: "#{DS} XIV", genre: "monograph",
                 scan: "BSB"),
        Item.new(key: "miklosich-fremdwoerter-1867", identifier: "10524176bsb", language: "deu",
                 creator: "Franz Miklosich", title: "Die Fremdwörter in den slavischen Sprachen",
                 date: dated(1867), imprint: "Wien: k. k. Hof- und Staatsdruckerei", series: "#{DS} XV",
                 genre: "monograph",
                 scan: "BSB"),
        Item.new(key: "miklosich-acc-inf-1869", identifier: "uberdenaccusativ00mikl", language: "deu",
                 creator: "Franz Miklosich", title: "Über den Accusativus cum Infinitivo", date: dated(1869),
                 imprint: "Wien: Karl Gerold's Sohn", series: "#{SB} LX (1868)", genre: "monograph",
                 scan: "University of Illinois"),
        Item.new(key: "miklosich-imperfect-1874", identifier: "dasimperfectinde00mikl", language: "deu",
                 creator: "Franz Miklosich", title: "Das Imperfect in den slavischen Sprachen", date: dated(1874),
                 imprint: "Wien: Karl Gerold's Sohn", series: "#{SB} LXXVII", genre: "monograph",
                 scan: "Library of Congress"),
        Item.new(key: "miklosich-aksl-beitraege-1875", identifier: "beitragezuraltsl00mikl", language: "deu",
                 creator: "Franz Miklosich", title: "Beiträge zur altslovenischen Grammatik", date: dated(1875),
                 imprint: "Wien: Karl Gerold's Sohn", series: "#{SB} LXXXI", genre: "monograph",
                 scan: "Library of Congress"),
        Item.new(key: "miklosich-lautbezeichnung-1883", identifier: "geschichtederlau00mikl", language: "deu",
                 creator: "Franz Miklosich", title: "Geschichte der Lautbezeichnung im Bulgarischen",
                 date: dated(1883), imprint: "Wien: Carl Gerold's Sohn", series: "#{DS} XXXIV",
                 genre: "monograph", scan: "University of British Columbia"),
        Item.new(key: "miklosich-blutrache-1887", identifier: "11481890bsb", language: "deu",
                 creator: "Franz Miklosich", title: "Die Blutrache bei den Slaven", date: dated(1887),
                 imprint: "Wien: Carl Gerold's Sohn", series: "#{DS} XXXVI", genre: "monograph", scan: "BSB"),
        Item.new(key: "murko-sieben-weisen-1890",
                 identifier: "rcin.org.pl.WA248_276275_F-6376_murko-die-gesch_o_240092",
                 file: "WA248_276275_F-6376_murko-die-gesch_o", language: "deu", creator: "Matthias Murko",
                 title: "Die Geschichte von den sieben Weisen bei den Slaven", date: dated(1890),
                 imprint: "Wien: F. Tempsky", series: "#{SB} CXXI", genre: "monograph",
                 scan: "RCIN (Institute of Literary Research PAS)"),
        Item.new(key: "jagic-syntax-1899", identifier: "v_jagic_beitrage_zur_slavischen_syntax",
                 file: "vtls001409597_P", language: "deu", creator: "Vatroslav Jagić",
                 title: "Beiträge zur slavischen Syntax I: Zur Analyse des einfachen Satzes",
                 date: dated(1899), imprint: "Wien: Carl Gerold's Sohn", series: "#{DS} XLVI",
                 genre: "monograph", scan: "Slovakiana (Slovak National Library), re-uploaded (PDM 1.0)"),
        Item.new(key: "jagic-entstehungsgeschichte-1913", identifier: "entstehungsgesch00jagiuoft",
                 language: "deu", creator: "Vatroslav Jagić",
                 title: "Entstehungsgeschichte der kirchenslavischen Sprache (neue, berichtigte und " \
                        "erweiterte Ausgabe)",
                 date: dated(1913), imprint: "Berlin: Weidmannsche Buchhandlung", genre: "monograph",
                 scan: "University of Toronto (Robarts)",
                 note: "the revised book edition of the Denkschriften XLVII study (1900)")
      ].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "slavistics-pd",
        name: "PD Slavistics reference shelf — Miklosich, Berneker, Leskien, Vondrák, Jagić " \
              "(archive.org scans, uncorrected OCR)",
        license: "Public domain: authors died 1844–1952, every print pre-1931; archive.org items " \
                 "marked NOT_IN_COPYRIGHT or PDM 1.0 by their contributors (Toronto, LoC, BSB/Google, " \
                 "RCIN, Slovakiana). Text = archive.org's uncorrected machine OCR (hOCR derivatives)",
        license_class: "open",
        upstream_url: "https://archive.org/details/etymologischesw00mikluoft",
        parser_family: "ia-hocr-text"
      )

      def self.manifest = MANIFEST
    end
  end
end
