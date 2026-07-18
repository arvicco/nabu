# OpenEtruscan fixtures — P29-0

Trimmed real upstream samples for the `open-etruscan` adapter
(`Nabu::Adapters::OpenEtruscan` / `FlatCsvParser` — the first flat-csv
corpus) and the `AxisBuilder::OpenEtruscanDates` extractor. Retrieved
**2026-07-18** (the sanctioned fixture snapshot, not a full sync). Layout
mirrors the canonical workdir the adapter fetches into: `corpus/` (the
Zenodo artifact) + `findspots/` (the Larth sidecar).

## Upstream artifacts (both sha-pinned in the adapter)

- `corpus/openetruscan_clean.csv` — from
  `https://zenodo.org/api/records/20075836/files/openetruscan_clean.csv/content`
  (record 20075836, **"Etruscan Machine Learning Corpus" v1.0.0**,
  published 2026-05-07, OpenEtruscan Project / Edoardo Panichi). Full
  artifact: 770,613 B, 6,567 data rows, sha256
  `4fc09af94005655bfe26affeeb48295c88606ae23c8dbc33ff5436f9083f69f8`
  (md5 `f9cfce78fcafe48edbfc12888380c90c` = Zenodo's own checksum field).
  **Version check 2026-07-18: no v2 deposit exists** — v1.0.0 is the only
  version under concept record 20075835.
- `findspots/Etruscan.csv` — from
  `https://raw.githubusercontent.com/GianlucaVico/Larth-Etruscan-NLP/daf4972175f45b48188fe36671db3a0e081e5130/Data/Etruscan.csv`
  (the pinned main commit of 2026-07-14 — the commit that added LICENSE).
  Full artifact: 302,495 B, 7,139 data rows (456 city-tagged, 397 unique
  city-tagged ids), sha256
  `e00bbff1858dbfd24579785784ca913a1dfc71f1722b8a6f907acba5b56a260a`.

## License (verbatim)

- Zenodo record license field: `cc-by-4.0` → **CC BY 4.0**, class
  `attribution`.
- Larth repo `LICENSE`: *"Attribution 4.0 International"* (CC BY 4.0 full
  text; re-verified 2026-07-18) → same class. Credit: Vico & Spanakis
  2023, "Larth: Dataset and Machine Translation for Etruscan", ALP2023.

## Corpus rows kept (header + 10 records, byte-verbatim; upstream CSV
record numbers counted with the header as record 1)

| id | record | Why |
|---|---|---|
| CIE 2609 | 2 | clean, Old Italic raw + transliterated/italic/words layers — the layer-annotation exemplar |
| CIE 2615 | 3 | clean, undated/unplaced — the honest `undated` count |
| CIE 2616 | 6 | **ocr_failed** ("IAN8VJV1…" digit-substitution junk) — the skip-by-rule pin |
| Ve 6.2 | 9 | dated 650.0–625.0 (BCE-positive) + `<ni>` editorial marker + translation → the -en sibling |
| ETP 313 | 23 | dated 100.0–**0.0** — the year-0 tripwire, no findspot → no axis row |
| CIE 262 | 111 | **needs_review**: mirror-glyph raw (`IИAƧUƧ…`) vs deterministically mapped transliteration — the quality-tag pin |
| ETP 240 | 173 | dated 100.0–**0.0** WITH findspot (Ager Saenensis) — invalid date must not cost the place |
| CIE 52a, b | 4441 | quoted comma-carrying id + MULTI-LINE quoted field (the two laminae) — the CSV-record integrity pin; also ocr_failed |
| ETP 192 | 4835 | dated 275.0–250.0 + translation + findspot (Ager Tarquiniensis) — the full-join exemplar |
| Cr 2.20 | 6561 | dated 675.0–650.0 + translation + findspot (Caere) — the sign-flip regression pin (-675/-650) |

## Findspot rows kept (header + 6 records, byte-verbatim)

| ID | record | Why |
|---|---|---|
| ETP 192 | 2 | joins the corpus fixture (Ager Tarquiniensis); note the trailing-space id upstream pads |
| Cr 2.20 | 3 | joins (Caere) |
| ETP 240 | 169 | joins (Ager Saenensis) — the place that must survive the year-0 date |
| ETP 285 | 198 + 478 | the ONE conflicting duplicate in the full file (Clusium vs Ager Clusinus) — the first-wins pin |
| Po 4.4 | 240 | city-tagged (Populonia) but its corpus row is ocr_failed — the honest join-miss residue (396/397 unique ids join minted docs) |

## Census at fixture time (full artifacts)

- data_quality: clean 6,094 · needs_review 154 · **ocr_failed 319**
  (skipped by rule).
- Dated rows 307, ALL BCE-positive (`year_from >= year_to`, no negatives,
  no one-sided pairs); 3 rows carry a `0.0` bound (ETP 313/240/274) — the
  year-0 tripwire, counted invalid, never stored.
- Translations 1,800 rows → -en siblings.
- Findspot join: 397 unique city-tagged Larth ids, ALL present in the
  corpus id space; 396 join minted documents (Po 4.4's corpus row is
  ocr_failed).
- id → urn mint (`OpenEtruscan.urn_for`): 6,567 ids, 0 slug collisions.

Data-quality caveat carried in docs/02-sources.md, the author's own words
(recorded at survey time, P17-5): "many inscriptions are really noisy and
not really reliable".
