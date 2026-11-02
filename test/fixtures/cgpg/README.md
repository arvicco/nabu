# CGPG fixtures — Calfa/GREgORI Patrologia Graeca (OCR + machine tagging)

Retrieved 2026-11-02.

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

## The delivery grains upstream serves

| Grain | What it is | Taken? |
|---|---|---|
| the archive | `PG.zip` → one top-level `PG/` directory | fetched, unpacked (not a document) |
| the volume file | `PG/PG<nnn>[_<part>]_tagged_text.vert` (28) or `.txt` (5, same format) — one Migne volume each, 33 in all | **ACCEPTED — the document** |
| `<doc>` element | one per file (`<doc id="PG 101 - AI processed">`) — the same unit as the file | folded into the document (a second one is a parse error) |
| PDF page | the `PDF Page P` part of every `<w id>` — the page image of the scanned volume | **the passage** |
| OCR line, word | `Line L - word id N` | ride inside the passage (line layout of the text; `line` on each token) |
| raw OCR text | GitHub `PG<nnn>/PG<nnn>_text.txt` — the same OCR without the tagging (`$0` volume / `$8` page / `$9` line markers) | **rejected** — superseded by the tagged files; specimen `rejected-grains/PG101_text.txt`, skipped by rule |
| OCR ground truth | Zenodo 20008699 — line images + transcriptions for training | not fetched (training data, not text) |

There is no work, chapter or Migne-column markup anywhere in the
deposit: a volume holds several authors and works (README table), and a
document here is a volume, not a work.

## Files

- `PG101_tagged_text.vert` — PG 101 (Photius vol. 1), trimmed to PDF
  page 14 (the volume's first page): 52 lines / 388 tokens.
- `PG008_tagged_text.txt` — PG 8 (Clement of Alexandria vol. 1), one of
  the five `.txt`-suffixed members, trimmed to PDF pages 57 and 343: the
  first carries an empty-form token (`\t∅\t∅\t∅\t∅`) and an unanalysed
  `»` (`»\t∅\t∅\t∅\t∅`); the second a `#NOM?` line (a spreadsheet error
  standing where the token row should be, its `</w>` missing).
  499 tokens over 79 lines.
- `PG153_tagged_text.vert` — PG 153 (John Cantacuzene, *Historia*),
  trimmed to PDF page 37 (the first page): 28 lines / 197 tokens.
- `rejected-grains/PG101_text.txt` — GitHub raw OCR, first page block
  (53 lines), the rejected grain.

Each trim keeps the `<doc>` line, every line of the kept pages' `<w>`
blocks byte for byte, `</doc>`, and upstream's CRLF line ends.

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
