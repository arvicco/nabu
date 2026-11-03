# Patristic Text Archive (PTA) fixtures

Real upstream samples from the Patristic Text Archive's data repository
(CLAUDE.md fixture rules), trimmed but structurally intact.

- **Retrieved:** 2026-11-02, a clone of
  [PatristicTextArchive/pta_data](https://github.com/PatristicTextArchive/pta_data)
  at commit `524eb9763b1181bc9f14edf52943bfe2f7a43aed` (2026-06-18; still
  HEAD on 2026-11-02).
- **License:** per file — each file's own teiHeader `<licence>` (README:
  "The individual files are licensed by different Creative Commons
  Licenses. The respective license is mentioned in the header of each
  file."). Attribution: Patristic Text Archive (BBAW) and each edition's
  editors.
- **Layout:** mirrors upstream's `data/<textgroup>/<work>/` CapiTainS tree
  (with the textgroup and work `__cts__.xml` files copied whole) and one
  `analyzed/` specimen.
- **Trim rule:** every teiHeader is kept verbatim; inside the body only
  the first citation units are kept at each level (and, for the long
  single-section texts and the never-parsed rejected specimens, only the
  first paragraphs / first nodes).

## Delivery grains (upstream serves)

| Grain | Upstream count | Adapter |
|---|---|---|
| `data/` Greek edition `pta-grc<n>` | 198 | **the document** (every edition of a work) — less the two Bible families below |
| `data/` manuscript transcription `pta-Ms*` | 172 (19 unlicensed) | skipped by rule |
| `data/` biblical-excerpt file `*Bibex` | 32 | skipped by rule |
| `data/` edition in another language (syc, deu, xcl, lat, eng, chu, com, rum) | 134 | skipped by rule |
| `data/pta9999` Rahlfs Septuagint (Greek) | 58 | skipped by rule (02-sources row 44) |
| `data/pta9999` SBL Greek New Testament | 27 | skipped by rule (held as `sblgnt`) |
| `analyzed/` tokenized/lemmatized twins | 487 | not walked (censused in the skip notes) |

No `<licence>` at all → skipped as unlicensed before any grain rule.

## Files (under `data/` unless noted)

| Path | Licence (own header) | Why it is here |
|---|---|---|
| `pta0001/pta002/pta0001.pta002.pta-grc1.xml` | CC BY-SA 4.0 | Severian, *De paenitentia et compunctione* (PG 49) — the CTS refsDecl beside the biblical/pta/perseus resolver refsDecls; pre-critical edition (sections 1–2 of 7) |
| `pta0001/pta024/pta0001.pta024.pta-grc1.xml` | CC BY 4.0 | *De sacrificiis Caini*, Uthemann et al. 1994 — first four paragraphs of its one section |
| `pta0001/pta024/pta0001.pta024.pta-grc2.xml` | CC BY 4.0 | the same work, Savile's Eton 1612 print — two editions of one work, both documents |
| `pta0001/pta036/pta0001.pta036.pta-grc1.xml` | CC BY 4.0 | *In Noe*, Uthemann — the inline critical apparatus (`<app>/<lem>/<rdg>`), sections 1–2 |
| `pta0036/pta001/pta0036.pta001.pta-grc1.xml` | CC BY-NC-SA 3.0 (deed.de) | Anonymus of Cyzicus, *Historia ecclesiastica* (Hansen, GCS N.F. 9) — the nc document; book 1, chapter 1 |
| `pta0100/pta001/pta0100.pta001.pta-grc1.xml` | CC BY 4.0 | Athanasius Werke III Dok. 1 — the catalog's unfilled defaults (`0030–0800`, Pleiades `XXXXX`, "Genre missing") |
| `pta0001/pta025/pta0001.pta025.pta-MsKa.xml` | **none** | unlicensed manuscript transcription (rejected: unlicensed) |
| `pta0001/pta025/pta0001.pta025.pta-MsAc.xml` | CC BY-SA 4.0 | licensed manuscript transcription (rejected grain) |
| `pta0001/pta026/pta0001.pta026.pta-grcBibex.xml` | CC BY-SA 4.0 | biblical-excerpt file (rejected grain) |
| `pta0100/pta001/pta0100.pta001.pta-deu1.xml` | CC BY-NC 3.0 DE | German translation (rejected: other language) |
| `pta9999/pta001/pta9999.pta001.pta-syc1.xml` | CC BY-NC 4.0 | Peshitta Genesis (rejected: other language) |
| `pta9999/pta001/pta9999.pta001.pta-grc1.xml` | CC BY-SA 4.0 | Rahlfs Genesis (rejected: the Rahlfs exclusion) |
| `pta9999/pta063/pta9999.pta063.pta-grc1.xml` | CC BY 4.0 | SBLGNT Matthew (rejected: held as `sblgnt`) |
| `analyzed/pta0001/pta002/pta0001.pta002.pta-grc1.xml` | CC BY-SA 4.0 | the analyzed/ twin of the first file (never walked) |

Together the licence tags cover every target upstream ships: by-sa-4.0,
by-4.0, by-nc-4.0, by-nc-3.0-de, by-nc-sa-3.0, plus an unlicensed file.
