# mazarinades fixtures — the Antonomaz corpus of Fronde pamphlets

Real files from `github.com/Antonomaz/Corpus`, retrieved **2026-11-05** by
direct HTTP (raw.githubusercontent.com) at main
`84f319b947e23b90f86f6948efa5f0f78f21e6f6` (last push 2025-02-26). Raw URL
of any file = `https://raw.githubusercontent.com/Antonomaz/Corpus/<sha>/<path>`.

`tree/` mirrors upstream's own layout, so discovery walks it exactly as it
walks a checkout. `malformed/` holds one of upstream's malformed files in the
same layout, OUTSIDE `tree/` so the conformance suite (which parses every
discovered file) never meets it; the adapter test copies it into a scratch
tree to pin the quarantine.

## License (verbatim, first-hand)

`tree/README.md` (the repo README, whole), section "Licence":

> Les textes sont publiés sous la licence [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Every well-formed TEI file's publicationStmt:

```xml
<availability n="cc-by" status="restricted">
  <licence target="https://creativecommons.org/licenses/by/4.0"/>
</availability>
```

→ class **attribution**. The oddity, recorded: `status="restricted"` (a TEI
availability value meaning access is restricted) sits on every file — the
project template's default — while the licence element and the README both
name CC BY 4.0; the licence element governs. 33 files carry `n="NaN"` instead
of `n="cc-by"` (specimen: `Moreau1021_GBOOKS.xml`), same licence element.

## Upstream's delivery grains (census of the whole tree at 84f319b9)

7,171 blobs (GitHub tree listing); every `Mazarinades/` file downloaded and
read for the census.

| grain | files | verdict | specimen |
|---|---|---|---|
| `Mazarinades/<folder>/*.xml` — one TEI file per pamphlet | 3,080 | **ACCEPTED** (3,067 parse; 13 malformed → quarantined) | 8 files below |
| `Mazarinades/filecount.txt`, `Mazarinades/1-100/diff.txt` — working files | 2 | skipped by rule | both (diff.txt trimmed) |
| `Doublons/**` — further exemplars of Moreau numbers already encoded ("ils n'ont à priori pas été relus") | 955 (953 xml + README.md + a macOS .textClipping) | REJECTED, outside the cone; skipped by rule where present | `Moreau3845-bad_GBOOKS.xml`, `README.md`, the `.textClipping` |
| `Mazarinades_jsons/**` — JSON exports of the TEI | 3,065 | REJECTED (derivative) | `1401-1500/Moreau1483_GBOOKS.json` |
| `output/**` — generated reports and statistics | 22 | REJECTED | `Mazarinades_filecount.txt` |
| `output/reviewed_files.csv` — the first-page review ledger | 1 | rides the cone; READ as per-document metadata `first_page_review`, skipped by rule as a document | trimmed (header + 8 rows) |
| `script/**` — processing scripts | 40 | REJECTED | `update_tracking.txt` |
| top-level files — README.md (the licence evidence, rides the cone), Antonomaz.xpr, apply_titles.py, titres_corriges_Moreau.json, Requete_sous_corpus.md, .gitignore; `.github/` | 7 | repository furniture, skipped by rule | `README.md`, `Requete_sous_corpus.md` |

Reconciliation against upstream's own counts: upstream advertises no total.
`Mazarinades/filecount.txt` lists the 48 folders and
`output/Mazarinades_filecount.txt` per-folder counts summing to 3,065 — the
JSON tree's figure; the TEI tree has 15 more (3,080). Accepted 3,080 =
3,067 well-formed + 13 malformed (all MANUAL-suffixed — 12 hand
transcriptions and one Kraken file: an unescaped `&`, mismatched tags). Doublons
955 = 953 + 2 non-TEI. A full parse of the downloaded `Mazarinades/` tree
through the adapter: **3,067 documents / 40,883 page passages, 13 errored,
4 skipped by rule (sparse cone: the two working files, README.md, the
ledger), 0 unrecognized.**

## The accepted specimens (all whole, byte-verbatim)

| file | why |
|---|---|
| `1401-1500/Moreau1483_GBOOKS.xml` | Google Books; one page; Paris, Moreau 1652; publisher persName |
| `2101-2200/Moreau2135_MAZ.xml` | Mazarinum scan: `pb vue=`, blank vues, `<gap/>`, `lb break="no"` continuations, imprimatur, two dates (Mazarine + Carrier's range), a Moreau episode setting, an ISNI author |
| `1001-1100/Moreau1085-i_MAZ.xml` | `language ident="other"` "Document en picard"; Sans lieu; `<l>` line boxes |
| `1001-1100/Moreau1021_GBOOKS.xml` | `availability n="NaN"`; `<l>` on a prose title page; a review-ledger row with a remark |
| `601-700/Moreau614_GALL.xml` | Gallica `facs` URLs; `<fw>` page numbers and catchwords; a margin `<note>`; a blank page; three genre terms |
| `2501-2600/Moreau2542_MANUAL.xml` | a hand transcription ("transcription manuelle réalisée par Karine Abiven") — no OCR label; no `<pb>` at all; Rouen |
| `4001-4100/Moreau4018_GALL.xml` | one of four files that use `<pb>` as a CONTAINER of the page's lines |
| `Labadie/Labadie332_GALL.xml` | the Labadie collection; Labadie + Antonomaz dates |

Rejected-grain and quarantine specimens: see the table; malformed:
`malformed/Mazarinades/1901-2000/Moreau1902_MANUAL.xml` (tag mismatch).

## Trims

- `tree/Mazarinades/1-100/diff.txt`: first 20 lines (of 63,749 bytes).
- `tree/output/reviewed_files.csv`: header + 8 of 3,064 rows (the first two,
  then every row naming a fixture file), byte-verbatim.
