# hittite-glossed fixtures

Real trims from `7000_hitt_txts_wGloss.csv` (Zenodo record 14266302,
DOI 10.5281/zenodo.14266302 v1.0, CC BY 4.0), retrieved 2026-09-29
from
https://zenodo.org/api/records/14266302/files/7000_hitt_txts_wGloss.csv/content
(12,779,728 bytes, sha256
25fd1e44940f4327ce2448c7d25eb728f2ecb345bb76c94f05fed66cca0e0129).

Trim recipe: the header line + every row (verbatim raw lines) whose
`txtid` is one of three censused texts:

- `IBoT 1.30+` (41 rows, CTH 821) — a multi-line text whose id carries
  the "+" join marker (slug shape).
- `KBo 35.261` (16 rows, CTH 628) — carries the corpus's empty-gloss
  token shape (27 empty `gloss` fields corpus-wide).
- `Bo 8897` (4 rows) — the multi-CTH duplicate-index shape: the same
  two lines indexed under CTH 615 and CTH 670 (7 such texts
  corpus-wide).

Re-cut: download the versioned file, filter rows by the `txtid`
column, keep raw lines unmodified.
