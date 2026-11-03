# hmml-reading-room fixtures (vHMML Reading Room dataset, CC BY 4.0)

`dataset/vhmml_rr_fulldata.zip` — a TRIMMED-REAL re-pack (2026-11-02)
of the weekly vHMML Reading Room full dataset,
https://www.vhmml.org/datasets/vhmml_rr_fulldata.zip (listed on
https://www.vhmml.org/dataPortal/dataset; "updated weekly, include all
active records, use the vHMML Schema, and are line-delimited"). The
generation taken: Last-Modified `Sun, 01 Nov 2026 07:05:49 GMT`, zip
50,741,267 bytes, sha256
`c6453bf8842568b5d2355c625748a86af3abb984f39901fc01fcd8f2eff9d959`, one
member `vhmml_rr_fulldata.json` (757,403,565 bytes, dated 2026-11-01
01:05).

The member is a JSON array written one record per line: line 1 opens
with `[`, every record line ends with `,`, and the last line is an
EMPTY record `{}]`. The fixture keeps that shape byte-for-byte: the
real first line (record 2), six real record lines copied whole, and the
real last line. Re-pack recipe: copy those lines out of the member,
then `zip -X vhmml_rr_fulldata.zip vhmml_rr_fulldata.json`.

License (read 2026-11-02, the data-portal page and vhmml.org/terms):
"The manuscript metadata in vHMML Reading Room is available for reuse
under a Creative Commons 4.0 License: Creative Commons Attribution 4.0
International License (CC BY 4.0)." Images are licensed separately by
the holding institutions and are never taken.

## Delivery grains (census of the 2026-11-01 generation)

| grain | count | taken? |
|---|---|---|
| Reading Room record (one object: manuscript 242,381 · archival object 19,101 · print 1,682 · manuscript-print 825) | 263,989 | the Syriac + Ethiopic slice (below) is the document grain; the rest is out of this slice, counted |
| the trailing empty record `{}` | 1 | no — skipped by rule (counted) |
| part (`parts[]`, a codicological unit with its own date, origin, script) | — | rides the document's metadata |
| content item (`parts[].contents[]`, a text in the object) | — | metadata; an item WITH an incipit is a passage (the incipit is the source-language text) |
| the limited-fields JSON and CSV datasets | 2 files | no — subsets of the full dataset |
| the vHMML Museum dataset | 1 file | no — museum objects, not Reading Room records (a later look) |

The slice: a record whose parts name a Syriac or Ethiopic writing
system, or whose content items are in Syriac, Ge'ez or Amharic — 18,892
records (by both 15,372 · writing system only 3,187 · language only
333); 245,097 records are outside it. Of the 18,892, 5,338 carry at
least one incipit (11,392 incipits: Ethiopic script 7,048, Syriac
4,055, Arabic 258, other 31). The adapter's full parse of the
generation: 18,892 documents / 11,196 incipit passages; 196 incipits
skip by rule (no lect mapping, or the script does not fit the
catalogued language), so 13,670 documents are metadata-only (13,554
with no incipit at all + 116 whose every incipit skipped).

## What is here

- record 2 — Codex Seitenstettensis 261, Latin: OUTSIDE the slice.
- 2419 — Innsbruck Codex 401, a 1517 Syriac psalter with no incipit:
  the metadata-only document.
- 56720 — Montserrat MS Or. 10, three Arabic Garshuni hagiographies
  (Arabic in Syriac script, `ara-Syrc`), 1800–1900.
- 77409 — Frankfurt Ms. or. 40, two Ge'ez chronicles, 18th century,
  origin Ethiopia.
- 123348 — Diyarbakır Meryem Ana 3/7, dated 1716 (native date
  "2025 AG"), origin Diyarbakir, catalogued Syriac.
- 128042 — Baghdad N. 85: two Syriac items and one Neo-Aramaic item
  (the Neo-Aramaic incipit skips by rule — no registry claim yet).
- 200191 — EMML 6555, the Fetḥa nagaśt in Amharic, dated 1884, no
  shelf mark.
- the trailing `{}` — the rejected empty record.
