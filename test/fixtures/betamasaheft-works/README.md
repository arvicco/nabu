# Beta maṣāḥǝft Works fixtures — Ethiopic TEI (P46-2)

Five real TEI records + one real repo-root packaging file, snapshotted
**2026-07-26** from `github.com/BetaMasaheft/Works` (branch `master`,
commit `e8d5814bacf33b71adc532b6f50ac3e7c0dc96e5`). All files are upstream
byte-for-byte except the ONE documented trim (LIT2711Mark.xml below), so the
fixtures document the corpus's real encoding quirks. Upstream keeps one TEI
file per work under thousand-range directories (`1-1000/` … `7001-8000/`)
plus a `new/` overflow directory; the fixture tree mirrors that layout.

Chosen to cover the shapes the adapter must handle:

- `2001-3000/LIT2711Mark.xml` — the Gospel of Mark (Bǝsrāta Mārqos), the
  chapter/verse shape: `div type="edition" xml:lang="gez"` →
  `div type="textpart" subtype="chapter" n="…"` → `<ab>` → `<l n="…">`
  verse lines interleaved with UNNUMBERED `<l>` section rubrics (reading
  text, no `@n`), `<label>` chapter headings (apparatus, dropped) and
  empty `<ref target=…/>` verse pointers (dropped). **TRIMMED: chapters
  1–2 only** (212 KB → 26 KB; the untrimmed file carries all 16 chapters /
  exactly 678 numbered `<l>` — the canonical verse count). The trimmed
  sample holds **73 numbered verses (45 + 28, the canonical chapter 1–2
  counts) + 12 unnumbered rubric lines**. In-file
  `<licence target="http://creativecommons.org/licenses/by-sa/4.0/">`.
- `2001-3000/LIT2229RuthBo.xml` — Book of Ruth, WHOLE (38 KB): four
  chapters / 85 numbered verses, no rubric lines, and the per-document
  attribution shape — `<editionStmt>` "OCTATEUCHUS © Digitalizavit Ran
  HaCohen" plus the licence paragraph naming the transcription copyright.
  The adapter carries this attribution in document metadata.
- `1001-2000/LIT1882MarkGo.xml` — the incipit/explicit record shape,
  WHOLE: `div type="edition"` with NO `@xml:lang`, a nested
  `textpart subtype="chapter"` (xml:id `BiographyMark`, no `@n`) holding
  `incipit`/`explicit` textparts with `<ab>` prose, plus `<listBibl>` and
  `<note>` apparatus (dropped). Two passages.
- `1-1000/LIT0017MMDZ.xml` — the MISLABELED-language shape, WHOLE: the
  edition div claims `xml:lang="en"` but its `<ab>` is Gǝʿǝz (Ethiopic
  script); a commented-out `<div type="translation">` rides beside it.
  The adapter's Ethiopic-content rule ingests it as `gez` (one passage).
- `2001-3000/LIT2006Mazmur.xml` — a CATALOG-ONLY record, WHOLE: no
  edition div at all (title + bibliography only). Skipped silently by
  rule — the corpus norm (most of the 6,548 files), never a quarantine.
- `repo.xml` — the repo-root eXist-db packaging file, WHOLE: real XML
  with NO TEI `<licence>` grant (one of the 3 licence-less XML files in
  the repo, beside `build.xml` and `expath-pkg.xml`). Skipped by rule:
  no in-file grant, no ingestion (the D46-a per-document licence gate).

License (D46-a, owner-ratified 2026-07-26): the per-document in-file
`<licence>` grant governs — 6,545 of the repo's 6,548 XML files carry
CC BY-SA 4.0 verbatim → class `attribution`. The PROJECT WEBSITE
(betamasaheft.eu) blankets its pages CC BY-NC-SA — a recorded discrepancy;
the in-file grant is the house doctrine (docs/02-sources.md row 123).
