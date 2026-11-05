# CGPG fixtures — Calfa/GREgORI Patrologia Graeca (OCR + machine tagging)

Retrieved 2026-11-02 (the deposit); the carve plan 2026-11-05.

- Upstream: Zenodo record 19915273, "Patrologia Graeca (OCRized and
  analyzed texts)" — <https://zenodo.org/records/19915273>; one file,
  `PG.zip` (103,122,119 bytes, md5 `0e9693c24bdf836997b9e912def7cc73`,
  sha256 `3df496869e56f93f9589ef46c7b279bd75a5af3452bee17ba95930a0833d166b`),
  GET `https://zenodo.org/api/records/19915273/files/PG.zip/content`.
- License: the record's license field is `cc-by-4.0`; the companion
  GitHub repository (github.com/calfa-co/Patrologia-Graeca, raw OCR) shows
  the README badge "License: CC BY 4.0" (it has no LICENSE file).
- Project: CGPG (Calfa GREgORI Patrologia Graeca), led by Jean-Marie
  Auwers (UCLouvain), with GREgORI and Calfa; cite Vidal-Gorène & Kindt,
  "The Patrologia Graeca Corpus: OCR, Annotation, and Open Release of
  Noisy Nineteenth-Century Polytonic Greek Editions", LREC 2026,
  pp. 6519–6527.
- The carve plan: open-greek-corpus's `data/cgpg_carve_plan.json` at tag
  `corpus-2026-10-28.2` —
  <https://raw.githubusercontent.com/open-greek/open-greek-corpus/corpus-2026-10-28.2/data/cgpg_carve_plan.json>
  (293 KB, sha256
  `7c0fec3de35cfaa15c0d58abf283e782a3d85d7f22a37aa77269464da797228c`),
  CC BY 4.0 project data: per-volume work ranges over this deposit's PDF
  pages, with incipit checks, ranks, residual and duplicate rows.

## The delivery grains upstream serves

| Grain | What it is | Taken? |
|---|---|---|
| the archive | `PG.zip` → one top-level `PG/` directory | fetched, unpacked (not a document) |
| the volume file | `PG/PG<nnn>[_<part>]_tagged_text.vert` (28) or `.txt` (5, same format) — one Migne volume each, 33 in all | **carved into works** where the plan carves it (22 volumes); **the document** where it does not (10 unplanned + PG 3, deferred by the plan) |
| `<doc>` element | one per file (`<doc id="PG 101 - AI processed">`) — the same unit as the file | folded into the volume (a second one is a parse error) |
| PDF page | the `PDF Page P` part of every `<w id>` — the page image of the scanned volume; the plan's "loci" | **the passage** (of a work, a residuum, or a volume) |
| OCR line, word | `Line L - word id N` | ride inside the passage (line layout of the text; `line` on each token) |
| raw OCR text | GitHub `PG<nnn>/PG<nnn>_text.txt` — the same OCR without the tagging (`$0` volume / `$8` page / `$9` line markers) | **rejected** — superseded by the tagged files; specimen `rejected-grains/PG101_text.txt`, skipped by rule |
| OCR ground truth | Zenodo 20008699 — line images + transcriptions for training | not fetched (training data, not text) |

The carve plan's grains:

| Plan grain | Taken? |
|---|---|
| plan work (a slug + page ranges) | **ACCEPTED — the document** (`urn:nabu:cgpg:<slug>`); an `append` continuation in a later volume joins it |
| residual ranges / residual loci (edition apparatus) | **kept** in the volume's residuum document, `residuum_class` apparatus |
| drop_duplicates (rescanned leaves) | **kept** in the residuum, `residuum_class` duplicate + `duplicate_of` |
| rows in no work and no residual | **kept** in the residuum, `residuum_class` uncarved |
| a deferred volume (`status: defer`, PG 3) | not carved — the volume stays one document |
| a plan volume the box does not hold | skipped by rule in discovery (specimen: this fixture tree keeps the PG 146 entry and holds no PG 146 file; on the live box every plan volume is held) |
| a work or residuum with no held row | skipped by rule at parse (`DocumentSkipped`; specimen: `pg123-residuum`) |

## Files

