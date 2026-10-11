# frozen_string_literal: true

require_relative "ia_scan_shelf"

module Nabu
  module Adapters
    # archiv-slav-phil (Q105) — Jagić's Archiv für slavische Philologie
    # (Berlin: Weidmann, 1876–1929), the field's journal of record, as the
    # archive.org scan run: one document per volume, page grain over the
    # hOCR derivative pair, UNCORRECTED OCR declared (Nabu::Adapters::
    # IaScanShelf, the slavistics-pd mechanics verbatim).
    #
    # == The census (2026-10-11)
    #
    # The 25 items titled exactly "Archiv für slavische Philologie":
    #   ADOPTED — 24 volumes, every one carrying the hOCR pair, every page
    #   index contiguous, measured wordlike share 0.72–0.84:
    #     Bd. 16–35 (1894–1914) — University of Toronto (Robarts) scans,
    #       NOT_IN_COPYRIGHT; the year from each title page.
    #     Bd. 1, 7, 8, 9 (1876, 1884–86) — user uploads (Bd. 1 marked PDM
    #       1.0) re-OCRed with Tesseract 5.
    #   SKIPPED — Pastrnek's Bibliographische Übersicht 1876–1891 (the
    #     Archiv's general register, bub_gb_6z5FAAAAYAAJ): a Google scan
    #     without hOCR derivatives (no page grain).
    # The 31 Google scans a looser title query adds ("bub_gb_…",
    # "archivfrslavisc…goog"): their metadata carries no volume number
    # (every one dated 1876), so each was keyed by its own title page
    # ("DRITTER BAND … BERLIN … 1879"): 9 fill the run's gaps and are
    # ADOPTED (GOOGLE below, wordlike 0.75–0.82); 17 duplicate held
    # volumes (Bd. 4, 9, 12, 21–25, 29), 4 name no volume on a legible
    # title page (archivfrslavisc06/07unkngoog, bub_gb_cmgoAAAAYAAJ,
    # bub_gb_NGgoAAAAYAAJ) and archivfrslavisc04unkngoog answers no
    # metadata at all — not adopted. Held run: Bd. 1, 3–12, 14–35;
    # Bd. 2, 13 and 36–42 (1916–1929) are not on archive.org as
    # identifiable scans.
    #
    # Reprint scans: Bd. 1, 3, 8, 9 and 11 are scans of Weidmann's 1964
    # facsimile reprint ("Reprint edition 1964" on the licence page) — the
    # text is the original volume's, the date stays the original's, the
    # reprint rides the note.
    #
    # == License
    #
    # Every adopted volume was published 1876–1914 (public domain in the
    # US, pre-1931). The EU term runs per ARTICLE (author's death + 70):
    # most contributors died long before 1955, but the later volumes carry
    # a few younger scholars — not audited article by article; declared
    # here and in the manifest, never silently assumed.
    #
    # == Language
    #
    # deu — the journal's language (Jagić's editorial policy: German, with
    # Russian, Serbo-Croatian and other Slavic contributions mixed in;
    # deliberately coarse, declared). Scholarship ABOUT Slavic.
    class ArchivSlavPhil < IaScanShelf
      TITLE = "Archiv für slavische Philologie"
      EDITOR = "Vatroslav Jagić (ed.)"
      IMPRINT = "Berlin: Weidmannsche Buchhandlung"
      TORONTO = "University of Toronto (Robarts)"
      REPRINT_NOTE = "scan of Weidmann's 1964 facsimile reprint (\"Reprint edition 1964\" on the " \
                     "licence page); text and date are the original volume's"

      # Bd. 16–35: the title-page year of each Toronto volume.
      TORONTO_YEARS = {
        16 => 1894, 17 => 1895, 18 => 1896, 19 => 1897, 20 => 1898, 21 => 1899, 22 => 1900,
        23 => 1901, 24 => 1902, 25 => 1903, 26 => 1904, 27 => 1905, 28 => 1906, 29 => 1907,
        30 => 1909, 31 => 1910, 32 => 1911, 33 => 1912, 34 => 1913, 35 => 1914
      }.freeze

      # The user-uploaded early volumes: [volume, year, reprint scan?].
      EARLY = [[1, 1876, true], [7, 1884, false], [8, 1885, true], [9, 1886, true]].freeze

      # The Google gap-fillers, each keyed by its own title page:
      # volume => [identifier, title-page year, library, reprint scan?].
      GOOGLE = {
        3 => ["bub_gb_PMFWAAAAIAAJ", 1879, "University of California", true],
        4 => ["archivfrslavisc01pastgoog", 1880, "Harvard University", false],
        5 => ["archivfurslavis00jagigoog", 1881, "Oxford University", false],
        6 => ["archivfrslavisc05unkngoog", 1882, "Harvard University", false],
        10 => ["bub_gb_gwIFAAAAYAAJ", 1887, "Harvard University", false],
        11 => ["bub_gb_TtZWAAAAIAAJ", 1888, "University of California", true],
        12 => ["archivfrslavisc03unkngoog", 1890, "New York Public Library", false],
        14 => ["archivfrslavisc00unkngoog", 1892, "Harvard University", false],
        15 => ["bub_gb_MGkoAAAAYAAJ", 1893, "New York Public Library", false]
      }.freeze

      def self.volume_item(volume, year, identifier:, file:, scan:, note: nil)
        Item.new(key: "bd#{volume.to_s.rjust(2, '0')}-#{year}", identifier: identifier, file: file,
                 language: "deu", creator: EDITOR, title: "#{TITLE}, Bd. #{volume}", date: dated(year),
                 imprint: IMPRINT, genre: "journal volume", series: TITLE, scan: scan, note: note)
      end

      ITEMS = (
        EARLY.map do |volume, year, reprint|
          volume_item(volume, year, identifier: "archiv-fur-slavische-philologie-v-#{volume}-#{year}",
                                    file: "Archiv fur slavische Philologie v #{volume} #{year}",
                                    scan: "user upload, re-OCRed (Tesseract 5)",
                                    note: (REPRINT_NOTE if reprint))
        end +
        GOOGLE.map do |volume, (identifier, year, library, reprint)|
          volume_item(volume, year, identifier: identifier, file: identifier,
                                    scan: "Google (#{library} copy)", note: (REPRINT_NOTE if reprint))
        end +
        TORONTO_YEARS.map do |volume, year|
          volume_item(volume, year, identifier: "archivfrslavis#{volume}berluoft",
                                    file: "archivfrslavis#{volume}berluoft", scan: TORONTO)
        end
      ).sort_by(&:key).freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "archiv-slav-phil",
        name: "Archiv für slavische Philologie, Bd. 1–35 (archive.org scans, uncorrected OCR)",
        license: "Public domain in the US (published 1876–1914, pre-1931); the EU term runs per " \
                 "article and was not audited article by article. archive.org items: Toronto " \
                 "volumes NOT_IN_COPYRIGHT, Bd. 1 PDM 1.0, Google scans under Google's public-domain " \
                 "statement. Text = archive.org's uncorrected machine OCR (hOCR derivatives)",
        license_class: "open",
        upstream_url: "https://archive.org/details/archivfrslavis16berluoft",
        parser_family: "ia-hocr-text"
      )

      def self.manifest = MANIFEST
    end
  end
end
