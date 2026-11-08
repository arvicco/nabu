# frozen_string_literal: true

require_relative "ia_scan_shelf"

module Nabu
  module Adapters
    # mongolic-pd — the public-domain Manchu–Mongolic–Oirat reference shelf
    # as archive.org scans (the manchu-mongolic round-2 survey §2.3): the
    # great 19th-century dictionaries, grammars and chrestomathies of
    # Manchu, Classical (written) Mongolian and Written Oirat (Kalmyk).
    # Mechanics: Nabu::Adapters::IaScanShelf (page grain over the hOCR
    # derivative pair; UNCORRECTED OCR declared on every document — the
    # slavistics-pd / africa-pd mold).
    #
    # == The census (2026-11-08; ITEMS below)
    #
    # Per work the scan carrying the hOCR derivative pair whose title page
    # matches the work. Taken: Zakharov's Полный маньчжурско-русский
    # словарь (1875 — THE big Manchu dictionary, its headwords in Cyrillic
    # transcription and so searchable); Möllendorff's Manchu Grammar with
    # analysed texts (1892); Amiot–Langlès' Dictionnaire tartare-mantchou-
    # françois, tome I (1789); Klaproth's Chrestomathie mandchou (1828);
    # Meadows' Translations from the Manchu (1849); Adam's Grammaire de la
    # langue mandchou (1873); Wylie's translation of the 清文啓蒙 (1855);
    # Kowalewski's Dictionnaire mongol-russe-français in its three volumes
    # (1844, 1846, 1849 — one archive.org item, one hOCR pair per volume);
    # I. J. Schmidt's Grammatik der mongolischen Sprache (1831);
    # Kowalewski's Монгольская хрестоматия II (1837); Pozdneev's
    # Калмыцко-русский словарь (1911); Jülg's Märchen des Siddhi-Kür
    # (1866); Popov's Грамматика калмыцкаго языка (1847).
    #
    # Skipped, with reasons (every copy censused carries NO hOCR pair —
    # djvu.txt only, which this shelf's parser does not read): Gabelentz's
    # Mandschu-Deutsches Wörterbuch (1864; bub_gb_QPg9AAAAcAAJ, the only
    # copy), Harlez's Manuel de la langue mandchoue (1884; both Michigan
    # copies), Rémusat's L'invariable milieu (1817; bub_gb_-8oWAAAAQAAJ),
    # Amiot's tome II (1790; dictionnairetar01amyogoog), and the hOCR-less
    # duplicate copies of Adam and Schmidt (the taken copies carry the
    # pair). The survey's NOT-taken stay out: the Li Hung 1913 trilingual
    # dictionary (native script only, unreadable OCR), the 1869 Manchu NT
    # (native script only), Hauer's Handwörterbuch (1952–55 print) and
    # Ramstedt's Kalmückisches Wörterbuch (1935 print).
    #
    # == License
    #
    # Public domain: every author died by 1920 (Amiot 1793, Langlès 1824,
    # Klaproth 1835, Schmidt 1847, Popov 1865, Meadows 1868, Kowalewski
    # 1878, Zakharov 1885, Jülg 1886, Wylie 1887, Möllendorff 1901, Adam
    # 1918, Pozdneev 1920) and every print predates 1931. The scans are
    # archive.org items marked NOT_IN_COPYRIGHT or PDM 1.0 by their
    # contributors (Google/Oxford, Google/Harvard, UC Libraries, the
    # Kowalewski community upload) or carrying no rights field (LoC with its
    # "unaware of any copyright restrictions" note, Cornell, BSB, the
    # Pozdneev community upload) — the works' status rests on those dates.
    # Google-digitized items carry Google's usage-guidelines page(s) — a
    # request, not a license term, ingested verbatim like any page.
    #
    # == Language
    #
    # Each document claims the language its PROSE is written in — the
    # reference-shelf posture: Russian (Zakharov, Kowalewski's dictionary
    # and chrestomathy, Pozdneev, Popov), English (Möllendorff, Meadows,
    # Wylie), French (Amiot, Klaproth, Adam) and German (Schmidt, Jülg).
    # The language each volume presents rides metadata "object_language":
    # mnc (Manchu), cmg (Classical Mongolian) and xwo (Written Oirat) —
    # all three registry nodes exist (nabu-lects, minted 2026-11-02). Coarse
    # at document grain, declared: Kowalewski's dictionary glosses in
    # Russian AND French and claims rus, its first-listed gloss language.
    #
    # == What the OCR keeps (and loses)
    #
    # Sampled mid-document (the survey): romanized and Cyrillic-transcribed
    # Manchu/Mongolian forms come out searchable; the native vertical
    # scripts — Manchu, Uyghur-Mongolian, the Oirat Clear Script — come out
    # as garbage. Native-script loss is declared on every document
    # (OCR_NOTE) and in the source dossier.
    class MongolicPd < IaScanShelf
      KOWALEWSKI = "kovalevskij-dictionnaire-mongol-russe-francais-1844-49-volumes-1-3"
      KOWALEWSKI_STEM = "Kovalevskij, Dictionnaire Mongol-Russe-Franca̧is (1844-49) - Volume %d"
      KOWALEWSKI_TITLE = "Dictionnaire mongol-russe-français / Монгольско-русско-французскій словарь, tome %s"

      ITEMS = [
        Item.new(key: "zakharov-manchu-russian-dictionary-1875", identifier: "polnyimanchzhurs00zakh",
                 language: "rus", creator: "И. И. Захаров (Ivan Zakharov)",
                 title: "Полный маньчжурско-русскій словарь", date: dated(1875),
                 imprint: "St Petersburg", genre: "dictionary", scan: "Library of Congress",
                 note: "the Manchu headwords in Zakharov's Cyrillic transcription (searchable) beside the " \
                       "native script (garbled in the OCR), with Russian definitions; the preface surveys " \
                       "the history of the Manchu script and literature"),
        Item.new(key: "mollendorff-manchu-grammar-1892", identifier: "cu31924023341112", language: "eng",
                 creator: "P. G. von Möllendorff", title: "A Manchu Grammar, with Analysed Texts",
                 date: dated(1892), imprint: "Shanghai: American Presbyterian Mission Press",
                 genre: "grammar", scan: "Cornell University Library",
                 note: "the grammar in Möllendorff's own romanization (the standard one since), with " \
                       "romanized Manchu texts analysed word by word"),
        Item.new(key: "amiot-dictionnaire-tartare-mantchou-1789", identifier: "dictionnairetar00amyogoog",
                 language: "fra", creator: "J.-M. Amiot; L. Langlès (ed.)",
                 title: "Dictionnaire tartare-mantchou-françois, composé d'après un dictionnaire " \
                        "mantchou-chinois, tome premier",
                 date: dated(1789), imprint: "Paris: Didot l'aîné", genre: "dictionary",
                 scan: "Google (Oxford University copy)",
                 note: "tome I only: the tome II scan (1790) carries no hOCR pair; Manchu headwords in " \
                       "Langlès' romanization beside the native script (garbled in the OCR)"),
        Item.new(key: "klaproth-chrestomathie-mandchou-1828", identifier: "chrestomathieman00klap",
                 language: "fra", creator: "Jules Klaproth",
                 title: "Chrestomathie mandchou, ou Recueil de textes mandchou, destiné aux personnes qui " \
                        "veulent s'occuper de l'étude de cette langue",
                 date: dated(1828), imprint: "Paris: Imprimerie royale", genre: "chrestomathy",
                 scan: "Library of Congress",
                 note: "Manchu texts printed in the native script (garbled in the OCR) with French " \
                       "apparatus and a vocabulary"),
        Item.new(key: "meadows-translations-from-the-manchu-1849", identifier: "translationsfrom00meadrich",
                 language: "eng", creator: "Thomas Taylor Meadows",
                 title: "Translations from the Manchu, with the Original Texts, Prefaced by an Essay on " \
                        "the Language",
                 date: dated(1849), imprint: "Canton: Press of S. Wells Williams", genre: "chrestomathy",
                 scan: "University of California Libraries",
                 note: "an essay on the language and English translations facing the Manchu originals " \
                       "(native script, garbled in the OCR)"),
        Item.new(key: "adam-grammaire-mandchou-1873", identifier: "grammairedelala00adamgoog", language: "fra",
                 creator: "Lucien Adam", title: "Grammaire de la langue mandchou", date: dated(1873),
                 imprint: "Paris: Maisonneuve et Cie", genre: "grammar",
                 scan: "Google (Harvard University copy)",
                 note: "French grammar with the Manchu forms in romanization"),
        Item.new(key: "wylie-tsing-wan-ke-mung-1855", identifier: "translationoftsi00chng", language: "eng",
                 creator: "Alexander Wylie (tr.)",
                 title: "Translation of the Ts'ing wan k'e mung, a Chinese Grammar of the Manchu Tartar " \
                        "Language; with Introductory Notes on Manchu Literature",
                 date: dated(1855), imprint: "Shanghae: London Mission Press", genre: "grammar",
                 scan: "Library of Congress",
                 note: "Wylie's English translation of Wuge's 清文啓蒙 (1730), the Manchu primer whose " \
                       "Manchu-script text the mnc-wikisource shelf carries; Manchu forms romanized"),
        *[[1, 1844], [2, 1846], [3, 1849]].map do |volume, year|
          Item.new(key: "kowalewski-dictionnaire-mongol-#{volume}-#{year}", identifier: KOWALEWSKI,
                   file: format(KOWALEWSKI_STEM, volume), language: "rus",
                   creator: "J. É. Kowalewski (О. М. Ковалевскій)",
                   title: format(KOWALEWSKI_TITLE, %w[I II III][volume - 1]),
                   date: dated(year), imprint: "Kazan: Imprimerie de l'Université", genre: "dictionary",
                   scan: "Google (Bavarian State Library copy), community upload (PDM 1.0)",
                   note: "Classical Mongolian headwords in the Uyghur-Mongolian script (garbled in the " \
                         "OCR) glossed in Russian and French — the Russian/French glosses read")
        end,
        Item.new(key: "schmidt-grammatik-mongolisch-1831", identifier: "10522293bsb", language: "deu",
                 creator: "I. J. Schmidt", title: "Grammatik der mongolischen Sprache", date: dated(1831),
                 imprint: "St. Petersburg: Kaiserliche Akademie der Wissenschaften", genre: "grammar",
                 scan: "BSB",
                 note: "the first European grammar of written Mongolian; the Mongolian-script examples " \
                       "(and the lithographed plate) are garbled in the OCR"),
        Item.new(key: "kowalewski-mongolskaja-chrestomatija-2-1837", identifier: "10572455bsb",
                 language: "rus", creator: "О. М. Ковалевскій",
                 title: "Монгольская хрестоматія, т. 2", date: dated(1837), imprint: "Kazan: University Press",
                 genre: "chrestomathy", scan: "BSB",
                 note: "Classical Mongolian readings in the native script (garbled in the OCR) with " \
                       "Russian notes"),
        Item.new(key: "pozdneev-kalmyk-russian-dictionary-1911", identifier: "pozdneev_a_kalmytsko_russkiy_slovar",
                 language: "rus", creator: "А. М. Позднѣевъ", title: "Калмыцко-русскій словарь",
                 date: dated(1911), imprint: "St Petersburg: Imperial Society for Oriental Studies",
                 genre: "dictionary", scan: "community upload",
                 note: "Written Oirat headwords in the Clear Script (garbled in the OCR) with Russian " \
                       "glosses and citation sigla (readable); the archive.org item carries no date or " \
                       "rights field and the title page's year is not legible in the OCR — 1911 is the " \
                       "print's bibliographic date"),
        Item.new(key: "julg-siddhi-kur-1866", identifier: "10250287bsb", language: "deu",
                 creator: "B. Jülg (ed. and tr.)",
                 title: "Die Märchen des Siddhi-Kür: kalmükischer Text mit deutscher Übersetzung und " \
                        "einem kalmükisch-deutschen Wörterbuch",
                 date: dated(1866), imprint: "Leipzig: F. A. Brockhaus", genre: "tales", scan: "BSB",
                 note: "the Oirat text of the Siddhi-Kür tales (Clear Script, garbled in the OCR) with " \
                       "Jülg's German translation and a Kalmyk-German glossary (readable)"),
        Item.new(key: "popov-kalmyk-grammar-1847", identifier: "10572460bsb", language: "rus",
                 creator: "А. В. Поповъ", title: "Грамматика калмыцкаго языка", date: dated(1847),
                 imprint: "Kazan: University Press", genre: "grammar", scan: "BSB",
                 note: "Russian grammar of written Kalmyk (Written Oirat); Clear Script examples garbled " \
                       "in the OCR")
      ].freeze

      # The language each volume presents — metadata only; the claim is the
      # item's prose language (see Language above).
      OBJECT_LANGUAGES = ITEMS.to_h do |item|
        code = case item.key
               when /\Akowalewski-|\Aschmidt-/ then "cmg"
               when /\Apozdneev-|\Ajulg-|\Apopov-/ then "xwo"
               else "mnc"
               end
        [item.key, code]
      end.freeze

      OCR_NOTE = "Uncorrected machine OCR (archive.org hOCR derivative), never proofread: Russian, " \
                 "English, French and German prose reads approximately (pre-reform Russian orthography " \
                 "with misread letters); romanized and Cyrillic-transcribed Manchu and Mongolian forms " \
                 "read with errors; the native vertical scripts — Manchu, Uyghur-Mongolian and the " \
                 "Oirat Clear Script — are garbled, never text. Cite the scan (ia_url)."

      MANIFEST = Nabu::SourceManifest.new(
        id: "mongolic-pd",
        name: "PD Manchu–Mongolic–Oirat reference shelf — Zakharov, Möllendorff, Amiot, Klaproth, Meadows, " \
              "Adam, Wylie, Kowalewski, Schmidt, Pozdneev, Jülg, Popov (archive.org scans, uncorrected OCR)",
        license: "Public domain: authors died 1793–1920, every print 1789–1911; archive.org items marked " \
                 "NOT_IN_COPYRIGHT or PDM 1.0 by their contributors (Google/Oxford, Google/Harvard, UC " \
                 "Libraries, a community upload of a BSB copy) or carrying no rights field (Library of " \
                 "Congress, Cornell, BSB, a community upload). Text = archive.org's uncorrected machine " \
                 "OCR (hOCR derivatives)",
        license_class: "open",
        upstream_url: "https://archive.org/details/polnyimanchzhurs00zakh",
        parser_family: "ia-hocr-text"
      )

      def self.manifest = MANIFEST

      private

      def metadata_for(item, pages, text_pages)
        super.merge("ocr_note" => OCR_NOTE, "object_language" => OBJECT_LANGUAGES.fetch(item.key))
      end
    end
  end
end
