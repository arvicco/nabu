# Baxter-Sagart fixtures (P32-3 — the reconstruction shelf)

Real upstream rows from the **yawnoc TSV dump of the Baxter & Sagart 2014
Old Chinese reconstruction** (`BaxterSagartOC2015-10-13.tsv`,
github.com/yawnoc/baxter-sagart-old-chinese). Every kept line is
**byte-verbatim** upstream data (header + 9 selected rows; a post-check
asserted each emitted line is a literal line of the raw download); only
the row SET was trimmed.

- **Retrieved:** 2026-07-19, full download from the pinned commit
  `a448f53a311dc11fe903a98323a4cfd3ba5322c1` (master @ 2026-07-11, "Fix
  duplicated rows"):
  `https://raw.githubusercontent.com/yawnoc/baxter-sagart-old-chinese/a448f53a311dc11fe903a98323a4cfd3ba5322c1/BaxterSagartOC2015-10-13.tsv`
  — 410,266 B, 4,960 lines (header + 4,959 rows; 4,056 distinct
  characters, 722 polyphones, max 5 readings), sha256
  `0151fafbb65277c9a522e22ec08f18dd442839cc44f6fd026f15eb2ae9b3d8c3`
  (the adapter's frozen pin) → **header + 9 fixture rows**.
- **Selection (full-file line numbers):** 2 埃 + 3 哀 (plain rows), 6 +
  781 隘 (the polyphone pair ài/è → entry ids 隘 / 隘:2 — first
  occurrences in the FULL file too, so fixture ids match live ids),
  763 + 764 阿 (row 764's gloss is one of the file's **3 non-NFC rows**
  — decomposed marks in "ābhāsvara" — pinning the NFC boundary), 1975 瀾
  (the file's ONE empty-`py` row), 3242 + 3880 宿 (row 3880's gloss is
  the file's ONE CSV-quoted field: `"""mansion"" of the zodiac …` — the
  TSV is Excel-style tab-separated CSV, quoting semantics and all).

## The provenance chain (License)

The TSV repo carries **no license file** — it is a faithful dump ("minor
(whitespace) cleanup", repo README) of the xlsx published by the authors'
University of Michigan site, so the **content license governs**. The site
is dead (`ocbaxtersagart.lsait.lsa.umich.edu` → 403,
`sites.lsa.umich.edu/ocbaxtersagart` → 403, both verified 2026-07-19).
Its grant survives in the Wayback capture of **2025-03-12**:

> The files on this page (related to Baxter & Sagart 2014: Old Chinese: a
> new reconstruction, New York, Oxford University Press) by William H.
> Baxter and Laurent Sagart are licensed under CC BY 4.0

— `http://web.archive.org/web/20250312164901/http://ocbaxtersagart.lsait.lsa.umich.edu/`
(capture also names `BaxterSagartOC2015-10-13.xlsx` — the second witness
of the content, not fetched). → `attribution`, credited to Baxter &
Sagart 2014.

## Upstream format reality (what these fixtures preserve)

- Header `zi py MC <unnamed> OC gloss GSR HYDZD rad str Unicode` — the
  **4th column is unnamed** (the MC structural analysis, `('- + -oj A)`);
  FlatCsvParser keys it `""`.
- **4,708 of 4,959 rows carry a trailing space in `OC`** (`*qˤə `) —
  stripped at parse.
- One row (瀾) has an empty `py`; 3 rows (阿/會/亘) have non-NFC glosses;
  one row (宿 xiù) has a CSV-quoted gloss.
