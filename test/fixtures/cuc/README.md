# CUC fixture — Copenhagen Ugaritic Corpus (CACCHT/DT-UCPH, P31-4)

Byte-verbatim trimmed slices of the pinned `tf/0.2.8` Text-Fabric dataset
of [github.com/DT-UCPH/cuc](https://github.com/DT-UCPH/cuc).

- **Retrieved:** 2026-07-19, from commit
  `0408967b1808c1f22c69e299d302b1e7b5e26354` (main), via raw GETs of
  `https://raw.githubusercontent.com/DT-UCPH/cuc/main/tf/0.2.8/<name>.tf`.
- **Layout:** the fixture mirrors the sparse workdir the adapter fetches
  (`tf/0.2.8/*.tf`); the license-bearing `README.md` (also in the sparse
  cone) is quoted below rather than checked in — the adapter never parses
  it. Upstream's `__checkout__.txt` marker is not part of the dataset.
- **Trim recipe:** headers byte-verbatim; kept data lines byte-verbatim
  for the ten tablets below (their slot ranges + their column/line/word/
  tablet nodes), with an explicit `node<TAB>` anchor added where a dropped
  region precedes (the dss "gap-anchored" recipe); empty-value lines drop
  (the family loads them as absent either way). `otype.tf` and `otext.tf`
  ride WHOLE — the census of record.

## Upstream census (at the pinned commit, from otype.tf — checked in WHOLE)

`tf/0.2.8` = 19 feature files ≈ 3.5 MB. otype.tf declares: **146,017
signs / 27,770 words / 7,616 lines / 334 columns / 279 tablets** — every
P31-4 briefed number exact. (The upstream README says "278 tablets" —
its own otype.tf counts 279; otype wins, discrepancy noted honestly.)
Corpus-wide facts the fixture tablets were chosen to attest, censused at
the pin:

- tablet.tf names are UNIFORMLY `KTU <n>.<n>`, all 279 unique → the urn
  mint (`urn:nabu:cuc:ktu-<n>.<n>`) asserts that shape and fails loudly
  on drift.
- Every line lies inside exactly one column and one tablet; **(tablet,
  stripped column label, line number) is globally unique** — the passage
  citation. ONE column label corpus-wide carries a trailing space
  (`"I "`, KTU 1.50) → stripped in urns, verbatim in annotations.
- `language.tf` is uniformly `Ugaritic` (27,770 words) → uga; anything
  else is a ParseError.
- The sign stream has 38 distinct single-char values incl. TWO space
  chars (U+0020 ×62,931 and NBSP U+00A0 ×5,325), `x` (illegible, 6,342),
  `.` (517), `?` (16), `-` (10), `…` (3), `Ṯ` (1).
- **72 lines render whitespace-only** via `{sign}` (fully illegible
  regions) → skipped by the adapter, listed in document metadata
  `empty_lines`.
- Words are contiguous, never cross line boundaries; word/line/column/
  tablet node order equals slot order.
- `side.tf` covers 7,589 of 7,616 lines with verbatim quirks: `rev.`
  5,163 / `le.e.` 1,228 / `up.e.` 542 / `low.e.` 392 / `rev. ` 183
  (trailing space) / `rev.\t` 43 (trailing TAB) / `rev.?` 24 / `obv.` 12
  / `low.e. ` 2. Absent is absent — never guessed.
- `emen.tf` values: restored 51,597 / excised 396 / missing 123 /
  redundant 72 / remark 43. `cert.tf`: True 53,664 / False 23,551.
  `alt.tf`: 79 signs. `cont.tf`: 102 signs. `tablet_info.tf`: 2 notes
  (KTU 1.7, KTU 1.84).

## License (verbatim, retrieved 2026-07-19)

Every `.tf` header carries the machine-readable pair — NB upstream's
BRITISH spelling of the key:

> @licence=Creative Commons Attribution-NonCommercial 4.0 International License
> @licenceUrl=http://creativecommons.org/licenses/by-nc/4.0/

and the repo README carries the CC BY-NC 4.0 badge and Zenodo DOI
`10.5281/zenodo.10695308` → source class `nc`.

## The ten tablet slices (5,090 slots / 250 lines / ~1,030 words)

| tablet | node | slots | lines | why |
|---|---|---|---|---|
| KTU 1.7 | 153974 | 1,438 | 56 | `tablet_info` note ("very damaged", the Pardee citation) verbatim; 3 whitespace-only lines (48/50/53) → the `empty_lines` witness; `rev. ` trailing-space side; `?` signs |
| KTU 1.15 | 153976 | 1,988 | 136 | Keret — the ONLY multi-column citation witness with all of I–VI; NBSP signs; excised/redundant emen |
| KTU 1.21 | 153982 | 362 | 14 | TWO columns (II, V) with line 1 in BOTH → the column-citation disambiguation pin; the `alt` sign (slot 55356, l→b); `le.e.` side |
| KTU 1.24 | 153985 | 902 | 50 | Nikkal — the token/sign-lane pin (word 166592 "ašr"); emen `missing` ×6 (line 15) + `excised`; word-divider trailers (. / 𐎟) |
| KTU 1.43 | 153995 | 483 | 26 | `cont` line-continuation signs (line 2, "ilm"); `rev.\t` tab-suffixed side; excised |
| KTU 1.50 | 154001 | 280 | 11 | THE `"I "` trailing-space column label (urn strips, annotation verbatim); restored lines |
| KTU 1.54 | 154002 | 125 | 14 | emen `remark` ×2 (line 6); 1 whitespace-only line (5) |
| KTU 1.105 | 154045 | 418 | 27 | emen `redundant` (line 11) + `missing` (line 12) in a ritual text |
| KTU 1.172 | 154099 | 338 | 31 | `rev.?` uncertain-side labels (lines 17–31) |
| KTU 2.103 | 154202 | 744 | 33 | the KTU 2 epistolary genre; the `-` dash signs (line 27 renders "---") |

Not attested in the slices (real upstream, documented so their absence is
honest): the `…` sign (KTU 1.6, 2.99), `Ṯ` (KTU 1.5), `obv.` and
`low.e. ` sides, the second `tablet_info` note (KTU 1.84).
