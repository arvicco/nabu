# syriac-htr-gt fixtures

Real pages of the Syriac ground truth of the Vienna HTR Winter Schools
(Österreichische Akademie der Wissenschaften, Institut für
Mittelalterforschung), copied byte-verbatim from the two Zenodo records'
`page.zip` archives, retrieved 2026-11-22:

| manuscript dir | record | zip | md5 (the record's own) | sha256 |
|---|---|---|---|---|
| `onb-cod-syr-1/` | [14714089](https://doi.org/10.5281/zenodo.14714089) (v1.0.0, 2025-01-21) — Vienna, ÖNB Cod. Syr. 1, Serto | `https://zenodo.org/records/14714089/files/page.zip` (1,113,171 B) | `1e06e5814a3c08daf4e9158289231dc1` | `649814702deb0599bd288642560d59848d9725f202d6fc705a0e28025fb9b19f` |
| `smmj-36/` | [18157525](https://doi.org/10.5281/zenodo.18157525) (2026-01-05) — Jerusalem, St Mark's Monastery MS 36, Estrangelo | `https://zenodo.org/records/18157525/files/page.zip` (2,457,701 B) | `b88c33b0dd0117db0f88b24e5e26cb6e` | `cf5fb067c88e0138aeb326a5832e186e7e6a025ea13b0a5c8d8eeda244d10cd0` |

The layout mirrors `canonical/syriac-htr-gt/` after the fetch: one directory
per manuscript, each holding its zip's unpacked tree (ZipFetch strips
14714089's single `page/` top directory; 18157525's pages sit at the zip root).

## License (read first-hand 2026-11-22)

Both records' Zenodo license field: `cc-by-4.0`. Both deposited
`htr-united.yml`: `license: name: CC-BY 4.0, url:
https://creativecommons.org/licenses/by/4.0/`. Both deposited `CITATION.cff`:
`license: CC-BY-SA-4.0`. Both descriptions: "all transcriptions are licensed
under the Creative Commons 4 licence". Attribution-class either way → `attribution`,
the share-alike reading honored as the stricter. The page images are the
holding libraries' (ÖNB; St Mark's Syrian Orthodox Monastery) and are not
held here.

## Delivery grains

| record | file | taken? |
|---|---|---|
| 14714089 | `page.zip` — `page/` with 140 PAGE 2019 XML pages + `page/.DS_Store` | **accepted** (document = page) |
| 14714089 | `images.zip` (468,604,566 B) | rejected — the page scans, never fetched |
| 14714089 | `CITATION.cff`, `htr-united.yml` | rejected — record metadata, transcribed into the adapter's MANUSCRIPTS |
| 18157525 | `page.zip` — 133 PAGE 2013 XML pages (Transkribus export) | **accepted** (document = page) |
| 18157525 | `alto.zip` (2,618,558 B) | rejected — the same lines exported from eScriptorium as ALTO (a second format), never fetched |
| 18157525 | `images.zip` (970,176,428 B) | rejected — the page scans, never fetched |
| 18157525 | `CITATION.cff`, `htr-united.yml` | rejected — record metadata, transcribed into MANUSCRIPTS |

Inside the fetched trees the one non-page member is 14714089's macOS Finder
file `page/.DS_Store` (6,148 B) — pinned here whole as
`onb-cod-syr-1/.DS_Store` (a gitignored name, force-added) and skipped by rule
in `discovery_skips`.

## Census (both zips through the page-xml family, 2026-11-22)

| manuscript | pages | regions | TextLines | empty | passages | upstream's own count |
|---|---:|---:|---:|---:|---:|---|
| onb-cod-syr-1 | 140 | 498 | 2,875 | 5 | 2,870 | htr-united `lines: 2869` (a one-line residue upstream does not explain) |
| smmj-36 | 133 | 1,056 | 17,836 | 0 | 17,836 | htr-united `lines: 17836`, `characters: 311392` — both exact |

Dry parse: 273 documents / 20,706 passages, 0 errors, 1 file skipped by rule.
Region types (SegmOnto): MainZone, MainZone-gold (14714089 only),
MarginTextZone, NumberingZone, and untyped (Transkribus regions without a
structure tag; eScriptorium's line-only dummy blocks). Transkribus tags:
14714089 unclear 33 · abbrev 13; 18157525 sic 128 · unclear 103 · person 41 ·
Variant 20 · abbrev 11 · Subtitle 7 · add 5. 57 lines carry non-canonical
combining-mark order (NFC'd at the boundary); 14714089's transcribers write
~900 no-break spaces (U+00A0), kept verbatim.

## Files

- `onb-cod-syr-1/0001_00000016.xml` — f. 1v: a marginal word (ܚܨܪܘܢ), the
  six-line incipit in gold block letters (`MainZone-gold`, every line tagged
  unclear) — "With the power of our Lord Jesus Christ we begin to write the
  book of the holy Gospel: first, the Gospel of Matthew, who spoke Hebrew in
  the land of Palestine" — then Matthew 1:1 and the folio number `1v`.
- `onb-cod-syr-1/0159_00000174.xml` — f. 80v: two EMPTY margin lines (r1.l1,
  r2.l1 — they mint nothing) and untyped Transkribus regions (tr_1, tr_2).
- `onb-cod-syr-1/0179_00000194.xml` — f. 90v (Matthew 11): a line with dot
  above before dot below (U+0307 U+0323 — non-NFC; NFC'd at the boundary).
- `onb-cod-syr-1/0319_00000334.xml` — the last image: the colophon, "ܫܢܬ ܐܠܦ ܘܚܡܫܡܐ
  ܘ ܚܡܫܝܢ ܘܐܪܒܥܐ ܡܫܝܚ̈ܝܬܐ: ܒܐܝܪܚ ܬܡܘܙ ܬܡܢܝܐ ܘܥܣܪܝܢ ܒܗ." — the year 1554
  of the Messiah, Tammuz 28 (the records say "dated 1545").
- `onb-cod-syr-1/.DS_Store` — the rejected grain's specimen (see above).
- `smmj-36/0071_SMMJ_00036__076.xml` — a bifolio image (Luke 12), four text
  columns + margins, Transkribus status DONE (pageNr 71, docId 11622279):
  unclear with its `alternative`, sic with its `correction`, person tags.