Each volume trim keeps the `<doc>` line, every line of the kept `<w>`
blocks byte for byte, `</doc>`, and upstream's line ends (CRLF; PG 123
and 124 are LF upstream). "Lines 1–n" = the page's OCR lines 1 to n only
(a page cut short keeps whole lines). Cut from the box's own canonical
copy of PG.zip.

- `PG101_tagged_text.vert` — PG 101 (Photius vol. 1): page 14 whole (52
  lines / 388 tokens; plan residual 14–15), page 44 whole (the
  Amphilochia's head and incipit), page 293 whole (two tokens — the
  plan's explicit residual locus inside the Amphilochia's range).
- `PG123_tagged_text.vert` — PG 123: page 569, lines 1–8 (the John
  commentary's opening vita).
- `PG124_tagged_text.vert` — PG 124: page 10, lines 1–6 (the John
  commentary's continuation, `append`), page 168, lines 1–3 (residual
  168–170, the garbled Latin MONITUM), page 173, lines 1–8 (Romans
  incipit).
- `PG134_tagged_text.vert` — PG 134 (Zonaras): page 561, lines 1–4; page
  563, lines 1–4 (the plan's rescan of 561); page 568, lines 1–36 (the
  clausula's incipit at line 33).
- `PG139_tagged_text.vert` — PG 139 (three plan passes): page 13, lines
  1–8 (Isidorus, pass 3); page 119 whole (Joel, pass 2); page 167, lines
  1–6 (Choniates, pass 1); page 554, lines 1–6 (the final residual, a
  table of contents).
- `PG003_tagged_text.vert` — PG 3 (the plan-deferred volume): page 71,
  lines 1–4.
- `PG008_tagged_text.txt` — PG 8 (Clement of Alexandria vol. 1, not in
  the plan), one of the five `.txt`-suffixed members, trimmed to PDF
  pages 57 and 343: the first carries an empty-form token
  (`\t∅\t∅\t∅\t∅`) and an unanalysed `»` (`»\t∅\t∅\t∅\t∅`); the second a
  `#NOM?` line (a spreadsheet error standing where the token row should
  be, its `</w>` missing). 499 tokens over 79 lines.
- `PG153_tagged_text.vert` — PG 153 (John Cantacuzene, *Historia*, not in
  the plan), trimmed to PDF page 37 (the first page): 28 lines / 197
  tokens.
- `carve/cgpg_carve_plan.json` — the plan trimmed to nine of its 34 pass
  entries (PG 134, 101, 123, 124, 146, 3, and PG 139's three passes),
  `_meta` and every kept entry and work verbatim; each entry's `works`
  list filtered to the works whose pages are cut above (PG 146's one work
  kept for the unheld-volume rule). Re-serialized as pretty JSON.
- `rejected-grains/PG101_text.txt` — GitHub raw OCR, first page block
  (53 lines), the rejected grain.

Fixture census through the adapter: 16 refs → 15 documents (3 volume,
8 work, 4 residuum) + 1 skipped by rule (`pg123-residuum`); 18
passages; discovery skips 2 (the raw OCR, PG 146).

## Deposit census (2026-11-02, all 33 members unpacked)

33 volume files, 718,313,636 bytes unpacked; **18,701 PDF pages**
carrying tokens; **6,779,355 tokens** with a surface form (6,770,076
lemmatized); 2,229 empty-form tokens; 66 `#NOM?` lines. Every other
token row has five columns; every `<w id>` has the PDF Page / Line /
word id shape; page numbers never decrease within a file. Line ends are
CRLF except PG 123, 124 and 126 (LF). Parsing the whole unpack through
the adapter takes about 70 s on this box. The volume list and the per-volume
dates/authors come from the GitHub README's "Works and Authors Dataset"
table (transcribed into the adapter).

## Carve census (2026-11-05, the box's 33 files + the pinned plan)

The plan: 34 pass entries over 23 volumes, 210 works; every plan volume
held. Through the adapter: 242 refs → 209 works (the John commentary's
two parts are one) + 12 residua + 11 volume documents (10 unplanned +
PG 3) = 232 documents, and 10 residua skipped by rule (every held row is
a work's). Passages 12,630 (works) + 316 (residua: 90 apparatus, 46
duplicate, 180 uncarved) + 5,755 (volumes) = 18,701 — the deposit's page
count exactly; tokens 6,779,355 — the deposit's exactly. 181 works
primary, 28 secondary; all 227 incipit checks verified.
