# emmo fixture

Retrieved 2026-11-03 from https://emmo.folger.edu/zip/emmo.zip — the one
public download of Early Modern Manuscripts Online (Folger Shakespeare
Library): 2,988,429 bytes, md5 8ffbed9736da067193379fc58c123683 (= the
server's ETag), Last-Modified Sun, 31 May 2026 23:13:48 GMT. The zip holds
one top directory `emmo/`; ZipFetch strips it, so the files sit at this
directory's root exactly as they land in `canonical/emmo/`.

## Delivery grains (every grain upstream serves)

| grain | where | taken? |
|---|---|---|
| the corpus zip | `emmo.zip` (101 members under `emmo/`) | TAKEN — the one artifact |
| manuscript | `<shelfmark>.xml`, 100 TEI P5 files | TAKEN — document = file |
| page | `<pb n="leaf 1 recto"/>` inside each file (299 pb) | TAKEN — passage = page with text (196); 103 outer leaves / blank versos carry no text and are counted as `blank_pages` |
| stylesheet | `emmo.xsl` (the display XSLT) | REJECTED — skipped by rule; pinned whole here |
| page image | `sourceDoc/surface/media@url` → digitalcollections.folger.edu | REJECTED — never fetched (images sit outside the CC BY-SA grant; the URL rides each passage as `image_url`) |

The files are whole, byte-identical members of the zip:

- `La13.xml` — Yeldard Alvey, Oxford, to Walter Bagot, Blithfield, 1620
  March 27 (the tutor's letter on the dancing school): three pb, the
  middle opening blank; a Latin `<foreign>` dateline
  (Oxon<ex>iensis</ex>, regularized both "Oxoniensis" and "Oxford"), a
  struck-through name (`<del>`), the endorsement note, archival foliation
  (`<fw>`) and call number.
- `Xd451-187.xml` — Nathaniel Rich to Sir Robert Rich, Clapham, 1697 May
  12: one of the three files with an n-less `<pb/>` (a turn inside the
  first opening), administrative notes, the latest date in the corpus.
- `Lb543.xml` — John Donne's receipt to Sir Thomas Egerton, 1602 July 6:
  a non-letter (document type Receipt), Latin datelines, the archivist's
  long administrative note.
- `emmo.xsl` — the rejected grain's specimen (asserted skipped by rule).

## Census of the whole zip (through the adapter, 2026-11-03)

100 documents / 196 passages, 0 errors; 1 file skipped by rule
(`emmo.xsl`). textLang `eng` on all 100; 18 `<foreign xml:lang="la">`
spans. Licence target `https://creativecommons.org/licenses/by-sa/4.0/` on
all 100. origin@when on all 100, 1552–1697. A dateline `<placeName>` (the
writing place) on 46. Title heads: Letter 89, Deposition 2, Examination 2,
Certificate 1, Certificate of recusancy 1, Order 1, Copy of an order 1,
Warrant 1, Receipt 1, Legal opinion 1. Keywords: Letters 49, Family
Papers 12, Certificate 2, Receipt 1, Legal 1 (35 files carry none).
