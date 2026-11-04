# frozen_string_literal: true

require_relative "ia_scan_shelf"

module Nabu
  module Adapters
    # analecta-hymnica — the Analecta Hymnica Medii Aevi (Leipzig: Reisland,
    # 1886–1922; eds. Guido Maria Dreves, Clemens Blume, Henry Marriott
    # Bannister), the 55-volume corpus of medieval Latin hymnody, as the
    # archive.org scan run: one document per volume, page grain over the
    # hOCR derivative pair, UNCORRECTED OCR declared (Nabu::Adapters::
    # IaScanShelf, the slavistics-pd / archiv-slav-phil mechanics).
    #
    # == The census (2026-11-04; VOLUMES below is the volume -> item table)
    #
    # archive.org holds 169 items of the series: the title query
    # "analecta hymnica" answers 82 (74 series items + 8 other works,
    # NOT_THE_SERIES), and creator/subtitle queries (Dreves, Blume, "Hymni
    # inediti", "Sequentiae ineditae", "Historiae rhythmicae", "Pia
    # dictamina", ...) add 95 more series items catalogued under a volume's
    # subtitle. The rule: ONE single-volume item per volume carrying the
    # hOCR pair, its volume confirmed by its own title page. The PIMS–
    # University of Toronto run is the one contributor complete in single
    # volumes with hOCR — Bd. 1–41 as analectahymnicamNNdrev, Bd. 42–55 as
    # hymniineditilituNNdrev (catalogued under Bd. 4's subtitle) — and is
    # ADOPTED whole (55); every title page read 2026-11-04 (volume number,
    # special title, editor, year). Bd. 50 is held twice by PIMS: the two
    # tie on measured OCR (wordlike 0.76) and analectahymnicam50drevuoft
    # carries more text pages (690 vs 672). Measured wordlike share of the
    # adopted run: 0.66 (Bd. 54) – 0.89 (Bd. 6).
    #
    # NOT adopted (114 series items, REJECTED by reason):
    #   no_hocr (72) — no hOCR derivative pair, so no page grain: the
    #     Toronto "drevuoft"/"blumuoft" catalogue run (54), the Google/NYPL
    #     and Google/Harvard copies without derivatives (16), two Million
    #     Books Project copies.
    #   bundle (20) — two or three volumes in one item, one hOCR stream
    #     across them: the Princeton Theological Seminary run (18 items,
    #     "v. 1-3" … "v. 54-55"), the two Robarts "Hymnographi Latini"
    #     items (Bd. 48 + 50 bound, 1,236 scan pages).
    #   other_copy (20) — further single copies of held volumes: 19
    #     Google scans (no volume field; usage-guideline leaves; several
    #     Harvard items bind two volumes) and Princeton's analec00drev
    #     (Bd. 10, wordlike 0.79 vs the adopted 0.78 — within the
    #     measurement's noise; the run stays one contributor's).
    #   folder_upload (1) — analecta-hymnica-medii-aevi, a community
    #     upload of all 55 volumes as PDFs in one item folder: the same
    #     PIMS scans (PDF sizes match) re-OCRed by archive.org with
    #     Tesseract 5 (lat+deu), measuring 0.00–0.05 better on most
    #     volumes — but volume identity rests on file names alone and one
    #     pair is swapped ("Vol. 28" is Bd. 48 by its title page, "Vol. 48"
    #     is Bd. 28), the item carries a dark/un-dark curation history
    #     ("Undarked During Discussion", 2025-12-30) and no contributing
    #     library. The declared alternative, not the held text.
    #   duplicate (1) — hymniineditilitu50drev (Bd. 50, above).
    #
    # == License
    #
    # Public domain: every volume was printed 1886–1922 (pre-1931, US),
    # and every editor died more than 70 years ago (Dreves †1909,
    # Bannister †1919, Blume †1932 — the EU term ended 2002). The PIMS
    # items carry no rights field; the works' status rests on those dates.
    #
    # == Language, dating, places
    #
    # lat — the hymn texts are the volumes' body; the editors' prefaces,
    # introductions and apparatus are German (coarse at document grain,
    # declared). The lect stage rides config/lect_overrides.yml (lat:med,
    # approximation — the series' own scope "medii aevi"; Bd. 50–52 reach
    # back to the 4th century and the Reimgebete/Psalterien volumes forward
    # to the 15th–16th). The date is the volume's PRINT year, labeled
    # class "edition" (the hymns are medieval; their per-hymn dating lives
    # in the uncorrected apparatus, not mined). The imprint (Leipzig)
    # rides metadata only; the provenance some special titles name
    # (Moissac, Limoges, Bohemia, Spain, Naples, Wessobrunn, Lilienfeld)
    # stays in the title — a place claim beside a print year would mix two
    # different objects (declared coarse).
    class AnalectaHymnica < IaScanShelf
      SERIES = "Analecta Hymnica Medii Aevi"
      DREVES = "Guido Maria Dreves (ed.)"
      BLUME = "Clemens Blume (ed.)"
      BANNISTER = "Henry Marriott Bannister (ed.)"
      BLUME_BANNISTER = "Clemens Blume and Henry Marriott Bannister (eds.)"
      FUES = "Leipzig: Fues's Verlag (R. Reisland)"
      REISLAND = "Leipzig: O. R. Reisland"
      PIMS = "PIMS – University of Toronto"

      HI = "Hymni inediti. Liturgische Hymnen des Mittelalters"
      SI = "Sequentiae ineditae. Liturgische Prosen des Mittelalters"
      HR = "Historiae rhythmicae. Liturgische Reimofficien des Mittelalters"
      PD = "Pia dictamina. Reimgebete und Leselieder des Mittelalters"
      CM = "Cantiones et muteti. Lieder und Motetten des Mittelalters"
      PR = "Psalteria rhythmica. Gereimte Psalterien des Mittelalters"
      TG = "Tropi graduales. Tropen des Missale im Mittelalter"
      HL = "Hymnographi Latini. Lateinische Hymnendichter des Mittelalters"
      TH = "Thesauri hymnologici hymnarium. Die Hymnen des Thesaurus hymnologicus H. A. Daniels " \
           "und anderer Hymnen-Ausgaben"
      TP = "Thesauri hymnologici prosarium. Die Sequenzen des Thesaurus hymnologicus H. A. Daniels " \
           "und anderer Sequenzenausgaben"

      # volume => [print year, special title (the volume's own title page,
      # spelling normalized from the OCR), editor, genre]. Composite
      # volumes (14, 41, 45) name both parts.
      VOLUMES = {
        1 => [1886, "Cantiones Bohemicae. Leiche, Lieder und Rufe des 13., 14. und 15. Jahrhunderts",
              DREVES, "songs"],
        2 => [1888, "Hymnarius Moissiacensis. Das Hymnar der Abtei Moissac im 10. Jahrhundert; im " \
                    "Anhange: Carmina scholarium Campensium, Cantiones Vissegradenses", DREVES, "hymnary"],
        3 => [1888, "Conradus Gemnicensis. Konrads von Haimburg und seiner Nachahmer, Alberts von Prag " \
                    "und Ulrichs von Wessobrunn, Reimgebete und Leselieder", DREVES, "rhymed prayers"],
        4 => [1888, HI, DREVES, "hymns"],
        5 => [1889, "#{HR}, Erste Folge", DREVES, "rhymed offices"],
        6 => [1889, "Udalricus Wessofontanus. Ulrich Stöcklins von Rottach, Abts zu Wessobrunn " \
                    "1438–1443, Reimgebete und Leselieder", DREVES, "rhymed prayers"],
        7 => [1889, "Prosarium Lemovicense. Die Prosen der Abtei St. Martial zu Limoges, aus Troparien " \
                    "des 10., 11. und 12. Jahrhunderts", DREVES, "sequences"],
        8 => [1890, "#{SI}, Erste Folge", DREVES, "sequences"],
        9 => [1890, "#{SI}, Zweite Folge", DREVES, "sequences"],
        10 => [1891, "#{SI}, Dritte Folge", DREVES, "sequences"],
        11 => [1891, "#{HI}, Zweite Folge", DREVES, "hymns"],
        12 => [1892, "#{HI}, Dritte Folge", DREVES, "hymns"],
        13 => [1892, "#{HR}, Zweite Folge", DREVES, "rhymed offices"],
        14 => [1893, "XIVa: Hymnarius Severinianus. Das Hymnar der Abtei S. Severin in Neapel; XIVb: " \
                     "Orricus Scacabarotius. Origo Scaccabarozzis Liber Officiorum", DREVES, "hymnary"],
        15 => [1893, "#{PD}, Erste Folge", DREVES, "rhymed prayers"],
        16 => [1894, "Hymnodia Hiberica. Spanische Hymnen des Mittelalters", DREVES, "hymns"],
        17 => [1894, "Hymnodia Hiberica. Liturgische Reimofficien aus spanischen Brevieren; im Anhange: " \
                     "Carmina Compostellana", DREVES, "rhymed offices"],
        18 => [1894, "#{HR}, Dritte Folge", DREVES, "rhymed offices"],
        19 => [1895, "#{HI}, Vierte Folge", DREVES, "hymns"],
        20 => [1895, "#{CM}, Erste Folge: Cantiones natalitiae, partheniae", DREVES, "songs"],
        21 => [1895, "#{CM}, Zweite Folge: Cantiones festivae, morales, variae", DREVES, "songs"],
        22 => [1895, "#{HI}, Fünfte Folge", DREVES, "hymns"],
        23 => [1896, "#{HI}, Sechste Folge", DREVES, "hymns"],
        24 => [1896, "#{HR}, Vierte Folge", DREVES, "rhymed offices"],
        25 => [1897, "#{HR}, Fünfte Folge", BLUME, "rhymed offices"],
        26 => [1897, "#{HR}, Sechste Folge", DREVES, "rhymed offices"],
        27 => [1897, "Hymnodia Gotica. Die mozarabischen Hymnen des alt-spanischen Ritus", BLUME, "hymns"],
        28 => [1898, "#{HR}, Siebente Folge", DREVES, "rhymed offices"],
        29 => [1898, "#{PD}, Zweite Folge", BLUME, "rhymed prayers"],
        30 => [1898, "#{PD}, Dritte Folge: Stunden- und Glossen-Lieder", DREVES, "rhymed prayers"],
        31 => [1898, "#{PD}, Vierte Folge", BLUME, "rhymed prayers"],
        32 => [1899, "#{PD}, Fünfte Folge", DREVES, "rhymed prayers"],
        33 => [1899, "#{PD}, Sechste Folge", BLUME, "rhymed prayers"],
        34 => [1900, "#{SI}, Vierte Folge", BLUME, "sequences"],
        35 => [1900, "#{PR}, Erste Folge", DREVES, "rhymed psalters"],
        36 => [1901, "#{PR}, Zweite Folge, nebst einem Anhange von Rosarien", DREVES, "rhymed psalters"],
        37 => [1901, "#{SI}, Fünfte Folge", BLUME, "sequences"],
        38 => [1902, "Psalteria Wessofontana. Ulrich Stöcklins von Rottach siebzehn Reimpsalterien",
               DREVES, "rhymed psalters"],
        39 => [1902, "#{SI}, Sechste Folge", BLUME, "sequences"],
        40 => [1902, "#{SI}, Siebente Folge", BANNISTER, "sequences"],
        41 => [1903, "XLIa: Christanus Campoliliensis. Christans von Lilienfeld Hymnen, Officien, " \
                     "Sequenzen und Reimgebete; XLIb: Boncore de Sancta Victoria. Boncores di Santa " \
                     "Vittoria Novus liber hymnorum ac orationum", DREVES, "hymns"],
        42 => [1903, "#{SI}, Achte Folge", BLUME, "sequences"],
        43 => [1903, "#{HI}, Siebente Folge", DREVES, "hymns"],
        44 => [1904, "#{SI}, Neunte Folge", BLUME, "sequences"],
        45 => [1904, "XLVa: #{HR}, Achte Folge; XLVb: #{CM}, Dritte Folge: Cantiones variae, " \
                     "Bohemicae, Suecicae", DREVES, "rhymed offices"],
        46 => [1905, "#{PD}, Siebente Folge", DREVES, "rhymed prayers"],
        47 => [1905, "#{TG}. I. Tropen zum Ordinarium Missae", BLUME_BANNISTER, "tropes"],
        48 => [1905, "#{HL}, Erste Folge", DREVES, "hymns"],
        49 => [1906, "#{TG}. II. Tropen zum Proprium Missarum", BLUME, "tropes"],
        50 => [1907, "#{HL}, Zweite Folge", DREVES, "hymns"],
        51 => [1908, "#{TH}. I. Die Hymnen des 5.–11. Jahrhunderts und die irisch-keltische Hymnodie",
               BLUME, "hymns"],
        52 => [1909, "#{TH}. II. Die Hymnen des 12.–16. Jahrhunderts", BLUME, "hymns"],
        53 => [1911, "#{TP}. Erster Teil: Liturgische Prosen erster Epoche", BLUME_BANNISTER, "sequences"],
        54 => [1915, "#{TP}. Des 2. Teiles erster Band: Liturgische Prosen des Übergangsstiles und der " \
                     "zweiten Epoche", BLUME_BANNISTER, "sequences"],
        55 => [1922, "#{TP}. Des 2. Teiles zweiter Band: Liturgische Prosen zweiter Epoche auf Feste " \
                     "der Heiligen", BLUME, "sequences"]
      }.freeze

      # The adopted archive.org item per volume (the PIMS run; see above).
      def self.identifier_for(volume)
        return "analectahymnicam50drevuoft" if volume == 50

        format(volume <= 41 ? "analectahymnicam%02ddrev" : "hymniineditilitu%02ddrev", volume)
      end

      ITEMS = VOLUMES.map do |volume, (year, title, editor, genre)|
        Item.new(key: format("ah%<v>02d-%<y>d", v: volume, y: year), identifier: identifier_for(volume),
                 language: "lat", creator: editor, title: "#{SERIES}, Bd. #{volume}: #{title}",
                 date: dated(year), imprint: volume <= 8 ? FUES : REISLAND, genre: genre,
                 series: SERIES, scan: PIMS)
      end.freeze

      # Princeton Theological Seminary's bundles ("v. 1-3" … "v. 54-55").
      PRINCETON_BUNDLES = %w[13drev_0 46drev 79drev 1012drev 1315drev 1618drev 1921drev 2224drev 2527drev
                             2830drev 3133drev 3436drev 3739drev 4345drev 4647drev 4849drev 5253drev
                             5455drev].freeze

      # The 114 series items not adopted, by reason (the reconciliation
      # above; ITEMS + REJECTED = the 169 series items censused).
      REJECTED = {
        "no_hocr" => [
          *[*1..39, *41..49, 51].map { |n| format("analectahymnica%02ddrevuoft", n) },
          *(52..55).map { |n| "analectahymnica#{n}blumuoft" }, "analectahymnica40drevuoft",
          *[0, *2..7, 9].map { |n| format("analectahymnica%02dblumgoog", n) }, "analectahymnica00banngoog",
          "cantionesbohemi00drevgoog", "historiaerhythm02drevgoog", "piadictaminarei00blumgoog",
          "piadictaminarei01blumgoog", "sequentiaeinedi01drevgoog", "thesaurihymnolo00churgoog",
          "tropigradualest00blumgoog", "liturgischeprose012814mbp", "nalectahymnicame008775mbp"
        ],
        "bundle" => [
          *PRINCETON_BUNDLES.map { |suffix| "analectahymnicam#{suffix}" },
          "hymnographilatin01drevuoft", "hymnographilatin1v2drev"
        ],
        "other_copy" => %w[
          analectahymnica01blumgoog analectahymnica08blumgoog cantionesetmute00churgoog
          conradusgemnice00drevgoog historiaerhythm00drevgoog historiaerhythm01drevgoog
          historiaerhythm03drevgoog historiaerhythm04drevgoog historiaerhythm05drevgoog
          hymniineditilit00churgoog hymniineditilit01churgoog hymniineditilit02churgoog
          hymnodiahiberic00drevgoog hymnographilati00drevgoog piadictaminarei02blumgoog
          piadictaminarei03blumgoog psalteriarhythm00churgoog sequentiaeinedi00drevgoog
          sequentiaeinedi02drevgoog analec00drev
        ],
        "folder_upload" => %w[analecta-hymnica-medii-aevi],
        "duplicate" => %w[hymniineditilitu50drev]
      }.transform_values(&:freeze).freeze

      # Title-query hits that are other works: Wetzel's Analecta hymnica
      # (1751–1755, five BSB items), the Analecta Hymnica Graeca, Dreves's
      # anthology Ein Jahrtausend lateinischer Hymnendichtung (1909, two).
      NOT_THE_SERIES = %w[10123087bsb 11338315bsb 11338321bsb 11338322bsb bub_gb_0lc7AAAAcAAJ
                          Analecta-Hymnica-Graeca einjahrtausendla0000drev einjahrtausendla00drev].freeze

      SERIES_EDITORS = /Dreves|Blume|Bannister/
      SERIES_TITLE = /analecta hymnica medii aevi/i
      VOLUME_RANGE = /\d+\s*-\s*\d+/

      # The machine-checkable half of the census rule over an archive.org
      # /metadata/<identifier> response: "not_the_series" (neither a series
      # editor among the creators nor the series title), "no_hocr" (no hOCR
      # derivative pair), "folder_upload" (more than one hOCR stem in one
      # item), "bundle" (a volume RANGE in the volume field), else
      # "eligible" — adoption among eligible copies is the measured census
      # above, never this method.
      def self.census_verdict(response)
        meta = response.fetch("metadata")
        names = response.fetch("files", []).map { |file| file["name"] }
        stems = names.select { |name| name.end_with?(IaHocrText::SEARCHTEXT_SUFFIX) }
                     .map { |name| name.delete_suffix(IaHocrText::SEARCHTEXT_SUFFIX) }
        paired = stems.select { |stem| names.include?("#{stem}#{IaHocrText::PAGEINDEX_SUFFIX}") }
        return "not_the_series" unless Array(meta["creator"]).join(" ").match?(SERIES_EDITORS) ||
                                       meta["title"].to_s.match?(SERIES_TITLE)
        return "no_hocr" if paired.empty?
        return "folder_upload" if paired.size > 1
        return "bundle" if meta["volume"].to_s.match?(VOLUME_RANGE)

        "eligible"
      end

      OCR_NOTE = "Uncorrected machine OCR (archive.org hOCR derivative), never proofread: the Latin hymn " \
                 "texts and the German prefaces and apparatus read approximately; stanza numbering, " \
                 "sigla, abbreviations and the occasional music notation are frequently garbled. " \
                 "Cite the scan (ia_url)."

      MANIFEST = Nabu::SourceManifest.new(
        id: "analecta-hymnica",
        name: "Analecta Hymnica Medii Aevi, Bd. 1–55 (Dreves, Blume, Bannister; archive.org scans, " \
              "uncorrected OCR)",
        license: "Public domain: printed 1886–1922 (pre-1931); editors died 1909 (Dreves), 1919 " \
                 "(Bannister), 1932 (Blume). archive.org items: the PIMS – University of Toronto scans, " \
                 "no rights field — the works' status rests on those dates. Text = archive.org's " \
                 "uncorrected machine OCR (hOCR derivatives)",
        license_class: "open",
        upstream_url: "https://archive.org/details/analectahymnicam01drev",
        parser_family: "ia-hocr-text"
      )

      def self.manifest = MANIFEST

      private

      # The print year is the date — labeled "edition" (the hymns are
      # medieval; see Language, dating, places above).
      def metadata_for(item, pages, text_pages)
        super.merge("ocr_note" => OCR_NOTE, "date" => item.date.merge("class" => "edition"),
                    "volume" => item.title[/Bd\. (\d+):/, 1].to_i)
      end
    end
  end
end
