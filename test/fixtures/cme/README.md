# CME fixtures — Corpus of Middle English Prose and Verse

Retrieved **2026-08-23** from the corpus editors' companion site
(medictionary.info — P.F. Schaffner's "point 3" bulk channel, grant №77-2,
2026-08-20). The site's Apache autoindex `http://www.medictionary.info/texts/`
serves the whole May-2026 normalization (297 files, Last-Modified 2026-05-09
across the board) as plain files; the Dropbox/Box `CME-all.zip` share links
offered on `pages/CME_downloads.html` hold the SAME corpus (the U-M
institutional folder zips to ~1.96 GB with extras) behind share-link tokens
that fail the automation bar, so the autoindex is the fetch channel.

## texts/ — four WHOLE real corpus files (untrimmed)

| file | URL (`http://www.medictionary.info/texts/…`) | why this one |
|---|---|---|
| `CME301.xml` | `CME301.xml` (9.5 KB) | Phase-3 direct-from-manuscript prose ("Three Inspections" Hematoscopy, Tavormina/Schaffner transcription): `<CHOICE><SIC>/<CORR>`, `<ADD>`/`<DEL>`, interlinear `<LB/>` line pairs, `<OPENER>`/`<ARGUMENT>`, a header with NO `BIBLFULL` (no print source) |
| `tenwives.xml` | `tenwives.xml` (12 KB) | Phases-1-2 verse ("A Talk of Ten Wives on their Husbands' Ware", EETS-era Furnivall print): `<FRONT>` title page, `<LG>`/`<L>` stanzas, inline `<NOTE PLACE="marg">`, folio `<MILESTONE>`s, `<PB N="29">`, the placeholder `<IDG ID="CME00000">`, þ/ȝ |
| `CME00011.xml` | `CME00011.xml` (20 KB) | dialogue ("Questiones by-twene the Maister of Oxenford and his clerke", Englische Studien 1885): 100 `<SP>`/`<SPEAKER>` speeches, `<GAP DESC="illegible" DISP="•">`, German foot-notes, the empty `<AUTHOR/>` before the real `<AUTHOR TYPE="add">`, BIBLFULL dates all "unknown" |
| `CME00121.xml` | `CME00121.xml` (31 KB) | **the nested-TEXT surprise**: a `<TEXT>` embedded inside a `<DIV1>` of another `<TEXT>` with NO `<GROUP>` ("Zwei Mittelenglische Christmas Carols", Englische Studien 1890) — the reason the tcp-xml div stack is nesting-driven, never ladder-rank-driven |

All four are byte-identical to upstream (no trimming): together they cover
prose/verse/drama/nested-text, the three corpus batches (Phases 1-2,
Phase 3, Englische-Studien-era additions), and every apparatus shape the
whole-corpus census (all 297 files, 2026-08-23) found load-bearing.

## fetch/ — the crawl fixture

`texts-index.html` — the REAL May-2026 autoindex page trimmed to six rows
(the four fixture files + `3KCol.xml` + the 20 MB outlier `afz9170.xml`),
header/sort-links/parent-row/tail kept byte-verbatim (ISO-8859-1, as
served). Documents the shape `Nabu::CmeFetch` harvests and the navigation
links it must never treat as records.

## Corpus-wide census facts the tests pin (2026-08-23)

- All 297 files: root `<ETS>`, DOCTYPE `eebo2prf.xml.dtd` (`DunTwa.xml`
  alone references the editor's local `C:/code/dtds/` copy — the DTD is
  never fetched; no named entities beyond the XML built-ins).
- One uniform public-domain `<AVAILABILITY>` statement across all 297.
- `<LANGUSAGE>` inconsistent: 150 files declare `enm`, 61 declare "eng",
  36 declare nothing, others list only their FOREIGN languages (lat/fre/
  ger …) — hence bare `enm` as the adapter claim, declarations in metadata.
- `<NOTE>` places: marg ×103,906, foot ×60,489, inter ×2, placeless ×3,315.
- 19 files carry multiple `<TEXT>`s (via `<GROUP>` in 9, via bare nesting
  in the rest); DIV ladder runs DIV1..DIV7.
