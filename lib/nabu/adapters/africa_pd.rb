# frozen_string_literal: true

require_relative "ia_scan_shelf"

module Nabu
  module Adapters
    # africa-pd — the public-domain African-languages reference shelf
    # (P124-1) as archive.org scans: Griffith's edition of the Old Nubian
    # texts (1913); the Swahili four — Steere's Swahili Tales (1870),
    # Taylor's African Aphorisms (1891), Büttner's Anthologie aus der
    # Suaheli-Litteratur (1894), Velten's Prosa und Poesie der Suaheli
    # (1907); the Hausa two — Schön's Magána Hausa (1885) and Robinson's
    # Specimens of Hausa Literature (1896); Hanoteau's Tamachek' grammar
    # (1860) and Kabyle popular poetry (1867); Koelle's Vai grammar (1854).
    # Mechanics: Nabu::Adapters::IaScanShelf (page grain over the hOCR
    # derivative pair; UNCORRECTED OCR declared on every document — the
    # slavistics-pd mold).
    #
    # == The census (2026-10-13; ITEMS below)
    #
    # Per work the scan carrying the hOCR derivative pair with the best
    # measured OCR (the share of whitespace tokens that read as words:
    # 0.62 Griffith – 0.92 Schön) whose title page matches the work.
    # Skipped, with reasons: scans with no hOCR pair (Büttner's
    # bub_gb_ObtFAQAAIAAJ, Velten's Google copy, Schön's Michigan copy,
    # Hanoteau's Harvard Google copy of 1860, Koelle's Oxford copy);
    # Steere's National Library of Scotland copy (a CC BY-NC-SA licenseurl
    # on the item — the Oxford copy carries none); Koelle's Toronto copy
    # (the 1968 Gregg International reprint — the UC copy is the 1854
    # print); the trailing-space-named second copy of Hanoteau's Poésies.
    # The survey's NOT-PD exclusions stay out: Chabot's Recueil des
    # inscriptions libyques, Plumley/Browne's Qasr Ibrim texts, Foucauld's
    # 1951 Tuareg dictionary.
    #
    # == License
    #
    # Public domain: every author died by 1935 (Steere 1882, Schön 1889,
    # Büttner 1893, Hanoteau 1897, Koelle 1902, Robinson 1925, Taylor 1927,
    # Griffith 1934, Velten 1935) and every print predates 1931. The scans
    # are archive.org items marked NOT_IN_COPYRIGHT or PDM 1.0 by their
    # contributors, or (Velten's UNC scan, the BSB Schön, the community
    # upload of Taylor's Harvard copy) carry no rights field — the works'
    # status rests on those dates. Google-digitized items carry Google's
    # usage-guidelines page(s) — a request, not a license term, ingested
    # verbatim like any page.
    #
    # == Language
    #
    # Each document claims the language its PROSE is written in — the
    # reference-shelf posture: the bilingual text editions (Steere, Taylor,
    # Schön, Robinson: English; Büttner: German; Hanoteau's Poésies:
    # French) and the grammars (Griffith, Koelle: English; Hanoteau's
    # Tamachek': French) claim their editorial language, with the African
    # language they present riding metadata "object_language"; ONLY Velten's
    # reader — Swahili text throughout, German footnotes — claims sw. The
    # African-language matter in Latin transcription reads in the OCR with
    # errors; Old Nubian (Coptic-derived alphabet), Arabic-script (Ajami)
    # facsimiles, Tifinagh and the Vai syllabary are garbled — declared.
    # Coarse at document grain, declared: a bilingual volume's
    # African-language pages ride its editorial-language claim.
    class AfricaPd < IaScanShelf
      ITEMS = [
        Item.new(key: "griffith-nubian-texts-1913", identifier: "nubiantextsofchr00grif", language: "eng",
                 creator: "F. Ll. Griffith (ed.)", title: "The Nubian Texts of the Christian Period",
                 date: dated(1913),
                 imprint: "Berlin: Verlag der Königl. Akademie der Wissenschaften, in Commission bei Georg Reimer",
                 series: "Abhandlungen der Königl. Preuss. Akademie der Wissenschaften, Jahrgang 1913, " \
                         "Phil.-hist. Classe, Nr. 8",
                 genre: "text edition", scan: "University of California Libraries",
                 note: "the Old Nubian manuscripts and graffiti with English translation, grammar and " \
                       "vocabulary — the Old Nubian (Coptic-derived alphabet) is garbled in the OCR"),
        Item.new(key: "steere-swahili-tales-1870", identifier: "swahilitalesast00steegoog", language: "eng",
                 creator: "Edward Steere",
                 title: "Swahili Tales, as Told by Natives of Zanzibar, with an English Translation",
                 date: dated(1870), imprint: "London: Bell & Daldy", genre: "text edition",
                 scan: "Google (Oxford University copy)",
                 note: "Swahili text facing Steere's English translation"),
        Item.new(key: "taylor-african-aphorisms-1891", identifier: "AfricanAphorisms", file: "African_aphorisms",
                 language: "eng", creator: "W. E. Taylor",
                 title: "African Aphorisms; or, Saws from Swahili-Land", date: dated(1891),
                 imprint: "London: Society for Promoting Christian Knowledge", genre: "proverb collection",
                 scan: "Google (Harvard College Library copy), community upload",
                 note: "Swahili proverbs, each with Taylor's English translation and commentary; the " \
                       "archive.org item carries no creator, date or rights field — its title page " \
                       "(London: SPCK, 1891) identifies it"),
        Item.new(key: "buttner-anthologie-suaheli-1894", identifier: "anthologieausde00btgoog", language: "deu",
                 creator: "C. G. Büttner",
                 title: "Anthologie aus der Suaheli-Litteratur (Gedichte und Geschichten der Suaheli)",
                 date: dated(1894), imprint: "Berlin: Emil Felber", genre: "anthology",
                 scan: "Google (Harvard University copy)",
                 note: "Swahili poems and stories (Erster Theil: Texte) with Büttner's German " \
                       "translations; archive.org's date field (1970, a Kraus reprint) does not describe " \
                       "this scan — its title page reads Berlin: Felber, 1894"),
        Item.new(key: "velten-prosa-poesie-suaheli-1907", identifier: "prosaundpoesiede00velt", language: "sw",
                 creator: "C. Velten", title: "Prosa und Poesie der Suaheli", date: dated(1907),
                 imprint: "Berlin: im Selbstverlag des Verfassers", genre: "reader",
                 scan: "University of North Carolina at Chapel Hill",
                 note: "Swahili prose and verse (tales, travel accounts, local histories, utenzi) with " \
                       "German footnotes — the shelf's one volume whose body is the African-language text"),
        Item.new(key: "schon-magana-hausa-1885", identifier: "11679913bsb", language: "eng",
                 creator: "J. F. Schön",
                 title: "Magána Hausa: Native Literature, or Proverbs, Tales, Fables and Historical " \
                        "Fragments in the Hausa Language, to which is added a Translation in English",
                 date: dated(1885), imprint: "London: Society for Promoting Christian Knowledge",
                 genre: "text edition", scan: "BSB",
                 note: "the Hausa texts in Schön's Latin transcription, followed by the English translation"),
        Item.new(key: "robinson-specimens-hausa-1896", identifier: "specimensofhausa00robirich", language: "eng",
                 creator: "Charles Henry Robinson", title: "Specimens of Hausa Literature", date: dated(1896),
                 imprint: "Cambridge: at the University Press", genre: "text edition",
                 scan: "University of California Libraries",
                 note: "Hausa Ajami poems in facsimile with transliteration, English translation and notes " \
                       "— the Arabic-script facsimiles are garbled in the OCR"),
        Item.new(key: "hanoteau-grammaire-tamachek-1860",
                 identifier: "hanoteau-essai-de-grammaire-de-la-langue-tamachek-1860-copy-c",
                 file: "Hanoteau, Essai de grammaire de la langue tamachek (1860) - copy C", language: "fra",
                 creator: "A. Hanoteau",
                 title: "Essai de grammaire de la langue tamachek', renfermant les principes du langage " \
                        "parlé par les Imouchar' ou Touareg",
                 date: dated(1860), imprint: "Paris: Imprimerie impériale", genre: "grammar",
                 scan: "Harvard University, Peabody Museum library copy (PDM 1.0)",
                 note: "French grammar of Tuareg with conversations in Tamachek' and Tifinagh facsimiles " \
                       "(the Tifinagh is garbled in the OCR)"),
        Item.new(key: "hanoteau-poesies-kabylie-1867", identifier: "posiespopulaire00hanogoog", language: "fra",
                 creator: "A. Hanoteau (ed. and tr.)",
                 title: "Poésies populaires de la Kabylie du Jurjura: texte kabyle et traduction",
                 date: dated(1867), imprint: "Paris: Imprimerie impériale", genre: "text edition",
                 scan: "Google (University of Michigan copy)",
                 note: "Kabyle verse in Latin transcription (beside its Arabic-script version, garbled in " \
                       "the OCR) with French translation and notes"),
        Item.new(key: "koelle-vei-grammar-1854", identifier: "outlinesofgramma00koelrich", language: "eng",
                 creator: "S. W. Koelle",
                 title: "Outlines of a Grammar of the Vei Language, together with a Vei-English Vocabulary, " \
                        "and an Account of the Discovery and Nature of the Vei Mode of Syllabic Writing",
                 date: dated(1854), imprint: "London: Church Missionary House", genre: "grammar",
                 scan: "University of California Libraries",
                 note: "the Vei forms in Koelle's Latin transcription; the Vai syllabary plates are garbled " \
                       "in the OCR")
      ].freeze

      # The African language each volume presents (ISO 639) — metadata
      # only; the claim is the item's language (see Language above).
      # Hanoteau's Tamachek' (the Ahaggar Tuareg of the Imouchar') rides
      # the tmh macrolanguage, declared coarse.
      OBJECT_LANGUAGES = {
        "griffith-nubian-texts-1913" => "onw", "steere-swahili-tales-1870" => "sw",
        "taylor-african-aphorisms-1891" => "sw", "buttner-anthologie-suaheli-1894" => "sw",
        "velten-prosa-poesie-suaheli-1907" => "sw", "schon-magana-hausa-1885" => "ha",
        "robinson-specimens-hausa-1896" => "ha", "hanoteau-grammaire-tamachek-1860" => "tmh",
        "hanoteau-poesies-kabylie-1867" => "kab", "koelle-vei-grammar-1854" => "vai"
      }.freeze

      OCR_NOTE = "Uncorrected machine OCR (archive.org hOCR derivative), never proofread: English, German " \
                 "and French prose reads approximately; African-language text in Latin transcription " \
                 "reads with errors (special letters and diacritics); Old Nubian, Arabic-script (Ajami), " \
                 "Tifinagh and Vai-syllabary matter is garbled. Cite the scan (ia_url)."

      MANIFEST = Nabu::SourceManifest.new(
        id: "africa-pd",
        name: "PD African-languages reference shelf — Griffith, Steere, Taylor, Büttner, Velten, Schön, " \
              "Robinson, Hanoteau, Koelle (archive.org scans, uncorrected OCR)",
        license: "Public domain: authors died 1882–1935, every print 1854–1913; archive.org items marked " \
                 "NOT_IN_COPYRIGHT or PDM 1.0 by their contributors (UC Libraries, Google/Oxford, " \
                 "Google/Harvard, Google/Michigan, Harvard Peabody) or carrying no rights field (UNC, BSB, " \
                 "a community upload of a Harvard copy). Text = archive.org's uncorrected machine OCR " \
                 "(hOCR derivatives)",
        license_class: "open",
        upstream_url: "https://archive.org/details/nubiantextsofchr00grif",
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
