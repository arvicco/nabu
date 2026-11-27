# frozen_string_literal: true

require_relative "ia_scan_shelf"

module Nabu
  module Adapters
    # turkic-pd — the public-domain Turkic reference shelf as archive.org
    # scans: the 19th-century editions that first put Cuman, the runiform
    # Old Turkic inscriptions and the Qutadgu Bilig into print. Mechanics:
    # Nabu::Adapters::IaScanShelf (page grain over the hOCR derivative pair;
    # UNCORRECTED OCR declared on every document — the slavistics-pd /
    # africa-pd / mongolic-pd mold).
    #
    # == The census (2026-11-27; ITEMS below)
    #
    # Every item's archive.org metadata read first-hand and every page index
    # fetched and parsed through IaHocrText: 4 items, each carrying the hOCR
    # derivative pair (searchtext + pageindex) beside its djvu.txt, PDF and
    # page-image derivatives.
    #
    # - Kuun's Codex Cumanicus (Budapest 1880; codexcumanicusbi00kuunuoft,
    #   Robarts/University of Toronto scan): 558 hOCR pages (556 images),
    #   538 with text — the Latin–Persian–Cuman glossary of the Venice
    #   codex and its Cuman texts, Latin prolegomena, notes and glossaries.
    #   The first Cuman text in the library.
    # - Thomsen's Inscriptions de l'Orkhon déchiffrées (Helsingfors 1896,
    #   Mémoires de la Société Finno-Ougrienne V; inscriptionsdel00thomgoog,
    #   Google/Michigan scan): 230 pages, 227 with text — the decipherment.
    # - Radloff's Die alttürkischen Inschriften der Mongolei
    #   (bub_gb_sVVDAQAAMAAJ, Google/UC scan): 1,038 pages, 1,029 with text.
    #   The scan binds the whole series — the first part (1895; the title
    #   page at hOCR page 7), the Neue Folge (1897, with Barthold's Die
    #   historische Bedeutung der alttürkischen Inschriften; page 486) and
    #   the Zweite Folge (1899: Radloff's Tonjukuk inscription, Hirth's
    #   Nachworte, Barthold's Die alttürkischen Inschriften und die
    #   arabischen Quellen; page 714) — read off the title pages, so the
    #   document is dated 1895–1899 and names all three authors. One
    #   document: the item is one hOCR pair and the shelf's grain is the
    #   pair (the parts' boundaries ride the note, never a split).
    # - Vámbéry's Uigurische Sprachmonumente und das Kudatku Bilik
    #   (Innsbruck 1870; uigurischesprach00vmuoft, Robarts/Toronto scan):
    #   288 pages, 275 with text — the first edition of any part of the
    #   Qutadgu Bilig, from the Vienna (Herat) Uyghur-script manuscript.
    #
    # Census total: 4 docs / 2,069 passages (the non-blank hOCR pages).
    #
    # Held back, with reasons (never fetched): Şemseddin Sami's Kamus-i
    # Türki (kamusitrki00emse — the Arabic-script OCR is noise, nothing
    # searchable); Redhouse's Turkish and English Lexicon (1890 — the scan's
    # rights were not checked, so it stays out until they are); the Wikimedia
    # Commons facsimile of the Dīwān Lughāt al-Turk (page images only, no
    # text derivative — out of this shelf's reach).
    #
    # == License
    #
    # Public domain: every author died by 1930 (Vámbéry 1913, Kuun 1905,
    # Radloff 1918, Thomsen 1927, Hirth 1927, Barthold 1930) and every print
    # predates 1931 (1870–1899). Rights fields as read 2026-11-27: Thomsen
    # and Vámbéry NOT_IN_COPYRIGHT; Radloff the Public Domain Mark 1.0
    # (licenseurl); Kuun no rights field (a Toronto scan) — its status rests
    # on the dates. The Google-digitized items carry Google's
    # usage-guidelines pages — a request, not a license term, ingested
    # verbatim like any page.
    #
    # == Language
    #
    # Each document claims the language its PROSE is written in — the
    # reference-shelf posture: Latin (Kuun), French (Thomsen), German
    # (Radloff, Vámbéry). The language each volume presents rides metadata
    # "object_language":
    #
    # - qwm (Cuman) for Kuun — no registry node yet (a registry change is in
    #   flight); metadata only, never a claim, so nothing waits on it.
    # - otk (Old Turkic) for Thomsen and Radloff — the runiform corpus.
    # - xqa (Karakhanid) for Vámbéry, decided from the book itself: the text
    #   it edits is the Qutadgu Bilig, which Vámbéry dates by its own
    #   colophon verses to 463 AH (1069/70 — the Karakhanid court of
    #   Kashgar). His "uigurisch" names the script of the Herat copy and the
    #   1870 understanding of the language; he himself sets the other
    #   Uyghur-script documents apart as Chagatai in Uyghur letters, the
    #   Kudatku Bilik some four hundred years older. The registry places the
    #   Qutadgu Bilig at xqa (band 1000–1200, its note names the work), so
    #   xqa, not oui. Coarse at document grain, declared: the introduction's
    #   survey of Uyghur-script monuments rides the same code.
    #
    # == What the OCR keeps (and loses)
    #
    # Read across every item: the Latin, French and German prose reads
    # approximately; Kuun's Latin-script Cuman and Persian glossary columns
    # and Vámbéry's romanized transcription read with errors; the runiform
    # script (Thomsen, Radloff), Radloff's Cyrillic-based transcriptions and
    # the Uyghur script (Vámbéry) are garbled, never text. Declared on every
    # document (OCR_NOTE) and in the source dossier.
    class TurkicPd < IaScanShelf
      ITEMS = [
        Item.new(key: "kuun-codex-cumanicus-1880", identifier: "codexcumanicusbi00kuunuoft", language: "lat",
                 creator: "Géza Kuun (ed.)",
                 title: "Codex Cumanicus bibliothecae ad templum Divi Marci Venetiarum, primum ex integro " \
                        "edidit, prolegomenis, notis et compluribus glossariis instruxit",
                 date: dated(1880), imprint: "Budapest: Academia Scientiarum Hungarica",
                 genre: "glossary edition", scan: "University of Toronto (Robarts)",
                 note: "the Venice codex's Latin–Persian–Cuman glossary and its Cuman texts in Latin " \
                       "script (searchable, with OCR errors), with Kuun's Latin prolegomena, notes and " \
                       "glossaries"),
        Item.new(key: "thomsen-inscriptions-orkhon-1896", identifier: "inscriptionsdel00thomgoog",
                 language: "fra", creator: "Vilhelm Thomsen",
                 title: "Inscriptions de l'Orkhon déchiffrées", date: dated(1896),
                 imprint: "Helsingfors: Imprimerie de la Société de littérature finnoise",
                 series: "Mémoires de la Société Finno-Ougrienne V", genre: "inscription study",
                 scan: "Google (University of Michigan copy)",
                 note: "the decipherment of the runiform script, with transcription and French " \
                       "translation of the Orkhon monuments; the runiform characters are garbled in the OCR"),
        Item.new(key: "radloff-alttuerkische-inschriften-1895-99", identifier: "bub_gb_sVVDAQAAMAAJ",
                 language: "deu", creator: "W. Radloff; W. Barthold; F. Hirth",
                 title: "Die alttürkischen Inschriften der Mongolei (with the Neue Folge and the Zweite Folge)",
                 date: dated(1895, 1899), imprint: "St Petersburg: Kaiserliche Akademie der Wissenschaften",
                 genre: "inscription study", scan: "Google (University of California copy)",
                 note: "the scan binds the whole series: the first part (1895; texts, transcription and " \
                       "translation of the Orkhon and Yenisei inscriptions), the Neue Folge (1897, from " \
                       "hOCR page 486: Radloff's grammar of the inscriptions and glossary, Barthold's Die " \
                       "historische Bedeutung der alttürkischen Inschriften) and the Zweite Folge (1899, " \
                       "from page 714: the Tonjukuk inscription, Hirth's Nachworte zur Inschrift des " \
                       "Tonjukuk, Barthold's Die alttürkischen Inschriften und die arabischen Quellen); " \
                       "the German reads, the runiform texts and the Cyrillic-based transcriptions are " \
                       "garbled in the OCR"),
        Item.new(key: "vambery-kudatku-bilik-1870", identifier: "uigurischesprach00vmuoft", language: "deu",
                 creator: "Hermann Vámbéry",
                 title: "Uigurische Sprachmonumente und das Kudatku Bilik: uigurischer Text mit " \
                        "Transscription und Übersetzung nebst einem uigurisch-deutschen Wörterbuche",
                 date: dated(1870),
                 imprint: "Innsbruck: Wagner'sche Universitäts-Buchdruckerei (Leipzig: F. A. Brockhaus)",
                 genre: "text edition", scan: "University of Toronto (Robarts)",
                 note: "the first edition of the Qutadgu Bilig (Yusuf Khass Hajib, 1069/70) from the " \
                       "Vienna Uyghur-script manuscript: romanized transcription (searchable, with OCR " \
                       "errors), German translation and a Uyghur-German glossary; the Uyghur script and " \
                       "the lithographed facsimile are garbled in the OCR")
      ].freeze

      # The language each volume presents — metadata only; the claim is the
      # item's prose language (see Language above).
      OBJECT_LANGUAGES = {
        "kuun-codex-cumanicus-1880" => "qwm",
        "thomsen-inscriptions-orkhon-1896" => "otk",
        "radloff-alttuerkische-inschriften-1895-99" => "otk",
        "vambery-kudatku-bilik-1870" => "xqa"
      }.freeze

      OCR_NOTE = "Uncorrected machine OCR (archive.org hOCR derivative), never proofread: Latin, French " \
                 "and German prose reads approximately; Latin-script Cuman and Persian glossary forms and " \
                 "romanized Turkic transcriptions read with errors; the runiform script, Radloff's " \
                 "Cyrillic-based transcriptions and the Uyghur script are garbled, never text. Cite the " \
                 "scan (ia_url)."

      MANIFEST = Nabu::SourceManifest.new(
        id: "turkic-pd",
        name: "PD Turkic reference shelf — Kuun's Codex Cumanicus, Thomsen, Radloff, Vámbéry's Kudatku " \
              "Bilik (archive.org scans, uncorrected OCR)",
        license: "Public domain: authors died 1905–1930, every print 1870–1899; archive.org items marked " \
                 "NOT_IN_COPYRIGHT (Thomsen, Vámbéry) or the Public Domain Mark 1.0 (Radloff), or carrying " \
                 "no rights field (Kuun, a University of Toronto scan). Text = archive.org's uncorrected " \
                 "machine OCR (hOCR derivatives)",
        license_class: "open",
        upstream_url: "https://archive.org/details/codexcumanicusbi00kuunuoft",
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
