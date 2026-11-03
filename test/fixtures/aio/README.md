# AIO fixtures — Attic Inscriptions Online

Retrieved 2026-11-02 from https://www.atticinscriptions.com (British School
at Athens; ed. Stephen Lambert). License: CC BY-SA 3.0 — every inscription
page carries the CC badge `<a rel="license"
href="http://creativecommons.org/licenses/by-sa/3.0/deed.en_GB">` (visible in
the three `.html` files below, `#CC` block); the API's per-record field is
`"IPR": "Creative Commons"`.

The tree mirrors the `AioFetch` workdir layout.

## Delivery grains (enumerated at fixture time)

| Grain | URL | Disposition |
|---|---|---|
| listing page | `/inscription/list_all_inscriptions.json?page=<n>` (100 rows, `count` 3,466, `next`-linked, 35 pages) | the manifest — persisted as `list-page-<n>.json` sidecars, **skipped by rule** at discover (specimens: `list-page-1.json`, `list-page-2.json`) |
| API record | `/inscription/<source>/<ref>.json` | **accepted** — with the page below, the record (`records/aio-<n>.json`) |
| inscription page | `/inscription/<source>/<ref>` | **accepted** — the record's page layer (`records/aio-<n>.html`) |
| Greek view | `/inscription/<source>/<ref>?text_type=greek` | never fetched — the API record carries the same Greek as EpiDoc |
| images, AIO/AIUK Papers (PDF), browse/search pages | — | never fetched (not text records) |

## Files

- `records/aio-2103.{json,html}` — AIUK 11 (Ashmolean) no. 9 =
  `/inscription/AIUK11/9`, "List of ephebic friends", 175/6 AD: carries
  AIO's own Greek (`greek_epidoc`) beside the translation; a ToposText-only
  original location and a Pleiades-linked findspot (Athens).
- `records/aio-2586.{json,html}` — SEG 46.153 = `/inscription/SEG/46153`,
  "Decree of Halai Araphenides honouring <i>choregoi</i>, 341/0 BC":
  translation only, `<term>` pairs, a Pleiades `<placeName>`, inline HTML
  in the API title.
- `records/aio-3869.{json,html}` — IG II² 5271 = `/inscription/IGII2/5271`,
  "Kioniskos of Malthake of Hagnous", 2nd century BC: translation only, a
  `<persName>` (athnames ref), a rubric-only line (`relief`), Findspot
  "Unknown".
- `list-page-1.json`, `list-page-2.json` — TRIMMED listing pages: the
  `inscriptions` arrays hold the three fixture records' rows copied
  verbatim from the live pages 20, 24 and 35; `count` is re-set to the
  trimmed total (3) and page 1's `next` points at page 2 (page 2 carries
  `previous` and no `next`, as the live last page does). Everything else
  is upstream's own shape.

The record files are the bytes as served (JSON + HTML untouched).
