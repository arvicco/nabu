# noscemus fixture

Retrieved 2026-11-05 from two Zenodo records, by direct HTTP GET:

- **Noscemus Digital Sourcebook** — record 15040256 (2025-03-17, concept
  15040255; creator Stefan Zathammer; license field cc-by-4.0), file
  `Noscemus_Digital_Sourcebook.zip` (301,102,275 bytes, md5
  ccd475d900ee5123d41d281b7234b285 = the record's checksum; sha256
  410cbd39…0fcc), via
  https://zenodo.org/api/records/15040256/files/Noscemus_Digital_Sourcebook.zip/content
- **Noscemus Wiki** backup — record 7855322 (2023-03-31, concept 7855321;
  license field cc-by-4.0), files `2023-03-31_noscemus_works.xml` (md5
  983b5bfd…0e0a), `2023-03-31_noscemus_authors.xml` (md5 c68af308…f1da),
  `2023-03-31_noscemus_literature.xml` (md5 a830b28b…5aa0), via
  https://zenodo.org/api/records/7855322/files/<name>/content

The tree is the sourcebook zip as the adapter's fetch lands it (bsdtar
unpack, the single top directory `Noscemus_Digital_Sourcebook/` stripped)
plus the wiki tables under `wiki/<table>/`.

## Delivery grains (every grain the two records serve)

| grain | where | taken? |
|---|---|---|
| the sourcebook archive | `Noscemus_Digital_Sourcebook.zip` (2,101 members: 1,051 dirs + 1,050 files, 791,925,300 bytes unpacked; 183 member names CP437 bytes + the UTF-8 name in the Info-ZIP Unicode Path extra field 0x7075) | unpacked (bsdtar), not a document |
| the copy | `<transkribus-id>/<Author_-_Title__Place_Year[_pdf]>.txt` — 1,050 dirs, exactly one .txt each (1,031 `*_pdf.txt`, 19 plain `.txt`) | TAKEN — the document |
| the Transkribus metadata section | the file header (Title, Author, Description, Genre, Writer, Sripttype, Language, Number of Pages, Created From/To, Editorial Declaration) | TAKEN as metadata |
| the text region | body runs separated by two or more blank lines (no page break or paragraph mark exists in the export) | TAKEN — the passage; letterless regions ride the next passage as `marks` |
| the empty-text copy | 12 copies with a blank or letterless body | skipped by rule (DocumentSkipped); `736346/` pinned whole |
| wiki works | `wiki/works/2023-03-31_noscemus_works.xml` — 989 `{{Works}}` pages | TAKEN as the metadata join (Transkribus-ID links) |
| wiki works with no copy | 41 with Transkribus-ID "not available"/empty, 3 naming ids absent from the zip | counted, never documents; one of each pinned (Archimedis De incidentibus in humidis; Epistola invitatoria → 71583) |
| wiki authors | `wiki/authors/2023-03-31_noscemus_authors.xml` — 850 `{{Authors}}` pages | TAKEN (life years, GND) |
| wiki literature | `wiki/literature/2023-03-31_noscemus_literature.xml` — 1,853 secondary-literature records | REJECTED — never fetched; one page pinned |

## The cuts

Text files: the header verbatim, then the body's first K regions with
their exact separators (the leading body newlines kept), one closing
newline. Names as bsdtar lands them (the Unicode Path field stores decomposed
accents; checked in NFC — the adapter keys on the directory id, never the
file name).

- `1031760/` — Bacon, *Instauratio magna*, London 1620 (also keyed in
  eebo-tcp — a different witness): 22 regions → 15 passages + 7 letterless
  marks (the title page "1620.", page numbers "2", "2\n9", "4" …); no
  `Sripttype` line in its header. Joined to the wiki's *Novum Organum*
  (a contained work at /pages/51).
- `1285855/` — Hippocrates & Denisot, *Aphorismi versibus Graecis et
  Latinis expositi*, Paris 1634: one of the 183 CP437-named members
  (`G\x82rard` in the header, Gérard in the extra field); 24 regions, all
  lettered; Greek and Latin; "Digitized by Google" stamps. Two wiki
  authors (Hippocrates, "c. 460 BC"; Denisot with GND).
- `643448/` — Oudin, *Poemata didascalica* vol. 2, Paris 1749: a host
  volume — three wiki works join (the collection itself as the whole-copy
  work, Noceti's *Iris* and *Aurora borealis* at /pages/211 and /231); 13
  regions → 10 passages.
- `5314216/` — Palingenio Stellato, *Zodiacus vitae*, Basel 1543: no wiki
  page (one of the 38 unjoined copies), a plain `.txt` name, CP437-named,
  header Language "Latin"; its opening pages are mirror-read HTR noise —
  the uncorrected-HTR caveat, verbatim. 12 regions → 11 passages.
- `736346/` — Crüger, *Uranodormus cometicus*, Gdańsk 1619: kept WHOLE
  (805 bytes) — header + a blank body, the skipped-by-rule specimen.

Wiki tables: the XML prologue and `<siteinfo>` verbatim, then the chosen
`<page>` blocks verbatim — works: the five joined pages + the two no-copy
specimens; authors: Bacon, Hippocrates, Denisot, Oudin, Noceti;
literature: its first page.

## Reconciliation (full unpack through the adapter, 2026-11-05)

1,050 directories = 1,050 text files = the record's 1,050 works →
1,038 documents / 555,797 region passages, 0 errored, 12 skipped by rule;
119,298 letterless regions ride as marks; 771,701,836 characters.
Dating: 1,036 from the Title label's imprint year, 2 from the Created
From year; 1472–1932. Wiki join: 1,012 of 1,050 copies.
