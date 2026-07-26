# cldf-spine fixtures (P46-6 — the CLDF reference spine)

Real upstream samples for **Nabu::CldfSpine**, the thin Concepticon +
Glottolog resolver instrument (kind: module). Kept rows are
**byte-verbatim** upstream lines; only the row SET was trimmed (both
files are one-record-per-line — no embedded newlines in the kept rows,
verified at trim time). Layout mirrors the post-fetch canonical tree
(`concepticon/` + `glottolog/` subdirs, each with its own FileFetch
state in real syncs).

- **Retrieved:** 2026-07-26, from the tag-pinned raw URLs (a raw URL at
  a release tag is a stable git blob — byte-stable, unlike generated
  zipballs):
  - `concepticon/concepticon.tsv` from
    <https://raw.githubusercontent.com/concepticon/concepticon-data/v3.4.0/concepticondata/concepticon.tsv>
    — full file 453,281 B, 4,033 concepts, sha256
    `f96a72b8dc18053098378cee1e18b13ba923d3380340b4164e8a7db415c5d4b8`.
  - `glottolog/languages.csv` from
    <https://raw.githubusercontent.com/glottolog/glottolog-cldf/v5.3/cldf/languages.csv>
    — full file 2,462,735 B, 27,177 languoids, sha256
    `1a50a393bc81568b656f9522be18aa4f80f38e94309ba6c863d583234adfbb89`.
- **License:** CC BY 4.0 both — Concepticon's `.zenodo.json` at v3.4.0
  declares `"license": {"id": "CC-BY-4.0"}`; the glottolog-cldf bundle's
  own `dc:license` (cldf/README.md at v5.3) is
  <https://creativecommons.org/licenses/by/4.0/>.

## What was kept

- `concepticon/concepticon.tsv` — header + 10 of 4,033 concepts: the six
  the WOLD fixture's parameters cite (965 WORLD, 1732 SKY, 890 MULE,
  1290 ELEPHANT, 1524 WINE, 1362 STREET), the three the CLICS fixture
  triangle carries (1060 CHILD-IN-LAW, 2264 DAUGHTER-IN-LAW (OF WOMAN),
  2266 SON-IN-LAW (OF WOMAN)), and 170 FATHER'S SISTER — a RETIRED
  concept whose `REPLACEMENT_ID` (2691) pins the verbatim-pointer rule.
- `glottolog/languages.csv` — header + 11 of 27,177 languoids: the WOLD
  fixture's vocabulary codes (stan1293 English, oldh1241 Old High
  German, swah1253 Swahili), its donor codes (lati1261 Latin, stan1318
  Standard Arabic, mode1248 Modern Greek, noon1243), oldn1244 Old Norse,
  and the three family rows the one-hop classification needs (indo1319
  Indo-European, afro1255 Afro-Asiatic, atla1278 Atlantic-Congo).
  **noon1243 is the upstream-defect pin:** WOLD v4.2 tags its "Old
  Norse" donor with that glottocode, but Glottolog resolves noon1243 to
  **Noone** (Atlantic-Congo, Cameroon) — real Old Norse is oldn1244.
  Both rows are kept so the test suite pins the discrepancy verbatim
  (and the WOLD donor map keys on languoid NAMES because of it).

## Refresh recipe

Re-download the two tag-pinned URLs above (immutable at their tags —
byte drift is an incident, not an update) and re-trim: concepticon by
column 1 (`ID`) against the id set above; glottolog by column 1 (`ID`)
against the glottocode set above. Header lines kept verbatim; LF line
endings upstream, preserved.
