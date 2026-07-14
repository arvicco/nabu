# IE-CoR fixtures (P18-5 — the cognacy matrix)

Real upstream samples from **IE-CoR, the Indo-European Cognate
Relationships database** (Heggarty, Anderson & Scarborough et al. 2023,
*Science* 381, eabg0818) — the CLDF bundle `lexibank/iecor` **v1.2**.
Every kept CSV record is **byte-verbatim** upstream data (the whole-file
csv round-trip was verified byte-identical before trimming, so record
re-serialization introduced no drift); only the record SET was trimmed.

- **Retrieved:** 2026-07-14, from the Zenodo versioned record
  <https://zenodo.org/records/13304537> (DOI 10.5281/zenodo.13304537 =
  v1.2, 2024-08-12; concept DOI 10.5281/zenodo.8089433), file
  `lexibank/iecor-v1.2.zip` — 6,394,446 B, md5
  `2d4e742ab755c0f506e91a74e6b6e2ad` (Zenodo's published checksum,
  matched), sha256
  `ff249cffc1bba75048d9eace3f9d95bf723f5a5c406f75ec739ab97586cc03c4`
  (the adapter's `RELEASE_SHA256` pin). Full-file census at retrieval:
  160 varieties / 170 parameters / 25,731 forms / 25,741 judgments /
  5,039 cognate-set rows (4,981 with ≥1 judgment) / 1,036 loan events.
- **License:** CC BY 4.0 — cldf/README.md verbatim: "This dataset is
  licensed under a https://creativecommons.org/licenses/by/4.0/ license";
  GitHub license field CC-BY-4.0; Zenodo record cc-by-4.0.
- The bundle's `cldf-metadata.json`, `sources.bib` and the auxiliary
  tables (clades.csv, authors.csv) are **not snapshotted**: the parser
  reads the six data tables by their fixed CLDF names and never consults
  the metadata document (noted in the parser header).

## What was kept (the pie-survey §7 sketch, per-fixture quirk)

- `cldf/languages.csv` — 13 of 160 varieties: the 12 held-mapped ones
  (Hittite 80, OCS 100, Vedic: Early 105, Greek: Ancient 110 / NT 177 /
  Mycenaean 173, Latin 112, Armenian: Classical 129, Old Novgorod 245,
  Slovene: Early Modern 259, Old English 298, Gothic 303) + Lithuanian 46
  (a modern variety, so held-scoping stays quiet; also the calc-root
  set's witness). Note Slovene: Early Modern carries ISO `slv` while the
  catalog tag is `sl` — the variety map, not the ISO column, decides.
- `cldf/cognatesets.csv` — 5 sets:
  - **6458** "heart" — the 11-witness golden (`Root_Form` \*k̑erd-, k +
    U+0311: the kaikki cross-witness fold pin).
  - **1171** "skin" — Proto-Slavic \*kož- ← Turkic, the loan-event set.
  - **1846** "back" — `Root_Form` EMPTY, `Root_Form_calc` nùgara with an
    empty `Root_Language_calc` (the calc-fallback + `ine` collective-tag
    pin).
  - **2280** "full" — a singleton (Hittite šūu- / šūuau̯-; also the
    spaced-slash stem-alternant split and the ?-doubt root ?\*seu̯H-).
  - **1105** "ash" — root ?\*pel(h₁)- (doubt prefix + inline parenthesized
    laryngeal: the paren-strip fold pin).
- `cldf/forms.csv` — 17 member forms of those sets, trimmed to the 13
  fixture varieties: the heart set's 11 held witnesses (polytonic grc ×2
  varieties, Gothic 𐌷𐌰𐌹𐍂𐍄𐍉/hairto dual script, Bohorič ſerzè with EMPTY
  native_script, hyphenated hit stems, Devanagari+accented-IAST san,
  Novgorod сердьце); the loan set's chu/orv/sl members; Lithuanian
  nùgara; Hittite šūu- / šūuau̯-; and OCS form 100-4-1 "попєлъ, пєпєлъ"
  (the comma-multiform split-policy pin).
- `cldf/cognates.csv` — the 17 matching membership judgments.
- `cldf/parameters.csv` — the 5 concepts those sets need (ash 4, back 6,
  full 62, heart 73, skin 144).
- `cldf/loans.csv` — set 1171's event (Source_languoid "Turkic", no
  source set/form — the languoid-only shape).

## Refresh recipe

Download the Zenodo zip above (immutable — a byte drift is an incident,
not an update), unzip, and re-trim with the ID sets listed in
`manifest.yml` (languages by ID; sets by Cognateset_ID; forms/cognates =
members of those sets whose Language_ID is in the fixture variety set;
loans by Cognateset_ID). Line endings are CRLF upstream and preserved.
