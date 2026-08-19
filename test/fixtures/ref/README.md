# ReF fixtures (Early New High German, CorA-XML)

Real samples from the **Reference Corpus of Early New High German
(1350–1650)** (*Referenzkorpus Frühneuhochdeutsch*, ReF), version
**1.0.2**, in its native **CorA-XML** export (CLAUDE.md fixture rules).
Four structural trims of real texts, mirroring the deposit's subcorpus
directories (`ref-mlu/`, `ref-rub/`; the `ref-up/` TigerXML syntax
overlay is a documented follow-up and has no fixture).

- **Retrieved:** 2026-08-19, from **Zenodo record 5793616** (concept DOI
  `10.5281/zenodo.5704572` → v1.0.2, `https://zenodo.org/records/5793616`).
- **Upstream artifact:** `ReF-v1.0.2.tar.gz`,
  `https://zenodo.org/api/records/5793616/files/ReF-v1.0.2.tar.gz/content`,
  143,463,482 B, sha256
  `288a478d02de5796d14faa0b669879dc6bf67c47e2d7ee261815e15120b99f0e`.
  The tarball holds `LICENSE` (CC BY-SA 4.0 legal text) + `README.md` +
  `dokumentation.pdf` + `ref-mlu/` (136 CorA-XML files) + `ref-rub/`
  (54 CorA-XML files) + `ref-up/` (26 TigerXML files). The full tarball
  was fetched to a scratch dir and is **not** committed.

## Files (structural trims)

Each trim keeps the `<cora-header>` + `<header>` byte-for-byte, keeps a
contiguous window of `layoutinfo` lines (with their pages/columns), the
`shifttags` entries whose ranges fall inside the window, exactly the
tokens whose dipl units the window covers (windows end on token
boundaries), and the top-level `<comment>` apparatus whose neighboring
token is kept, then closes the document. Well-formedness verified with
`xmllint --noout`; content is upstream's, never edited.

| File | Bytes | Text | Window | Exercises |
|---|---|---|---|---|
| `ref-mlu/F011.xml` | 65,005 | *Die Geometria. Deutsch* (Roritzer print, Regensburg 1487/88) | lines l1–l13 (page 001r) | mostly-manual annotation, the her(=)nach line-straddling token, punc lane, 3 top-level + 2 anno-level comments |
| `ref-rub/F166.xml` | 39,461 | *Farbrezepte für Garne* (Cologne ms., 16th c.) | lines l1–l15 (page 1r) | ReF.RUB subcorpus, title shifttags, one-dipl/two-anno punctuation splits, anno-level comment notes ("Mehl?") |
| `ref-mlu/F313.xml` | 28,603 | *Heiltum Bamberg* (print, Bamberg 1493) | lines l70–l84 (003r → 003va) | wholly-auto annotation, NAMED columns joining the citation |
| `ref-mlu/F240.xml` | 79,336 | *Thüringer Spiele* (ms., 3rd quarter 14th c.) | lines l55–l70 (page 090) | sideless pages, upstream's adjacent duplicate line label 08 (the :b2 exemplar), lat shifttags, 12 top-level comments |

## Censuses backing the parser (whole deposit, 2026-08-19)

190 CorA-XML files; 3,107,196 tokens / 3,218,542 dipl units / 3,418,971
anno units; header `language: fnhd` in 190/190; every layout line's
start dipl id exists and every file's first dipl starts its first line;
5,729 duplicate line citations across 40 files; annoType 2,874,451 auto
vs 544,520 manual (`checked="y"` count equals the manual count); the 28
header keys are uniform across all files; 103,352 `<comment>` elements
(31,135 anno-level `@tag` notes riding token records, the rest top-level
free-text apparatus — counted per document, text swallowed).
