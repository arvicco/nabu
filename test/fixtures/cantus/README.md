# Cantus Database fixtures

Real upstream samples from the Cantus Database (https://cantusdatabase.org),
retrieved 2026-11-04. License: Creative Commons Attribution-NonCommercial-
ShareAlike 4.0 International (every page footer: "This work is licensed under
a Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International
License.", https://creativecommons.org/licenses/by-nc-sa/4.0/).

The tree mirrors the fetch layout (`Nabu::CantusFetch`):

| File | Retrieved from | Trimming |
|------|----------------|----------|
| `json-sources.json` | https://cantusdatabase.org/json-sources/ | the 305-entry object cut to the four fixture sources (entries verbatim) |
| `sources-page-1.html` | https://cantusdatabase.org/sources/?segment=4063 | see below |
| `sources-page-2.html` | https://cantusdatabase.org/sources/?segment=4063&page=2 | see below |
| `sources-page-3.html` | https://cantusdatabase.org/sources/?segment=4063&page=3 | see below |
| `sources/693666.csv` | https://cantusdatabase.org/source/693666/csv/ | whole (2 rows) — CDN-Mrb MS Medieval 0209, a 15th-c. Italian gradual leaf (Montréal, McGill) |
| `sources/1000458.csv` | https://cantusdatabase.org/source/1000458/csv/ | whole (1 row) — "Cantus D:0pb1q", a Halifax private-collection leaf with no century or provenance in the listing |
| `sources/123717.csv` | https://cantusdatabase.org/source/123717/csv/ | 25 of 2,192 rows — CH-SGs 390, the Hartker Antiphoner (St. Gall, 975–1000): the first 22 rows (responsories, verses, antiphons, tropes, genre-less rows) + rows 1779 (`--*`), 2113 (`LACUNA`) and 2183 |
| `sources/123738.csv` | https://cantusdatabase.org/source/123738/csv/ | 14 of 1,320 rows — HR-Dsmbb Badija V (Dominican antiphoner, 13th c. 2nd half): the first 10 rows (incipit-only) + rows 134–135, 152 and 1228 |

CSV trimming kept the header and whole rows (re-serialized with stdlib CSV,
CRLF as upstream). The browse pages were trimmed with Nokogiri: table rows
other than the fixture sources removed, the filter `<select>` option lists
emptied (kept the first option), and — so the trimmed set stays
self-consistent — the "Displaying a-b of N sources." line, the pagination
block (3 pages) and each kept row's Chants count (the trimmed CSV's row
count) EDITED. Everything else is upstream's markup as served.

## Delivery grains upstream serves (enumerated 2026-11-04)

| Grain | Taken? |
|-------|--------|
| `/json-sources/` — the CSV manifest, 305 sources (= the "Cantus DB: Sources with Inventories" segment 4063) | sidecar (the fetch manifest) |
| Browse Sources pages, segment 4063 (4 × 100 rows: country, institution, siglum, summary, curated century + provenance links, chant/melody counts) | sidecar — per-source metadata, never documents |
| `/source/<id>/csv/` — one row per chant record | **ACCEPTED**: a record carrying full text = one document |
| a chant record without full text (incipit only, or a standardized field that only repeats the incipit) | **REJECTED — skipped by rule**, counted in `discovery_skips` (pinned: the first 10 Badija V rows, Badija row 134 "Jerusalem gaude gaudio magno", Hartker rows `--*` / `LACUNA`) |
| Sequence Database segment 4064 (325 sources, Bower's Clavis Sequentiarum — incipit-only sequence rows keyed to Analecta Hymnica numbers, e.g. `/source/123896/csv/`: `cod. 375,…,p. 237,a01,Natus ante saecula,,,Sq,,ah53015,…`) | never listed by `/json-sources/`, never fetched |
| the ~109 other "All Sources" entries (739 in all) — descriptions without inventories | never fetched |
| `/chant/<id>/` pages, `/source/<id>/` pages (HTML, or JSON under `Accept: application/json`: description, free-text date, provenance), melody search, images | never fetched — the CSV carries every chant field; the listing carries the curated century/provenance |

## Census (2026-11-04)

- 305 sources listed = 305 manifest entries; the listing's Chants column sums
  to **449,132** records; the export row count equals the listing count on
  every source probed (15/15).
- Fixture totals: 42 chant records → 28 accepted (26 with manuscript text,
  2 standardized-only), 14 skipped by rule (11 with no full text, 3 whose
  standardized text only repeats the incipit).
- A random 12-source sample (20,732 rows): 47.1% manuscript text, 11.3%
  standardized-only full text, 5.7% standardized echoing the incipit, 35.9%
  no full text — per-source shares range from 0% to 100% full text.
